import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// Use your app theme tokens (do NOT modify app_theme.dart)
import 'theme/app_theme.dart';

class OnboardingForm extends StatefulWidget {
  const OnboardingForm({super.key});

  @override
  State<OnboardingForm> createState() => _OnboardingFormState();
}

class _OnboardingFormState extends State<OnboardingForm> {
  final _personalKey = GlobalKey<FormState>();

  // ===== Cloudinary & Server Config =====
  static const String _cloudName = 'dnxj5r6rc'; // keep in sync with .env
  static const String _baseFolder = 'smartDrive';
  static const String _hostingerBase =
      'https://tajdrivingschool.in/smartDrive/cloudinary';

  // ===== Personal fields =====
  final _permanentAddressCtrl = TextEditingController();
  final _relationCtrl = TextEditingController(); // Son/Wife/Daughter of

  // learner/license fields
  bool _isLearnerHolder = false;
  final _learnerNumberCtrl = TextEditingController();
  DateTime? _learnerExpiry;

  bool _isLicenseHolder = false;
  final _licenseNumberCtrl = TextEditingController();
  DateTime? _licenseExpiry;

  // NEW: license issue date + issuing authority
  DateTime? _licenseIssued; // date of issue
  final _licenseAuthorityCtrl = TextEditingController();

  DateTime? _dob;
  XFile? _profilePhoto;
  String? _photoUrl;

  // ===== State / Flow =====
  bool _saving = false;
  bool _loadingState = true;
  String? _onboardingStatus;
  final _picker = ImagePicker();

  // Remove ALL whitespace (to avoid signature mismatch)
  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), '');

  @override
  void initState() {
    super.initState();
    _hydrateState();
  }

  @override
  void dispose() {
    _permanentAddressCtrl.dispose();
    _relationCtrl.dispose();
    _learnerNumberCtrl.dispose();
    _licenseNumberCtrl.dispose();
    _licenseAuthorityCtrl.dispose();
    super.dispose();
  }

  bool _isPersonalCompleteFromData(Map<String, dynamic> data) {
    final addr = (data['permanent_address'] ?? '').toString().trim();
    final dob = data['dob'];
    final relation = (data['relation_of'] ?? '').toString().trim();
    // learner/license are optional; only require address, relation and dob
    return addr.isNotEmpty && relation.isNotEmpty && dob != null;
  }

  Future<void> _hydrateState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingState = false);
      return;
    }

    try {
      final profRef = FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid);
      final profSnap = await profRef.get();

      if (profSnap.exists) {
        final data = profSnap.data();
        _onboardingStatus = data?['onboarding_status'] as String?;
        _photoUrl = data?['photo_url'] as String?;
        _permanentAddressCtrl.text =
            (data?['permanent_address'] ?? '') as String;
        _relationCtrl.text = (data?['relation_of'] ?? '') as String? ?? '';

        final ts = data?['dob'] as Timestamp?;
        _dob = ts?.toDate();

        _isLearnerHolder = (data?['is_learner_holder'] as bool?) ?? false;
        _learnerNumberCtrl.text = (data?['learner_number'] ?? '') as String;
        final lExp = data?['learner_expiry'] as Timestamp?;
        _learnerExpiry = lExp?.toDate();

        _isLicenseHolder = (data?['is_license_holder'] as bool?) ?? false;
        _licenseNumberCtrl.text = (data?['license_number'] ?? '') as String;
        final licExp = data?['license_expiry'] as Timestamp?;
        _licenseExpiry = licExp?.toDate();
        // If a license exists, clear learner fields and disable learner input
        if (_isLicenseHolder) {
          _isLearnerHolder = false;
          _learnerNumberCtrl.clear();
          _learnerExpiry = null;
        }

        // NEW: hydrate license issue date + authority
        final licIssuedTs = data?['license_issue_date'] as Timestamp?;
        _licenseIssued = licIssuedTs?.toDate();
        _licenseAuthorityCtrl.text =
            (data?['license_authority'] ?? '') as String;
      }
    } catch (_) {
      // ignore and let user fill
    } finally {
      if (mounted) setState(() => _loadingState = false);
    }
  }

  // Pick image (you can switch to file_picker if you truly want ANY file from UI)
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

  // ===== Signed Upload: Get server signature =====
  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final uri = Uri.parse('$_hostingerBase/signature.php');
    final body = {
      'public_id': _clean(publicId),
      'folder': _clean(folder),
      'overwrite': overwrite,
    };
    final res = await http.post(uri, body: body);
    if (res.statusCode != 200) {
      throw Exception('Signature server error: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['signature'] == null ||
        json['api_key'] == null ||
        json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

  // ===== Signed Upload to Cloudinary (ANY file type via /auto/upload) =====
  Future<String> _uploadToCloudinarySigned({
    required XFile xfile,
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final signed = await _getSignature(
      publicId: publicId,
      folder: folder,
      overwrite: overwrite,
    );
    final timestamp = signed['timestamp'].toString();
    final signature = signed['signature'] as String;
    final apiKey = signed['api_key'] as String;

    // Use /auto/upload to accept any format (image, video, raw, pdf, etc.)
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload',
    );

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['signature'] = signature
      ..fields['public_id'] = _clean(publicId)
      ..fields['folder'] = _clean(folder)
      ..fields['overwrite'] = overwrite;

    // generic content-type so ANY file works
    final mediaType = MediaType('application', 'octet-stream');

    if (kIsWeb) {
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'upload.bin';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: mediaType,
        ),
      );
    } else {
      final filename = xfile.name.isNotEmpty ? xfile.name : 'upload.bin';
      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          xfile.path,
          filename: filename,
          contentType: mediaType,
        ),
      );
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['secure_url'] as String?) ?? (json['url'] as String);
  }

  // ===== Save Personal =====
  Future<void> _savePersonal() async {
    if (!_personalKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }

    // Date validations: DOB and license issue date must be in the past; expiry dates must be in the future
    final now = DateTime.now();
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick date of birth')),
      );
      return;
    }
    if (!_dob!.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date of birth must be in the past')),
      );
      return;
    }
    if (_isLearnerHolder && _learnerExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick learner expiry date')),
      );
      return;
    }
    if (_isLearnerHolder &&
        _learnerExpiry != null &&
        !_learnerExpiry!.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Learner expiry must be a future date')),
      );
      return;
    }
    if (_isLicenseHolder && _licenseExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick license expiry date')),
      );
      return;
    }
    if (_isLicenseHolder &&
        _licenseExpiry != null &&
        !_licenseExpiry!.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License expiry must be a future date')),
      );
      return;
    }
    if (_isLicenseHolder && _licenseIssued == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick license date of issue')),
      );
      return;
    }
    if (_isLicenseHolder &&
        _licenseIssued != null &&
        !_licenseIssued!.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('License date of issue must be in the past'),
        ),
      );
      return;
    }

    // Additional validation: expiry dates when applicable
    if (_isLearnerHolder && _learnerExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick learner expiry date')),
      );
      return;
    }
    if (_isLicenseHolder && _licenseExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick license expiry date')),
      );
      return;
    }

    // NEW: validate license issue date and authority when license holder
    if (_isLicenseHolder && _licenseIssued == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick license date of issue')),
      );
      return;
    }
    if (_isLicenseHolder && (_licenseAuthorityCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter licensing authority')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? photoUrl = _photoUrl;
      if (_profilePhoto != null) {
        final folder = _clean('$_baseFolder/users/${user.uid}/profile');
        final publicId = _clean('profile');
        photoUrl = await _uploadToCloudinarySigned(
          xfile: _profilePhoto!,
          publicId: publicId,
          folder: folder,
        );
      }

      final data = {
        'uid': user.uid,
        'permanent_address': _permanentAddressCtrl.text.trim(),
        'relation_of': _relationCtrl.text.trim(),
        'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
        'photo_url': photoUrl,
        'is_learner_holder': _isLearnerHolder,
        'learner_number': _isLearnerHolder
            ? _learnerNumberCtrl.text.trim()
            : null,
        'learner_expiry': _isLearnerHolder && _learnerExpiry != null
            ? Timestamp.fromDate(_learnerExpiry!)
            : null,
        'is_license_holder': _isLicenseHolder,
        'license_number': _isLicenseHolder
            ? _licenseNumberCtrl.text.trim()
            : null,
        'license_expiry': _isLicenseHolder && _licenseExpiry != null
            ? Timestamp.fromDate(_licenseExpiry!)
            : null,
        // NEW: save issue date + authority
        'license_issue_date': _isLicenseHolder && _licenseIssued != null
            ? Timestamp.fromDate(_licenseIssued!)
            : null,
        'license_authority': _isLicenseHolder
            ? _licenseAuthorityCtrl.text.trim()
            : null,
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
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Personal info saved')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final bg = context.c.background;
    final surface = context.c.surface;
    final onSurface = context.c.onSurface;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Complete Onboarding'),
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0.5,
      ),
      body: _loadingState
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.c.primary),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  color: surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                  ),
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _SimpleHeader(),
                        const SizedBox(height: 12),
                        const SizedBox(height: 8),
                        Expanded(child: _buildPersonalForm()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPersonalForm() {
    return Form(
      key: _personalKey,
      child: ListView(
        padding: const EdgeInsets.only(top: 6),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _AvatarPreview(
                        xfile: _profilePhoto,
                        networkUrl: _photoUrl,
                        radius: 48,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickAvatar,
                  child: Text(
                    'Add / Change Passport Photo',
                    style: TextStyle(color: context.c.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          _Labeled(
            'Permanent Address*',
            child: TextFormField(
              controller: _permanentAddressCtrl,
              decoration: _inputDecoration(
                'Flat, Street, Area, City, State, PIN',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 12),

          _Labeled(
            'Son/Wife/Daughter of*',
            child: TextFormField(
              controller: _relationCtrl,
              decoration: _inputDecoration('Name of parent or spouse'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),

          const SizedBox(height: 12),

          _Labeled(
            'Date of Birth*',
            child: InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(now.year - 10, now.month, now.day),
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
                  style: TextStyle(
                    color: _dob == null
                        ? AppColors.onSurfaceFaint
                        : context.c.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ===== New: Learner holder question =====
          _Labeled(
            'Are you a learner\'s holder?*',
            child: DropdownButtonFormField<bool>(
              value: _isLearnerHolder,
              decoration: _inputDecoration('Select'),
              items: const [
                DropdownMenuItem(value: false, child: Text('No')),
                DropdownMenuItem(value: true, child: Text('Yes')),
              ],
              onChanged: _isLicenseHolder
                  ? null
                  : (v) => setState(() => _isLearnerHolder = v ?? false),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLicenseHolder)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Learner details are disabled when license details are provided.',
                style: TextStyle(color: AppColors.onSurfaceFaint, fontSize: 12),
              ),
            ),
          if (_isLearnerHolder) ...[
            _Labeled(
              'Learner Number*',
              child: TextFormField(
                controller: _learnerNumberCtrl,
                decoration: _inputDecoration('Enter learner number'),
                validator: (v) =>
                    (_isLearnerHolder && (v == null || v.trim().isEmpty))
                    ? 'Required'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            _Labeled(
              'Learner Expiry*',
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(now.year - 10),
                    lastDate: DateTime(now.year + 50),
                    initialDate: _learnerExpiry ?? now,
                  );
                  if (picked != null) setState(() => _learnerExpiry = picked);
                },
                child: InputDecorator(
                  decoration: _inputDecoration('Pick learner expiry date'),
                  child: Text(
                    _learnerExpiry == null
                        ? 'Tap to select'
                        : '${_learnerExpiry!.day.toString().padLeft(2, '0')}-'
                              '${_learnerExpiry!.month.toString().padLeft(2, '0')}-'
                              '${_learnerExpiry!.year}',
                    style: TextStyle(
                      color: _learnerExpiry == null
                          ? AppColors.onSurfaceFaint
                          : context.c.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ===== New: License holder question =====
          _Labeled(
            'Are you a license holder?*',
            child: DropdownButtonFormField<bool>(
              value: _isLicenseHolder,
              decoration: _inputDecoration('Select'),
              items: const [
                DropdownMenuItem(value: false, child: Text('No')),
                DropdownMenuItem(value: true, child: Text('Yes')),
              ],
              onChanged: (v) => setState(() {
                _isLicenseHolder = v ?? false;
                // if user toggles license ON, clear learner details and disable them
                if (_isLicenseHolder) {
                  _isLearnerHolder = false;
                  _learnerNumberCtrl.clear();
                  _learnerExpiry = null;
                }
              }),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLicenseHolder) ...[
            _Labeled(
              'License Number*',
              child: TextFormField(
                controller: _licenseNumberCtrl,
                decoration: _inputDecoration('Enter license number'),
                validator: (v) =>
                    (_isLicenseHolder && (v == null || v.trim().isEmpty))
                    ? 'Required'
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // NEW: Date of Issue
            _Labeled(
              'License Date of Issue*',
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(now.year - 50),
                    lastDate: DateTime(now.year + 10),
                    initialDate: _licenseIssued ?? now,
                  );
                  if (picked != null) setState(() => _licenseIssued = picked);
                },
                child: InputDecorator(
                  decoration: _inputDecoration('Pick license date of issue'),
                  child: Text(
                    _licenseIssued == null
                        ? 'Tap to select'
                        : '${_licenseIssued!.day.toString().padLeft(2, '0')}-'
                              '${_licenseIssued!.month.toString().padLeft(2, '0')}-'
                              '${_licenseIssued!.year}',
                    style: TextStyle(
                      color: _licenseIssued == null
                          ? AppColors.onSurfaceFaint
                          : context.c.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // NEW: Licensing Authority
            _Labeled(
              'Licensing Authority*',
              child: TextFormField(
                controller: _licenseAuthorityCtrl,
                decoration: _inputDecoration(
                  'E.g. RTO Ernakulam / Regional Transport Office',
                ),
                validator: (v) =>
                    (_isLicenseHolder && (v == null || v.trim().isEmpty))
                    ? 'Required'
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            _Labeled(
              'License Expiry*',
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(now.year - 10),
                    lastDate: DateTime(now.year + 50),
                    initialDate: _licenseExpiry ?? now,
                  );
                  if (picked != null) setState(() => _licenseExpiry = picked);
                },
                child: InputDecorator(
                  decoration: _inputDecoration('Pick license expiry date'),
                  child: Text(
                    _licenseExpiry == null
                        ? 'Tap to select'
                        : '${_licenseExpiry!.day.toString().padLeft(2, '0')}-'
                              '${_licenseExpiry!.month.toString().padLeft(2, '0')}-'
                              '${_licenseExpiry!.year}',
                    style: TextStyle(
                      color: _licenseExpiry == null
                          ? AppColors.onSurfaceFaint
                          : context.c.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _SubmitButton(
            text: _saving ? 'Saving...' : 'Save & Continue',
            onPressed: _saving ? null : _savePersonal,
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.s),
      ),
    );
  }
}

// ================== UI building blocks ==================

class _SimpleHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Onboarding',
          style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
        ),
        const Spacer(),
      ],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.l),
          ),
          backgroundColor: context.c.primary,
          foregroundColor:
              context.c.inverseSurface ??
              AppColors.onSurfaceInverse, // fallback handled by theme
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
  final String? Function()? validator;
  const _Labeled(this.label, {required this.child, this.validator});

  @override
  Widget build(BuildContext context) {
    final errorText = validator?.call();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.tileTitle.copyWith(color: context.c.onSurface),
        ),
        const SizedBox(height: 8),
        child,
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText,
              style: TextStyle(color: AppColors.errFg, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  final XFile? xfile;
  final String? networkUrl;
  final double radius;
  const _AvatarPreview({
    required this.xfile,
    this.networkUrl,
    this.radius = 48,
  });

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
        backgroundColor: AppColors.neuBg,
        child: Icon(Icons.person, size: 48, color: AppColors.onSurfaceFaint),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: provider,
      backgroundColor: AppColors.neuBg,
    );
  }
}

class _ThumbPreview extends StatelessWidget {
  final XFile xfile;
  const _ThumbPreview({required this.xfile});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: kIsWeb
          ? Image.network(xfile.path, width: 64, height: 64, fit: BoxFit.cover)
          : Image.file(
              File(xfile.path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
    );
  }
}
