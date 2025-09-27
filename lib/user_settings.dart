// lib/user_settings.dart
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'messaging_setup.dart'; // for unsubscribeRoleStatusTopics()
import 'services/session_service.dart'; // for clearing saved session
import 'package:shared_preferences/shared_preferences.dart';

import 'login.dart'; // your login screen
import 'maps_page_user.dart'; // user map picker screen
import 'plans_view.dart'; // NEW: dedicated plans page

// ─── Razorpay config ───────────────────────────────────────────────────────────

// Public key via --dart-define (DO NOT hardcode secret)
const String _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');

// Your Hostinger PHP base (same as booking page)
const String _hostingerBase = 'https://tajdrivingschool.in/smartDrive/payments';

// Cloudinary signed upload host (server creates signature)
const String _cloudinarySignatureHost =
    'https://tajdrivingschool.in/smartDrive/cloudinary';
const String _cloudName = 'dnxj5r6rc';
const String _baseFolder = 'smartDrive';

// ───────────────────────────────────────────────────────────────────────────────

class _LatLng {
  final double latitude;
  final double longitude;
  const _LatLng(this.latitude, this.longitude);
}

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // New: learner/license controllers (mirror onboarding)
  bool _isLearnerHolder = false;
  final _learnerNumberController = TextEditingController();
  DateTime? _learnerExpiry;

  bool _isLicenseHolder = false;
  final _licenseNumberController = TextEditingController();
  DateTime? _licenseExpiry;

  // NEW: license issue date + issuing authority
  DateTime? _licenseIssued; // date of issue
  final _licenseAuthorityController = TextEditingController();

  // Profile photo
  final ImagePicker _picker = ImagePicker();
  XFile? _profilePhoto; // file selected
  String? _photoUrl; // existing network url hydrates here

  // Form key for input validation
  final _profileFormKey = GlobalKey<FormState>();

  User? currentUser;
  Map<String, dynamic>? userData;

  /// Resolved from `plans/{planId}`, includes 'id'
  Map<String, dynamic>? currentPlan;

  /// From `plans` collection, each with its 'id'
  List<Map<String, dynamic>> availablePlans = [];

  bool isLoading = true;

  // ─── Razorpay (plan upgrade flow) ────────────────────────────────────────────
  Razorpay? _razorpay;
  String? _lastOrderId; // set after server creates an order
  String? _pendingPlanId; // plan currently being purchased
  int _pendingAmountPaise = 0; // expected amount for verification

  // ---- track current plan usage so we can warn on upgrade ----
  int _currentPlanSlots = 0;
  int _currentSlotsUsed = 0;
  bool _currentPlanIsPayPerUse = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    currentUser = _auth.currentUser;
    _initRazorpay();
    _loadUserData();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccessPlan);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentErrorPlan);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWalletPlan);
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();

    _learnerNumberController.dispose();
    _licenseNumberController.dispose();
    _licenseAuthorityController.dispose();
    super.dispose();
  }

  // Remove ALL whitespace (to avoid signature mismatch)
  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), '');

  // ===== Cloudinary Signed Upload Helpers =====
  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final uri = Uri.parse('$_cloudinarySignatureHost/signature.php');
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
    if (json['signature'] == null || json['api_key'] == null || json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

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

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/auto/upload');

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['signature'] = signature
      ..fields['public_id'] = _clean(publicId)
      ..fields['folder'] = _clean(folder)
      ..fields['overwrite'] = overwrite;

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

  // ─── Data loading ───────────────────────────────────────────────────────────
  Future<void> _loadUserData() async {
    if (currentUser == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      // Load user profile (users collection)
      final userDoc = await _firestore.collection('users').doc(currentUser!.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          userData = data;
          _nameController.text = (data['name'] ?? '').toString();
          _emailController.text = (data['email'] ?? currentUser!.email ?? '').toString();
        }
      }

      // Hydrate user_profiles (learner/license + photo)
      try {
        final profSnap = await _firestore.collection('user_profiles').doc(currentUser!.uid).get();
        if (profSnap.exists) {
          final pdata = profSnap.data() ?? <String, dynamic>{};
          _photoUrl = (pdata['photo_url'] ?? '') as String?;
          _isLearnerHolder = (pdata['is_learner_holder'] as bool?) ?? false;
          _learnerNumberController.text = (pdata['learner_number'] ?? '') as String;
          final lExp = pdata['learner_expiry'] as Timestamp?;
          _learnerExpiry = lExp?.toDate();

          _isLicenseHolder = (pdata['is_license_holder'] as bool?) ?? false;
          _licenseNumberController.text = (pdata['license_number'] ?? '') as String;
          final licExp = pdata['license_expiry'] as Timestamp?;
          _licenseExpiry = licExp?.toDate();

          final licIssuedTs = pdata['license_issue_date'] as Timestamp?;
          _licenseIssued = licIssuedTs?.toDate();
          _licenseAuthorityController.text = (pdata['license_authority'] ?? '') as String;
        }
      } catch (e) {
        debugPrint('Error hydrating user_profiles: $e');
      }

      // Load current plan (user_plans/{userId} → planId → plans/{planId})
      await _loadCurrentPlan();

      // Load available plans
      await _loadAvailablePlans();
    } catch (e) {
      _showErrorDialog('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Single-doc schema: read from `user_plans/{userId}` and resolve planId.
  Future<void> _loadCurrentPlan() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) {
        currentPlan = null;
        _currentPlanSlots = 0;
        _currentSlotsUsed = 0;
        _currentPlanIsPayPerUse = false;
        return;
      }

      final userPlanDoc = await _firestore.collection('user_plans').doc(uid).get();

      if (!userPlanDoc.exists) {
        currentPlan = null; // No plan doc created yet
        _currentPlanSlots = 0;
        _currentSlotsUsed = 0;
        _currentPlanIsPayPerUse = false;
        return;
      }

      final up = userPlanDoc.data() as Map<String, dynamic>;
      final planId = (up['planId'] ?? '').toString().trim();
      _currentSlotsUsed = (up['slots_used'] is num) ? (up['slots_used'] as num).toInt() : 0;

      if (planId.isEmpty) {
        currentPlan = null;
        _currentPlanSlots = 0;
        _currentPlanIsPayPerUse = false;
        return;
      }

      final planDoc = await _firestore.collection('plans').doc(planId).get();
      if (!planDoc.exists || planDoc.data() == null) {
        currentPlan = null;
        _currentPlanSlots = 0;
        _currentPlanIsPayPerUse = false;
        return;
      }

      final p = planDoc.data()!;
      currentPlan = {'id': planDoc.id, ...p};

      _currentPlanSlots = (p['slots'] is num) ? (p['slots'] as num).toInt() : 0;
      _currentPlanIsPayPerUse = (p['isPayPerUse'] == true);
    } catch (e) {
      // keep UI stable
      // ignore: avoid_print
      print('Error loading current plan: $e');
      currentPlan = null;
      _currentPlanSlots = 0;
      _currentSlotsUsed = 0;
      _currentPlanIsPayPerUse = false;
    }
  }

  /// Reads all plans; orders by price if present
  Future<void> _loadAvailablePlans() async {
    try {
      Query query = _firestore.collection('plans');

      try {
        query = query.orderBy('price');
      } catch (_) {
        // price may not exist or no index—skip ordering
      }

      final snap = await query.get();
      availablePlans = snap.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {'id': d.id, ...data};
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      // ignore: avoid_print
      print('Error loading available plans: $e');
      availablePlans = [];
    }
  }

  // ─── Profile & Security actions ─────────────────────────────────────────────
  Future<void> _updateProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;

    if (currentUser == null) {
      _toLogin();
      return;
    }

    // Date validations similar to onboarding form
    final now = DateTime.now();
    if (_isLearnerHolder && _learnerExpiry == null) {
      _showErrorDialog('Please pick learner expiry date');
      return;
    }
    if (_isLearnerHolder && _learnerExpiry != null && !_learnerExpiry!.isAfter(now)) {
      _showErrorDialog('Learner expiry must be a future date');
      return;
    }
    if (_isLicenseHolder && _licenseExpiry == null) {
      _showErrorDialog('Please pick license expiry date');
      return;
    }
    if (_isLicenseHolder && _licenseExpiry != null && !_licenseExpiry!.isAfter(now)) {
      _showErrorDialog('License expiry must be a future date');
      return;
    }
    if (_isLicenseHolder && _licenseIssued == null) {
      _showErrorDialog('Please pick license date of issue');
      return;
    }
    if (_isLicenseHolder && _licenseIssued != null && !_licenseIssued!.isBefore(now)) {
      _showErrorDialog('License date of issue must be in the past');
      return;
    }
    if (_isLicenseHolder && (_licenseAuthorityController.text.trim().isEmpty)) {
      _showErrorDialog('Please enter licensing authority');
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      String? photoUrl = _photoUrl;
      if (_profilePhoto != null) {
        final folder = _clean('$_baseFolder/users/${currentUser!.uid}/profile');
        final publicId = _clean('profile');
        photoUrl = await _uploadToCloudinarySigned(
          xfile: _profilePhoto!,
          publicId: publicId,
          folder: folder,
        );
      }

      // Update users/{uid}
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update user_profiles/{uid} with learner/license & photo
      final profileData = {
        'uid': currentUser!.uid,
        'photo_url': photoUrl,
        'is_learner_holder': _isLearnerHolder,
        'learner_number': _isLearnerHolder ? _learnerNumberController.text.trim() : null,
        'learner_expiry': _isLearnerHolder && _learnerExpiry != null ? Timestamp.fromDate(_learnerExpiry!) : null,
        'is_license_holder': _isLicenseHolder,
        'license_number': _isLicenseHolder ? _licenseNumberController.text.trim() : null,
        'license_expiry': _isLicenseHolder && _licenseExpiry != null ? Timestamp.fromDate(_licenseExpiry!) : null,
        'license_issue_date': _isLicenseHolder && _licenseIssued != null ? Timestamp.fromDate(_licenseIssued!) : null,
        'license_authority': _isLicenseHolder ? _licenseAuthorityController.text.trim() : null,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('user_profiles').doc(currentUser!.uid).set(profileData, SetOptions(merge: true));

      _photoUrl = photoUrl;
      _showSuccessSnack('Profile updated');

      // refresh state (reload)
      await _loadUserData();
      if (mounted) setState(() {});
    } catch (e) {
      _showErrorDialog('Error updating profile: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showErrorDialog('All password fields are required');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showErrorDialog('New passwords do not match');
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showErrorDialog('New password must be at least 6 characters');
      return;
    }
    if (currentUser == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      final credential = EmailAuthProvider.credential(
        email: currentUser!.email!,
        password: _currentPasswordController.text,
      );
      await currentUser!.reauthenticateWithCredential(credential);
      await currentUser!.updatePassword(_newPasswordController.text);

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      _showSuccessSnack('Password changed');
    } catch (e) {
      _showErrorDialog('Error changing password: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Updates the SINGLE document: `user_plans/{userId}`.
  /// Does NOT create a document if missing; shows a helpful error instead.
  Future<void> _upgradePlan(String newPlanId) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      final userPlanRef = _firestore.collection('user_plans').doc(uid);

      await userPlanRef.update({
        'planId': newPlanId,
        'isActive': true, // keep active flag if you use it elsewhere
        'active': true, // optional legacy flag
        'startDate': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // 'slots_used': 0, // uncomment if you reset counters on upgrade
      });

      _showSuccessSnack('Plan updated');
      await _loadCurrentPlan();
      if (mounted) setState(() {});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        _showErrorDialog(
          'No plan document found at user_plans/$uid.\n'
          'Create this document once with id = userId, e.g. { "planId": "<planId>", "isActive": true }. '
          'After that, you can change plans from here.',
        );
      } else {
        _showErrorDialog('Error updating plan: ${e.message ?? e.code}');
      }
    } catch (e) {
      _showErrorDialog('Error updating plan: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _logout({bool wipeAllPrefs = false}) async {
    try {
      if (mounted) setState(() => isLoading = true);

      // 1) Stop FCM topic subscriptions tied to role/status
      await unsubscribeRoleStatusTopics(alsoAll: false);

      // 2) Clear saved session + remember-me flags
      final sp = await SharedPreferences.getInstance();
      await SessionService().clear(); // removes userId/role/status
      await sp.remove('sd_saved_email'); // forget saved email
      await sp.setBool('sd_remember_me', false);

      // Optional: full wipe of all SharedPreferences (use with care)
      if (wipeAllPrefs) {
        await sp.clear();
      }

      // 3) Sign out Firebase
      await _auth.signOut();

      // 4) Go to login
      _toLogin();
    } catch (e) {
      _showErrorDialog('Error logging out: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─── Boarding selection navigation ──────────────────────────────────────────
  void _goToBoardingSelection() {
    if (currentUser == null) {
      _toLogin();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapsPageUser(
          userId: currentUser!.uid,
        ),
      ),
    );
  }

  // ─── Razorpay: server helpers ───────────────────────────────────────────────
  Future<Map<String, dynamic>> _postJson(String url, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) throw Exception('Invalid JSON');
    return data;
  }

  Future<String> _createOrderOnServer({
    required int amountPaise,
    required String planId,
  }) async {
    final res = await _postJson(
      '$_hostingerBase/createOrder.php',
      {
        'amountPaise': amountPaise,
        'receipt': 'plan_${planId}_${DateTime.now().millisecondsSinceEpoch}',
        'notes': {
          'planId': planId,
          'userId': currentUser?.uid ?? '',
        },
      },
    );
    final orderId = (res['orderId'] ?? '').toString();
    if (orderId.isEmpty) throw Exception('OrderId missing in response');
    return orderId;
  }

  Future<bool> _verifyPaymentOnServer({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required int expectedAmountPaise,
  }) async {
    final res = await _postJson(
      '$_hostingerBase/verifyPayment.php',
      {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
        'expectedAmountPaise': expectedAmountPaise,
      },
    );
    return (res['valid'] == true);
  }

  // ─── Razorpay: open checkout for plan upgrade ───────────────────────────────
  Future<void> _startPlanPayment({
    required String planId,
    required int amountPaise,
    required String planName,
  }) async {
    if (_razorpay == null) {
      _showErrorDialog('Payment is unavailable right now. Please try again.');
      return;
    }
    if (_razorpayKeyId.isEmpty) {
      _showErrorDialog('Razorpay key missing. Pass --dart-define=RAZORPAY_KEY_ID=your_key');
      return;
    }

    _pendingPlanId = planId;
    _pendingAmountPaise = amountPaise;

    try {
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise, planId: planId);

      final options = {
        'key': _razorpayKeyId,
        'order_id': _lastOrderId,
        'amount': amountPaise,
        'currency': 'INR',

        // Keep header as minimal as Razorpay allows
        'name': '',
        'description': planName,
        'image': '',

        'prefill': {
          'contact': '',
          'email': '',
          'name': '',
        },

        // Hide EMI, Wallet, Paylater
        'config': {
          'display': {
            'hide': [
              {'method': 'emi'},
              {'method': 'wallet'},
              {'method': 'paylater'},
            ],
          }
        },

        'theme': {'color': '#FFFFFF'},
        'timeout': 300,
      };

      _razorpay!.open(options);
    } catch (e) {
      _showErrorDialog('Could not start payment: $e');
    }
  }

  // ─── Razorpay: callbacks ───────────────────────────────────────────────────
  Future<void> _onPaymentSuccessPlan(PaymentSuccessResponse r) async {
    if (r.orderId == null || r.paymentId == null || r.signature == null) {
      _showErrorDialog('Payment success response incomplete.');
      return;
    }
    if (_pendingPlanId == null || _pendingAmountPaise <= 0) {
      _showErrorDialog('No pending plan to upgrade.');
      return;
    }

    bool valid = false;
    try {
      valid = await _verifyPaymentOnServer(
        razorpayOrderId: r.orderId!,
        razorpayPaymentId: r.paymentId!,
        razorpaySignature: r.signature!,
        expectedAmountPaise: _pendingAmountPaise,
      );
    } catch (e) {
      _showErrorDialog('Verification error: $e');
      return;
    }

    if (!valid) {
      _showErrorDialog('Payment verification failed. Please contact support.');
      return;
    }

    // 1) Update user's plan
    await _upgradePlan(_pendingPlanId!);

    // 2) Log the purchase
    try {
      await _firestore.collection('plan_purchases').add({
        'user_id': currentUser?.uid,
        'plan_id': _pendingPlanId,
        'amount': _pendingAmountPaise / 100.0,
        'currency': 'INR',
        'razorpay_order_id': r.orderId,
        'razorpay_payment_id': r.paymentId,
        'razorpay_signature': r.signature,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    _showSuccessSnack('Plan upgraded successfully!');
    _pendingPlanId = null;
    _pendingAmountPaise = 0;
    _lastOrderId = null;

    await _loadCurrentPlan();
    setState(() {});
  }

  void _onPaymentErrorPlan(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _showErrorDialog('Payment failed${msg != null && msg.isNotEmpty ? ':\n$msg' : ''}');
    // Optional log
    _firestore.collection('plan_purchases').add({
      'user_id': currentUser?.uid,
      'plan_id': _pendingPlanId,
      'status': 'failed',
      'code': r.code,
      'message': r.message,
      'order_id': _lastOrderId,
      'created_at': FieldValue.serverTimestamp(),
    });
    _pendingPlanId = null;
    _pendingAmountPaise = 0;
    _lastOrderId = null;
  }

  void _onExternalWalletPlan(ExternalWalletResponse r) {
    _showSuccessSnack('Using external wallet: ${r.walletName ?? ''}');
  }

  // ─── UI helpers ────────────────────────────────────────────────────────────
  void _toLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showChangePasswordSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottom,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetTitle('Change Password'),
              const SizedBox(height: 8),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _currentPasswordController.clear();
                        _newPasswordController.clear();
                        _confirmPasswordController.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _changePassword();
                      },
                      child: const Text('Change'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ─── Payment Summary before upgrading (with unused-slots warning) ───────────
  Future<void> _presentPaymentSummary(Map<String, dynamic> plan) async {
    final planId = (plan['id'] ?? '').toString();
    if (planId.isEmpty) {
      _showErrorDialog('Invalid plan selection.');
      return;
    }

    // Warn if current plan still has unused slots and is not PPU
    final bool hasUnusedSlotsToLose = !_currentPlanIsPayPerUse &&
        _currentPlanSlots > 0 &&
        _currentSlotsUsed < _currentPlanSlots;

    if (hasUnusedSlotsToLose) {
      final remaining = _currentPlanSlots - _currentSlotsUsed;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Unused Slots Remaining'),
          content: Text(
            'You still have $remaining slot(s) left in your current plan.\n\n'
            'Upgrading now will reset/forfeit these remaining slots.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Current Plan'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue Upgrade'),
            ),
          ],
        ),
      );
      if (proceed != true) return; // user cancelled
    }

    // Plan values
    final String planName = (plan['name'] ?? planId).toString();
    final num planPriceNum = (plan['price'] is num) ? plan['price'] as num : 0;

    final bool freePickupRadius = plan['freePickupRadius'] == true;
    final int freeRadiusKm =
        freePickupRadius ? ((plan['freeRadius'] ?? 0) as num).toInt() : 0;

    final bool extraKmSurcharge = plan['extraKmSurcharge'] == true;
    final int surchargePerKm =
        extraKmSurcharge ? ((plan['surcharge'] ?? 0) as num).toInt() : 0;

    // Fetch coordinates
    final _LatLng? userBoarding = await _fetchUserBoardingPoint();
    final _LatLng? officePoint = await _fetchOfficePoint();

    if (userBoarding == null) {
      _missingBoardingDialog();
      return;
    }
    if (officePoint == null) {
      _showErrorDialog('Office location is not configured yet. Please contact support/admin.');
      return;
    }

    // Distance (km) using Haversine
    final double distanceKm = _haversineKm(
      userBoarding.latitude,
      userBoarding.longitude,
      officePoint.latitude,
      officePoint.longitude,
    );

    // Additional charge calculation
    int additionalCharge = 0;
    int billableKm = 0;

    if (extraKmSurcharge) {
      final double extra = math.max(0.0, distanceKm - freeRadiusKm);
      // Charge per full km (ceil to next whole km)
      billableKm = extra.ceil();
      additionalCharge = billableKm * surchargePerKm;
    }

    final int planPrice = planPriceNum.round();
    final int total = planPrice + additionalCharge;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Payment Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              planName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _line('Plan price', _formatCurrency(planPrice)),
            _line('Distance to office', '${distanceKm.toStringAsFixed(2)} km'),
            if (freePickupRadius) _line('Free pickup radius', '$freeRadiusKm km'),
            if (extraKmSurcharge) _line('Surcharge per km', _formatCurrency(surchargePerKm)),
            const Divider(height: 18),
            if (extraKmSurcharge) _line('Billable km', '$billableKm km'),
            if (extraKmSurcharge) _line('Additional charge', _formatCurrency(additionalCharge)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(_formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            if (hasUnusedSlotsToLose) ...[
              const SizedBox(height: 10),
              Text(
                'Note: Upgrading now will reset your remaining ${_currentPlanSlots - _currentSlotsUsed} slot(s) from the current plan.',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              final totalPaise = total * 100;

              if (total <= 0) {
                // Free plan or no charge → directly update
                _upgradePlan(planId);
              } else {
                _startPlanPayment(planId: planId, amountPaise: totalPaise, planName: planName);
              }
            },
            child: const Text('Confirm & Upgrade'),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatCurrency(num amount) => '₹${amount.round()}';

  // ─── Data fetchers ──────────────────────────────────────────────────────────
  Future<_LatLng?> _fetchUserBoardingPoint() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return null;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (data == null) return null;
      final b = data['boarding'];
      if (b is Map<String, dynamic>) {
        final lat = (b['latitude'] as num?)?.toDouble();
        final lng = (b['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return _LatLng(lat, lng);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<_LatLng?> _fetchOfficePoint() async {
    try {
      final doc = await _firestore.collection('settings').doc('app_settings').get();
      final data = doc.data();
      if (data == null) return null;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return _LatLng(lat, lng);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Haversine distance in kilometers
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // Earth radius km
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  // Prompt user to set boarding point if missing
  void _missingBoardingDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Boarding Point Required'),
        content: const Text(
          'Please select your boarding point first to calculate any additional charges.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _goToBoardingSelection();
            },
            child: const Text('Select Boarding Point'),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;
    final pagePadding = EdgeInsets.all(isSmall ? 12 : 16);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: SingleChildScrollView(
                          padding: pagePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Header card with avatar + summary
                              _HeaderCard(
                                name: _nameController.text.trim().isEmpty
                                    ? (currentUser?.email ?? 'User')
                                    : _nameController.text.trim(),
                                email: _emailController.text,
                                photoUrl: _photoUrl,
                              ),
                              const SizedBox(height: 16),

                              // Responsive content:
                              if (isWide) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _LeftColumn(
                                        profileFormKey: _profileFormKey,
                                        nameController: _nameController,
                                        emailController: _emailController,
                                        onSaveProfile: _updateProfile,
                                        onChangePassword: _showChangePasswordSheet,
                                        // learner/license bindings:
                                        isLearnerHolder: _isLearnerHolder,
                                        onLearnerChanged: (v) {
                                          setState(() {
                                            _isLearnerHolder = v;
                                            if (v) {
                                              // leave license as-is
                                            }
                                          });
                                        },
                                        learnerNumberController: _learnerNumberController,
                                        learnerExpiry: _learnerExpiry,
                                        onPickLearnerExpiry: (d) => setState(() => _learnerExpiry = d),
                                        isLicenseHolder: _isLicenseHolder,
                                        onLicenseChanged: (v) {
                                          setState(() {
                                            _isLicenseHolder = v;
                                            if (v) {
                                              // disable learner fields when license exists
                                              _isLearnerHolder = false;
                                              _learnerNumberController.clear();
                                              _learnerExpiry = null;
                                            }
                                          });
                                        },
                                        licenseNumberController: _licenseNumberController,
                                        licenseExpiry: _licenseExpiry,
                                        onPickLicenseExpiry: (d) => setState(() => _licenseExpiry = d),
                                        licenseIssued: _licenseIssued,
                                        onPickLicenseIssued: (d) => setState(() => _licenseIssued = d),
                                        licenseAuthorityController: _licenseAuthorityController,
                                        onPickAvatar: _pickAvatar,
                                        profilePhotoFile: _profilePhoto,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: _RightColumn(
                                        currentPlan: currentPlan,
                                        onShowPlans: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => const PlansView(),
                                            ),
                                          );
                                        },
                                        onLogout: _logout,
                                        onSelectBoarding: _goToBoardingSelection,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                _LeftColumn(
                                  profileFormKey: _profileFormKey,
                                  nameController: _nameController,
                                  emailController: _emailController,
                                  onSaveProfile: _updateProfile,
                                  onChangePassword: _showChangePasswordSheet,
                                  isLearnerHolder: _isLearnerHolder,
                                  onLearnerChanged: (v) {
                                    setState(() {
                                      _isLearnerHolder = v;
                                      if (v) {
                                        // leave license as-is
                                      }
                                    });
                                  },
                                  learnerNumberController: _learnerNumberController,
                                  learnerExpiry: _learnerExpiry,
                                  onPickLearnerExpiry: (d) => setState(() => _learnerExpiry = d),
                                  isLicenseHolder: _isLicenseHolder,
                                  onLicenseChanged: (v) {
                                    setState(() {
                                      _isLicenseHolder = v;
                                      if (v) {
                                        _isLearnerHolder = false;
                                        _learnerNumberController.clear();
                                        _learnerExpiry = null;
                                      }
                                    });
                                  },
                                  licenseNumberController: _licenseNumberController,
                                  licenseExpiry: _licenseExpiry,
                                  onPickLicenseExpiry: (d) => setState(() => _licenseExpiry = d),
                                  licenseIssued: _licenseIssued,
                                  onPickLicenseIssued: (d) => setState(() => _licenseIssued = d),
                                  licenseAuthorityController: _licenseAuthorityController,
                                  onPickAvatar: _pickAvatar,
                                  profilePhotoFile: _profilePhoto,
                                ),
                                const SizedBox(height: 16),
                                _RightColumn(
                                  currentPlan: currentPlan,
                                  onShowPlans: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const PlansView(),
                                      ),
                                    );
                                  },
                                  onLogout: _logout,
                                  onSelectBoarding: _goToBoardingSelection,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ======= UI building blocks =======

class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;

  const _HeaderCard({
    required this.name,
    required this.email,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1f2937), const Color(0xFF111827)]
              : [const Color(0xFFE3F2FD), const Color(0xFFEEF7FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFBBDEFB),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: (photoUrl == null || photoUrl!.isEmpty) ? null : NetworkImage(photoUrl!),
            child: photoUrl == null || photoUrl!.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _CardSection({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanTile extends StatelessWidget {
  final String name;
  final String description;
  final dynamic price;

  const _CurrentPlanTile({
    required this.name,
    required this.description,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = price is num ? '₹${(price as num).toStringAsFixed(0)}' : '₹—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.star_rate_rounded, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Plan: $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description),
                ],
                const SizedBox(height: 4),
                Text('Price: $priceText', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
  }
}

/// LEFT column — profile editor including learner/license and avatar
class _LeftColumn extends StatelessWidget {
  final GlobalKey<FormState> profileFormKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final VoidCallback onSaveProfile;
  final VoidCallback onChangePassword;

  // learner/license bindings
  final bool isLearnerHolder;
  final ValueChanged<bool> onLearnerChanged;
  final TextEditingController learnerNumberController;
  final DateTime? learnerExpiry;
  final ValueChanged<DateTime?> onPickLearnerExpiry;

  final bool isLicenseHolder;
  final ValueChanged<bool> onLicenseChanged;
  final TextEditingController licenseNumberController;
  final DateTime? licenseExpiry;
  final ValueChanged<DateTime?> onPickLicenseExpiry;

  final DateTime? licenseIssued;
  final ValueChanged<DateTime?> onPickLicenseIssued;
  final TextEditingController licenseAuthorityController;

  // avatar
  final VoidCallback onPickAvatar;
  final XFile? profilePhotoFile;

  const _LeftColumn({
    required this.profileFormKey,
    required this.nameController,
    required this.emailController,
    required this.onSaveProfile,
    required this.onChangePassword,
    required this.isLearnerHolder,
    required this.onLearnerChanged,
    required this.learnerNumberController,
    required this.learnerExpiry,
    required this.onPickLearnerExpiry,
    required this.isLicenseHolder,
    required this.onLicenseChanged,
    required this.licenseNumberController,
    required this.licenseExpiry,
    required this.onPickLicenseExpiry,
    required this.licenseIssued,
    required this.onPickLicenseIssued,
    required this.licenseAuthorityController,
    required this.onPickAvatar,
    required this.profilePhotoFile,
  });

  String _formatDate(DateTime? d) {
    if (d == null) return 'Tap to select';
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CardSection(
          title: 'Profile',
          subtitle: 'Update your name, email and documents',
          child: Form(
            key: profileFormKey,
            child: Column(
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: onPickAvatar,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: (profilePhotoFile != null && !kIsWeb)
                                  ? FileImage(File(profilePhotoFile!.path)) as ImageProvider
                                  : (profilePhotoFile != null && kIsWeb)
                                      ? NetworkImage(profilePhotoFile!.path)
                                      : null,
                              child: (profilePhotoFile == null) ? const Icon(Icons.person, size: 48) : null,
                            ),
                            Container(
                              decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(Icons.edit, size: 16, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(onPressed: onPickAvatar, child: Text('Add / Change Profile Photo', style: TextStyle(color: Theme.of(context).primaryColor))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Learner holder
                InputDecorator(
                  decoration: const InputDecoration(label: Text("Are you a learner's holder?"), border: OutlineInputBorder()),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      value: isLearnerHolder,
                      items: const [
                        DropdownMenuItem(value: false, child: Text('No')),
                        DropdownMenuItem(value: true, child: Text('Yes')),
                      ],
                      onChanged: onLicenseChanged == null ? null : (v) {
                        // We intentionally allow both dropdowns to be toggled.
                        // Parent handlers will ensure disabling when appropriate.
                        if (v != null) onLearnerChanged(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (isLearnerHolder) ...[
                  TextFormField(
                    controller: learnerNumberController,
                    decoration: const InputDecoration(labelText: 'Learner Number', border: OutlineInputBorder()),
                    validator: (v) => (isLearnerHolder && (v == null || v.trim().isEmpty)) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 50),
                        initialDate: learnerExpiry ?? now,
                      );
                      if (picked != null) onPickLearnerExpiry(picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Learner Expiry', border: OutlineInputBorder()),
                      child: Text(_formatDate(learnerExpiry)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // License holder
                InputDecorator(
                  decoration: const InputDecoration(label: Text('Are you a license holder?'), border: OutlineInputBorder()),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      value: isLicenseHolder,
                      items: const [
                        DropdownMenuItem(value: false, child: Text('No')),
                        DropdownMenuItem(value: true, child: Text('Yes')),
                      ],
                      onChanged: (v) {
                        if (v != null) onLicenseChanged(v);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                if (isLicenseHolder) ...[
                  TextFormField(
                    controller: licenseNumberController,
                    decoration: const InputDecoration(labelText: 'License Number', border: OutlineInputBorder()),
                    validator: (v) => (isLicenseHolder && (v == null || v.trim().isEmpty)) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // License date of issue
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(now.year - 50),
                        lastDate: DateTime(now.year + 10),
                        initialDate: licenseIssued ?? now,
                      );
                      if (picked != null) onPickLicenseIssued(picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'License Date of Issue', border: OutlineInputBorder()),
                      child: Text(_formatDate(licenseIssued)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: licenseAuthorityController,
                    decoration: const InputDecoration(labelText: 'Licensing Authority', border: OutlineInputBorder(), hintText: 'E.g. RTO Ernakulam'),
                    validator: (v) => (isLicenseHolder && (v == null || v.trim().isEmpty)) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // expiry
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 50),
                        initialDate: licenseExpiry ?? now,
                      );
                      if (picked != null) onPickLicenseExpiry(picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'License Expiry', border: OutlineInputBorder()),
                      child: Text(_formatDate(licenseExpiry)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onSaveProfile,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Changes'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onChangePassword,
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Change Password'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  final Map<String, dynamic>? currentPlan;
  final VoidCallback onShowPlans;
  final VoidCallback onLogout;
  final VoidCallback onSelectBoarding;

  const _RightColumn({
    required this.currentPlan,
    required this.onShowPlans,
    required this.onLogout,
    required this.onSelectBoarding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CardSection(
          title: 'Subscription',
          subtitle: 'View or change your plan anytime',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currentPlan != null)
                _CurrentPlanTile(
                  name: (currentPlan!['name'] ?? currentPlan!['id']).toString(),
                  description: (currentPlan!['description'] ?? '').toString(),
                  price: currentPlan!['price'],
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'No active plan found',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onShowPlans,
                icon: const Icon(Icons.upgrade),
                label: Text(currentPlan != null ? 'Change Plan' : 'Select Plan'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onSelectBoarding,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Select Boarding Point'),
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: Boarding pickup beyond free radius may incur extra KM charges as per your plan.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CardSection(
          title: 'Logout',
          subtitle: 'Sign out from this device',
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onLogout();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
