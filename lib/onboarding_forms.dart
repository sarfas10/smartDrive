// onboarding_form.dart
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class OnboardingForm extends StatefulWidget {
  const OnboardingForm({super.key});

  @override
  State<OnboardingForm> createState() => _OnboardingFormState();
}

class _OnboardingFormState extends State<OnboardingForm> {
  final _personalKey = GlobalKey<FormState>();
  final _kycKey = GlobalKey<FormState>();

  // ===== Cloudinary config (replace with your real values) =====
  static const String _cloudName = 'dxeunc4vd';
  static const String _unsignedUploadPreset = 'smartDrive';
  static const String _baseFolder = 'smartDrive';

  // ===== Personal fields =====
  final _address1Ctrl = TextEditingController();
  final _address2Ctrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  DateTime? _dob;
  double? _homeLat;
  double? _homeLng;
  XFile? _profilePhoto; // local pick
  String? _photoUrl;    // existing remote photo

  // ===== KYC fields =====
  String? _docType; // Aadhaar / PAN / VoterId
  XFile? _docFront;
  XFile? _docBack;

  // ===== State / Flow =====
  int _step = 0; // 0 = Personal, 1 = KYC
  bool _saving = false;
  bool _loadingState = true;
  String? _onboardingStatus; // 'personal_saved','kyc_pending','kyc_approved','kyc_rejected'
  String? _kycStatus;        // 'pending','approved','rejected'
  final _picker = ImagePicker();

  bool get _isUnderVerification =>
      (_kycStatus == 'pending') || (_onboardingStatus == 'kyc_pending');
  bool get _isApproved =>
      _kycStatus == 'approved' || _onboardingStatus == 'kyc_approved';
  bool get _isReadOnly => _isUnderVerification || _isApproved;

  @override
  void initState() {
    super.initState();
    _hydrateState();
  }

  @override
  void dispose() {
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  bool _isPersonalCompleteFromData(Map<String, dynamic> data) {
    final addr1 = (data['address_line1'] ?? '').toString().trim();
    final zip = (data['zipcode'] ?? '').toString().trim();
    final dob = data['dob'];
    final lat = data['home_lat'];
    final lng = data['home_lng'];
    return addr1.isNotEmpty &&
        zip.isNotEmpty &&
        dob != null &&
        lat != null &&
        lng != null;
  }

  // ================== Hydrate from Firestore ONLY ==================
  Future<void> _hydrateState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingState = false);
      return;
    }

    try {
      // 1) Profile doc
      final profRef =
          FirebaseFirestore.instance.collection('user_profiles').doc(user.uid);
      final profSnap = await profRef.get();

      Map<String, dynamic>? data;
      if (profSnap.exists) {
        data = profSnap.data();
        _onboardingStatus = data?['onboarding_status'] as String?;
        _photoUrl = data?['photo_url'] as String?;
        _address1Ctrl.text = (data?['address_line1'] ?? '') as String;
        _address2Ctrl.text = (data?['address_line2'] ?? '') as String? ?? '';
        _zipCtrl.text = (data?['zipcode'] ?? '') as String;
        final ts = data?['dob'] as Timestamp?;
        _dob = ts?.toDate();
        _homeLat = (data?['home_lat'] as num?)?.toDouble();
        _homeLng = (data?['home_lng'] as num?)?.toDouble();
      }

      // 2) Latest KYC status
      final kycQ = await FirebaseFirestore.instance
          .collection('documents')
          .where('uid', isEqualTo: user.uid)
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (kycQ.docs.isNotEmpty) {
        _kycStatus = kycQ.docs.first.data()['status'] as String?;
      }

      // 3) Decide step
      if (_isUnderVerification || _isApproved) {
        _step = 1; // show KYC (locked)
      } else if (_onboardingStatus == 'personal_saved' ||
          (data != null && _isPersonalCompleteFromData(data))) {
        // Either marked by flag OR data satisfies required fields
        _step = 1; // jump to KYC
      } else {
        _step = 0; // start at Personal
      }
    } catch (_) {
      // If anything fails, start from Personal
      _step = 0;
    } finally {
      if (mounted) setState(() => _loadingState = false);
    }
  }

  // ================== Image Pick (no crop) ==================
  Future<XFile?> _pickImage() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
  }

  Future<void> _pickAvatar() async {
    final x = await _pickImage();
    if (x != null) setState(() => _profilePhoto = x);
  }

  // ================== Cloudinary Upload ==================
  Future<String> _uploadToCloudinary({
    required XFile xfile,
    required String publicId,
    String? folder,
  }) async {
    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _unsignedUploadPreset
      ..fields['public_id'] = publicId;

    if (folder != null && folder.isNotEmpty) {
      req.fields['folder'] = folder;
    }

    if (kIsWeb) {
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'upload.jpg';
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      ));
    } else {
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        xfile.path,
        filename: xfile.name.isNotEmpty ? xfile.name : 'upload.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['secure_url'] as String?) ?? (json['url'] as String);
  }

  // ================== Location ==================
  Future<void> _useCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')));
      }
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _homeLat = pos.latitude;
      _homeLng = pos.longitude;
    });
  }

  // ================== Save Personal ==================
  Future<void> _savePersonal() async {
    if (!_personalKey.currentState!.validate()) return;
    if (_isReadOnly) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }

    setState(() => _saving = true);
    try {
      String? photoUrl = _photoUrl;
      if (_profilePhoto != null) {
        photoUrl = await _uploadToCloudinary(
          xfile: _profilePhoto!,
          publicId: 'profile',
          folder: '$_baseFolder/users/${user.uid}',
        );
      }

      final data = {
        'uid': user.uid,
        'address_line1': _address1Ctrl.text.trim(),
        'address_line2':
            _address2Ctrl.text.trim().isEmpty ? null : _address2Ctrl.text.trim(),
        'zipcode': _zipCtrl.text.trim(),
        'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
        'home_lat': _homeLat,
        'home_lng': _homeLng,
        'photo_url': photoUrl,
        'onboarding_status': 'personal_saved',
        'updated_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      _photoUrl = photoUrl;
      setState(() {
        _onboardingStatus = 'personal_saved';
        _step = 1; // immediately move to KYC
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Personal info saved')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ================== Submit KYC ==================
  Future<void> _submitKyc() async {
    if (!_kycKey.currentState!.validate()) return;
    if (_isReadOnly) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }
    setState(() => _saving = true);
    try {
      final doctype = _docType!.toLowerCase(); // "aadhaar" | "pan" | "voterid"
      final String frontUrl = await _uploadToCloudinary(
        xfile: _docFront!,
        publicId: 'kyc_${doctype}_front',
        folder: '$_baseFolder/users/${user.uid}/kyc',
      );
      final String backUrl = await _uploadToCloudinary(
        xfile: _docBack!,
        publicId: 'kyc_${doctype}_back',
        folder: '$_baseFolder/users/${user.uid}/kyc',
      );

      await FirebaseFirestore.instance.collection('documents').add({
        'uid': user.uid,
        'type': _docType,
        'front': frontUrl,
        'back': backUrl,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Mark profile as KYC pending
      await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid)
          .set(
              {'onboarding_status': 'kyc_pending', 'updated_at': FieldValue.serverTimestamp()},
              SetOptions(merge: true));

      setState(() {
        _onboardingStatus = 'kyc_pending';
        _kycStatus = 'pending';
      });

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC submitted. Status: pending')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Complete Onboarding'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loadingState
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _Header(step: _step),
                        const SizedBox(height: 12),
                        if (_isUnderVerification)
                          const _StatusBanner(
                            type: BannerType.info,
                            text:
                                'Your KYC is under verification. Editing is disabled.',
                          ),
                        if (_isApproved)
                          const _StatusBanner(
                            type: BannerType.success,
                            text: 'Your KYC is approved.',
                          ),
                        if (_kycStatus == 'rejected' ||
                            _onboardingStatus == 'kyc_rejected')
                          const _StatusBanner(
                            type: BannerType.error,
                            text:
                                'Your KYC was rejected. Please fix and resubmit.',
                          ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _step == 0
                                ? _buildPersonalForm()
                                : _buildKycForm(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPersonalForm() {
    final disabled = _isReadOnly;
    return Form(
      key: _personalKey,
      child: ListView(
        padding: const EdgeInsets.only(top: 6),
        children: [
          // ===== Avatar first =====
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: disabled ? null : _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _AvatarPreview(
                          xfile: _profilePhoto,
                          networkUrl: _photoUrl,
                          radius: 48),
                      if (!disabled)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF6759FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.edit,
                              size: 16, color: Colors.white),
                        )
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (!disabled)
                  TextButton(
                    onPressed: _pickAvatar,
                    child: const Text('Add / Change Photo'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          _Labeled(
            'Address Line 1*',
            child: TextFormField(
              controller: _address1Ctrl,
              enabled: !disabled,
              decoration: _inputDecoration('House / Street / Area'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Address Line 2 (optional)',
            child: TextFormField(
              controller: _address2Ctrl,
              enabled: !disabled,
              decoration:
                  _inputDecoration('Apartment / Landmark (optional)'),
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Zipcode*',
            child: TextFormField(
              controller: _zipCtrl,
              enabled: !disabled,
              decoration: _inputDecoration('e.g. 682001'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Date of Birth*',
            child: InkWell(
              onTap: disabled
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate:
                            DateTime(now.year - 10, now.month, now.day),
                        initialDate: DateTime(now.year - 18),
                      );
                      if (picked != null) setState(() => _dob = picked);
                    },
              child: InputDecorator(
                decoration: _inputDecoration('Pick your DOB'),
                child: Text(
                  _dob == null
                      ? 'Tap to select'
                      : '${_dob!.day.toString().padLeft(2, '0')}-'
                        '${_dob!.month.toString().padLeft(2, '0')}-'
                        '${_dob!.year}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Home Location (lat/lng)*',
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: _inputDecoration('Latitude'),
                    enabled: !disabled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(
                        text: _homeLat?.toStringAsFixed(6) ?? ''),
                    onChanged: (v) => _homeLat = double.tryParse(v.trim()),
                    validator: (v) => (_homeLat == null) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    decoration: _inputDecoration('Longitude'),
                    enabled: !disabled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(
                        text: _homeLng?.toStringAsFixed(6) ?? ''),
                    onChanged: (v) => _homeLng = double.tryParse(v.trim()),
                    validator: (v) => (_homeLng == null) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Use current location',
                  onPressed: disabled ? null : _useCurrentLocation,
                  icon: const Icon(Icons.my_location_rounded),
                )
              ],
            ),
          ),
          if (_homeLat != null && _homeLng != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('Lat: ${_homeLat!.toStringAsFixed(6)}')),
                Chip(label: Text('Lng: ${_homeLng!.toStringAsFixed(6)}')),
              ],
            ),
          ],

          const SizedBox(height: 20),
          if (!disabled)
            _SubmitButton(
              text: _saving ? 'Saving...' : 'Save & Continue',
              onPressed: _saving ? null : _savePersonal,
            ),
        ],
      ),
    );
  }

  Widget _buildKycForm() {
    final disabled = _isReadOnly;
    return Form(
      key: _kycKey,
      child: ListView(
        padding: const EdgeInsets.only(top: 6),
        children: [
          _Labeled(
            'Select Document Type*',
            child: DropdownButtonFormField<String>(
              value: _docType,
              decoration: _inputDecoration('Choose one'),
              items: const [
                DropdownMenuItem(value: 'Aadhaar', child: Text('Aadhaar')),
                DropdownMenuItem(value: 'PAN', child: Text('PAN')),
                DropdownMenuItem(value: 'VoterId', child: Text('Voter ID')),
              ],
              onChanged: disabled ? null : (v) => setState(() => _docType = v),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Front Side Image*',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Pick Front'),
                    onPressed: disabled
                        ? null
                        : () async {
                            final f = await _pickImage();
                            if (f != null) setState(() => _docFront = f);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                if (_docFront != null) _ThumbPreview(xfile: _docFront!),
              ],
            ),
            validator: () => _docFront == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Back Side Image*',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Pick Back'),
                    onPressed: disabled
                        ? null
                        : () async {
                            final f = await _pickImage();
                            if (f != null) setState(() => _docBack = f);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                if (_docBack != null) _ThumbPreview(xfile: _docBack!),
              ],
            ),
            validator: () => _docBack == null ? 'Required' : null,
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step = 0),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: !disabled
                    ? _SubmitButton(
                        text: _saving ? 'Submitting...' : 'Submit KYC',
                        onPressed: _saving ? null : _submitKyc,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// ================== UI building blocks ==================

class _Header extends StatelessWidget {
  final int step;
  const _Header({required this.step});

  @override
  Widget build(BuildContext context) {
    final chips = [
      _StepChip(label: 'Personal', active: step == 0, done: step > 0),
      _StepChip(label: 'KYC', active: step == 1, done: false),
    ];
    return Row(
      children: [
        const Text('Onboarding',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const Spacer(),
        Wrap(spacing: 8, children: chips),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  const _StepChip(
      {required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final bg = done
        ? Colors.green.shade50
        : active
            ? Colors.deepPurple.shade50
            : Colors.grey.shade100;
    final fg = done
        ? Colors.green.shade700
        : active
            ? Colors.deepPurple
            : Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done
              ? Colors.green.shade200
              : active
                  ? Colors.deepPurple.shade200
                  : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.circle, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg)),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  const _SubmitButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: const Color(0xFF6759FF),
          foregroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Icon(Icons.north_east_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  final String? Function()? validator; // optional hook
  const _Labeled(this.label, {required this.child, this.validator});

  @override
  Widget build(BuildContext context) {
    final errorText = validator?.call();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        child,
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(errorText,
                style:
                    TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
      ],
    );
  }
}

enum BannerType { info, success, error }

class _StatusBanner extends StatelessWidget {
  final BannerType type;
  final String text;
  const _StatusBanner({required this.type, required this.text});

  @override
  Widget build(BuildContext context) {
    Color bg, fg, border;
    switch (type) {
      case BannerType.success:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        border = Colors.green.shade200;
        break;
      case BannerType.error:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        border = Colors.red.shade200;
        break;
      default:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        border = Colors.amber.shade200;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            type == BannerType.success
                ? Icons.verified_outlined
                : type == BannerType.error
                    ? Icons.error_outline
                    : Icons.info_outline,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}

// Avatar preview (local XFile OR existing network URL)
class _AvatarPreview extends StatelessWidget {
  final XFile? xfile;
  final String? networkUrl;
  final double radius;
  const _AvatarPreview(
      {required this.xfile, this.networkUrl, this.radius = 48});

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;
    if (xfile != null) {
      provider = kIsWeb
          ? NetworkImage(xfile!.path)
          : FileImage(File(xfile!.path)) as ImageProvider;
    } else if (networkUrl != null && networkUrl!.isNotEmpty) {
      provider = NetworkImage(networkUrl!);
    }

    if (provider == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE9EAF4),
        child: const Icon(Icons.person, size: 48, color: Colors.grey),
      );
    }
    return CircleAvatar(
        radius: radius,
        backgroundImage: provider,
        backgroundColor: const Color(0xFFE9EAF4));
  }
}

// Small thumbnail preview for KYC files
class _ThumbPreview extends StatelessWidget {
  final XFile xfile;
  const _ThumbPreview({required this.xfile});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: kIsWeb
          ? Image.network(xfile.path, width: 64, height: 64, fit: BoxFit.cover)
          : Image.file(File(xfile.path),
              width: 64, height: 64, fit: BoxFit.cover),
    );
  }
}
