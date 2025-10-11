// lib/learners_application_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:smart_drive/theme/app_theme.dart';
import 'package:smart_drive/upload_document_page.dart';

const String _hostingerBase = 'https://tajdrivingschool.in/smartDrive/payments';
// Provide Razorpay key via --dart-define
const String _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');

class LearnersApplicationPage extends StatefulWidget {
  const LearnersApplicationPage({super.key});

  @override
  State<LearnersApplicationPage> createState() =>
      _LearnersApplicationPageState();
}

class _LearnersApplicationPageState extends State<LearnersApplicationPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // UI state
  bool _acknowledged = false;
  bool _docsUploaded = false; // simulate; you can replace with real upload state
  bool _loadingSettings = true;
  bool _processing = false;

  // Razorpay
  Razorpay? _razorpay;
  String? _lastOrderId;

  // Fee from settings (in rupees)
  double _applicationFee = 0.0;
  double _retestFee = 0.0; // NEW: retest fee

  // track whether current payment is for application or retest
  String? _currentPaymentPurpose; // 'application' | 'retest'

  // simple controllers
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadSettings();
    _populateFromAuth();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final doc = await _fs
          .collection('settings')
          .doc('app_settings')
          .get(const GetOptions(source: Source.serverAndCache));
      if (doc.exists) {
        final m = doc.data() ?? {};
        final rawApp = m['learner_application_fee'] ??
            m['learners_application_fee'] ??
            m['learner_application_fees'];
        double feeApp = 0.0;
        if (rawApp is num) feeApp = rawApp.toDouble();
        else if (rawApp is String) feeApp = double.tryParse(rawApp) ?? 0.0;

        final rawRetest = m['learner_retest_fee'];
        double feeRetest = 0.0;
        if (rawRetest is num) feeRetest = rawRetest.toDouble();
        else if (rawRetest is String) feeRetest = double.tryParse(rawRetest) ?? 0.0;

        setState(() {
          _applicationFee = feeApp;
          _retestFee = feeRetest;
        });
      } else {
        setState(() {
          _applicationFee = 0.0;
          _retestFee = 0.0;
        });
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      setState(() {
        _applicationFee = 0.0;
        _retestFee = 0.0;
      });
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _populateFromAuth() async {
    final user = _auth.currentUser;
    if (user == null) return;
    _nameCtrl.text = (user.displayName ?? '').trim();
    _emailCtrl.text = (user.email ?? '').trim();
    _phoneCtrl.text = (user.phoneNumber ?? '').trim();
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse),
      ),
      backgroundColor: color ?? AppColors.onSurface,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ---------------- Server helpers (same pattern as booking_page) ----------------

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
    if (data is! Map<String, dynamic>) throw Exception('Invalid JSON from server');
    return data;
  }

  // Extended to accept payment type (application|retest) to help server set order notes & receipt
  Future<String> _createOrderOnServer({required int amountPaise, String type = 'application'}) async {
    final res = await _postJson(
      '$_hostingerBase/createOrder.php',
      {
        'amountPaise': amountPaise,
        'receipt': 'learner_${type}_${DateTime.now().millisecondsSinceEpoch}',
        'notes': {
          'type': type == 'retest' ? 'learner_retest' : 'learner_application',
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

  // ---------------- Payment flow ----------------

  Future<void> _startPaymentFlow() async {
    if (!_acknowledged) {
      _snack('Please acknowledge the declaration', color: AppColors.warning);
      return;
    }

    final payable = _applicationFee;
    _currentPaymentPurpose = 'application';

    if (payable <= 0.0) {
      await _createApplicationDocument(status: 'confirmed', paidAmount: 0.0, type: 'application');
      _snack('Application submitted (free)', color: AppColors.success);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    try {
      setState(() => _processing = true);
      final amountPaise = (payable * 100).round();
      _snack('Preparing payment…');
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise, type: 'application');
      await _openRazorpayCheckout(orderId: _lastOrderId!, amountPaise: amountPaise);
    } catch (e) {
      _snack('Could not start payment: $e', color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _startRetestFlow() async {
    final payable = _retestFee;
    _currentPaymentPurpose = 'retest';

    if (payable <= 0.0) {
      await _createApplicationDocument(status: 'confirmed', paidAmount: 0.0, type: 'retest');
      _snack('Retest application submitted (free)', color: AppColors.success);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    try {
      setState(() => _processing = true);
      final amountPaise = (payable * 100).round();
      _snack('Preparing retest payment…');
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise, type: 'retest');
      await _openRazorpayCheckout(orderId: _lastOrderId!, amountPaise: amountPaise);
    } catch (e) {
      _snack('Could not start retest payment: $e', color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openRazorpayCheckout({required String orderId, required int amountPaise}) async {
    if (_razorpay == null) {
      _snack('Payment unavailable', color: AppColors.danger);
      return;
    }
    if (_razorpayKeyId.isEmpty) {
      _snack('Razorpay key missing. Provide via --dart-define=RAZORPAY_KEY_ID', color: AppColors.danger);
      return;
    }

    String? prefillName = _nameCtrl.text.trim();
    String? prefillEmail = _emailCtrl.text.trim();
    String? prefillContact = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');

    final options = {
      'key': _razorpayKeyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'SmartDrive',
      'description': _currentPaymentPurpose == 'retest' ? "Learner's retest fee" : "Learner's application fee",
      'prefill': {
        if (prefillContact.isNotEmpty) 'contact': prefillContact,
        if (prefillEmail.isNotEmpty) 'email': prefillEmail,
        if (prefillName.isNotEmpty) 'name': prefillName,
      },
      'notes': {'purpose': _currentPaymentPurpose == 'retest' ? 'learner_retest' : 'learner_application'},
      'theme': {'color': '#FFFFFF'},
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      _snack('Unable to open payment: $e', color: AppColors.danger);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    if (r.orderId == null || r.paymentId == null || r.signature == null) {
      _snack('Payment response incomplete', color: AppColors.danger);
      return;
    }

    final purpose = _currentPaymentPurpose ?? 'application';
    final expectedPaise = ((purpose == 'retest' ? _retestFee : _applicationFee) * 100).round();

    _snack('Payment completed — verifying…', color: AppColors.info);

    bool valid = false;
    try {
      valid = await _verifyPaymentOnServer(
        razorpayOrderId: r.orderId!,
        razorpayPaymentId: r.paymentId!,
        razorpaySignature: r.signature!,
        expectedAmountPaise: expectedPaise,
      );
    } catch (e) {
      _snack('Verification error: $e', color: AppColors.danger);
      return;
    }

    if (!valid) {
      _snack('Payment verification failed. Contact support.', color: AppColors.danger);
      return;
    }

    final paidAmount = (purpose == 'retest' ? _retestFee : _applicationFee);
    final createdRef = await _createApplicationDocument(
      status: 'paid',
      paidAmount: paidAmount,
      type: purpose == 'retest' ? 'retest' : 'application',
    );

    if (createdRef != null) {
      _snack('${purpose == 'retest' ? 'Retest' : 'Application'} submitted successfully', color: AppColors.success);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _snack('Payment failed${msg != null && msg.isNotEmpty ? ': $msg' : ''}', color: AppColors.danger);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack('External wallet: ${r.walletName ?? ''}');
  }

  // ---------------- Firestore write ----------------
  // returns the created application DocumentReference or null
  Future<DocumentReference?> _createApplicationDocument({
    required String status,
    required double paidAmount,
    String type = 'application', // NEW: record whether this is 'application' or 'retest'
  }) async {
    setState(() => _processing = true);
    try {
      final applicationsRef = _fs.collection('learner_applications').doc();
      final uid = _auth.currentUser?.uid;

      final doc = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'userId': uid,
        'paid_amount': paidAmount,
        'status': status,
        'type': type,
        'created_at': FieldValue.serverTimestamp(),
      };

      await applicationsRef.set(doc);
      return applicationsRef;
    } catch (e) {
      _snack('Failed to save application: $e', color: AppColors.danger);
      return null;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ---------------- UI / Upload sim ----------------

  Future<void> _simulateUploadDocuments() async {
    setState(() => _processing = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _docsUploaded = true;
      _processing = false;
    });
    _snack('Documents uploaded (simulated)', color: AppColors.success);
  }

  // ---------------- Responsive layout helpers ----------------

  Widget _buildRequiredDocsBlock(BuildContext context, {bool compact = false}) {
    final children = <Widget>[
      const _DocItem(title: "Proof of Identity", desc: "Aadhaar, Passport, or Voter ID"),
      const _DocItem(title: "Proof of Address", desc: "Utility bill or bank statement (within 3 months)"),
      const _DocItem(title: "Age Proof", desc: "Birth certificate or school certificate"),
      const _DocItem(title: "Passport Size Photographs", desc: "2 photos with white background"),
      const _DocItem(title: "Medical Certificate", desc: "Fitness certificate from registered doctor"),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.folder_copy, color: AppColors.brand),
            const SizedBox(width: 8),
            Text("Required Documents", style: AppText.sectionTitle),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.neuBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...children,
                const SizedBox(height: 6),
                const Text(
                  "All documents should be clear, legible, and in JPG, PNG, or PDF.",
                  style: TextStyle(fontSize: 12),
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _processing
                      ? null
                      : () async {
                          final res = await Navigator.of(context).push<bool?>(MaterialPageRoute(builder: (_) => const UploadDocumentPage()));
                          if (res == true) {
                            setState(() => _docsUploaded = true);
                            _snack('Documents uploaded', color: AppColors.success);
                          }
                        },
                  icon: const Icon(Icons.upload_file),
                  label: Text(_docsUploaded ? 'Documents uploaded' : 'Upload Documents'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onSurfaceInverse,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payableText = _applicationFee <= 0.0 ? 'FREE' : '₹${_applicationFee.toStringAsFixed(2)}';
    final uid = _auth.currentUser?.uid;

    // Top-level layout: responsive widths and proper scrolling to avoid overflow.
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("Learner's Application"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: _loadingSettings
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              // Breakpoints tuned for mobile / tablet / desktop
              final maxWidth = constraints.maxWidth;
              final isNarrow = maxWidth < 720;
              final contentPadding = EdgeInsets.symmetric(horizontal: math.min(20.0, maxWidth * 0.03), vertical: 16);

              // Use a scrollable container to prevent vertical overflow on small screens
              return SingleChildScrollView(
                padding: contentPadding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (uid != null)
                          StreamBuilder<QuerySnapshot>(
                            stream: _fs
                                .collection('learner_applications')
                                .where('userId', isEqualTo: uid)
                                .orderBy('created_at', descending: true)
                                .limit(1)
                                .snapshots(),
                            builder: (context, snapshot) {
                              final bool hasApp = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                              Map<String, dynamic>? appData;
                              if (hasApp) {
                                appData = snapshot.data!.docs.first.data() as Map<String, dynamic>?;
                              }

                              final myAppCard = Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.surface,
                                  boxShadow: AppShadows.card,
                                ),
                                child: snapshot.connectionState == ConnectionState.waiting
                                    ? const Text("Loading your application...")
                                    : (!hasApp
                                        ? Row(
                                            children: [
                                              Icon(Icons.person, color: AppColors.brand),
                                              const SizedBox(width: 10),
                                              Text("My Application", style: AppText.sectionTitle),
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Icon(Icons.person, color: AppColors.brand),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(appData?['name'] ?? '', style: AppText.sectionTitle),
                                                    const SizedBox(height: 6),
                                                    Text(appData?['email'] ?? '', style: AppText.tileSubtitle),
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        Text('Status: ', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                                                        Text((appData?['status'] ?? '-').toString(), style: AppText.tileSubtitle),
                                                        const SizedBox(width: 12),
                                                        Text('Paid: ', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                                                        Text('₹${(appData?['paid_amount'] ?? 0).toString()}', style: AppText.tileSubtitle),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: AppColors.okBg,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Applied',
                                                  style: AppText.tileSubtitle.copyWith(color: AppColors.okFg, fontWeight: FontWeight.w700),
                                                ),
                                              ),
                                            ],
                                          )),
                              );

                              Widget contentBelow;
                              if (hasApp && appData != null) {
                                final status = (appData['status'] ?? 'pending').toString().toLowerCase();

                                if (status == 'confirmed') {
                                  contentBelow = Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: AppColors.surface,
                                      boxShadow: AppShadows.card,
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 92,
                                          height: 92,
                                          decoration: BoxDecoration(
                                            color: AppColors.okBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(Icons.verified, size: 52, color: AppColors.okFg),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Application Confirmed',
                                          style: AppText.sectionTitle.copyWith(fontSize: 20),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "Your application has been reviewed and confirmed. Contact Admin to know about further steps.",
                                          style: AppText.tileSubtitle,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Text('Retest Fee', style: AppText.tileTitle.copyWith(fontSize: 14)),
                                              const SizedBox(height: 4),
                                              Text(_retestFee <= 0 ? 'FREE' : '₹${_retestFee.toStringAsFixed(2)}', style: AppText.tileSubtitle),
                                            ]),
                                            ElevatedButton(
                                              onPressed: _processing ? null : _startRetestFlow,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.brand,
                                                foregroundColor: AppColors.onSurfaceInverse,
                                                minimumSize: const Size(140, 44),
                                              ),
                                              child: _processing
                                                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onSurfaceInverse, strokeWidth: 2))
                                                  : Text('Apply for Retest'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'If you choose to apply for a retest, you will be charged the retest fee and a new retest application will be created.',
                                          style: AppText.tileSubtitle.copyWith(fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (status == 'rejected') {
                                  contentBelow = Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          color: AppColors.surface,
                                          boxShadow: AppShadows.card,
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              width: 92,
                                              height: 92,
                                              decoration: BoxDecoration(
                                                color: AppColors.warnBg,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Icon(Icons.block, size: 52, color: AppColors.warning),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Application Rejected',
                                              style: AppText.sectionTitle.copyWith(fontSize: 20),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Your application has been rejected. Please review the requirements, update your documents, and re-apply if you'd like to proceed.",
                                              style: AppText.tileSubtitle,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 14),
                                            _buildRequiredDocsBlock(context),
                                            const SizedBox(height: 12),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.surface,
                                                borderRadius: BorderRadius.circular(12),
                                                boxShadow: AppShadows.card,
                                              ),
                                              child: Row(
                                                children: [
                                                  Checkbox(
                                                    value: _acknowledged,
                                                    onChanged: (v) => setState(() => _acknowledged = v ?? false),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      'I confirm I have updated/uploaded required documents and the information provided is accurate and complete.',
                                                      style: AppText.tileSubtitle,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text('Application Fee', style: AppText.tileTitle.copyWith(fontSize: 14)),
                                                  const SizedBox(height: 4),
                                                  Text(_applicationFee <= 0 ? 'FREE' : '₹${_applicationFee.toStringAsFixed(2)}', style: AppText.tileSubtitle),
                                                ]),
                                                ElevatedButton(
                                                  onPressed: (_processing || !_acknowledged) ? null : _startPaymentFlow,
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: AppColors.brand,
                                                    foregroundColor: AppColors.onSurfaceInverse,
                                                    minimumSize: const Size(140, 44),
                                                  ),
                                                  child: _processing
                                                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onSurfaceInverse, strokeWidth: 2))
                                                      : Text('Re-apply'),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'You may re-apply after correcting any issues in your documents. If you re-apply and payment is required, the application fee will be charged again.',
                                              style: AppText.tileSubtitle.copyWith(fontSize: 12),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  contentBelow = Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: AppColors.surface,
                                      boxShadow: AppShadows.card,
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 92,
                                          height: 92,
                                          decoration: BoxDecoration(
                                            color: AppColors.okBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(Icons.check, size: 52, color: AppColors.okFg),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Application Submitted',
                                          style: AppText.sectionTitle.copyWith(fontSize: 20),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "We've received your application. Our team will review it and contact you if any further information is required.",
                                          style: AppText.tileSubtitle,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          'For further inquiries, please contact the admin.',
                                          style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                    ),
                                  );
                                }
                              } else {
                                // No app -> default new application flow
                                contentBelow = Column(
                                  children: [
                                    _buildRequiredDocsBlock(context),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Application Fee', style: AppText.tileTitle),
                                        Text(payableText, style: AppText.tileTitle.copyWith(color: _applicationFee <= 0 ? AppColors.success : AppColors.onSurface)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: AppShadows.card,
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: _acknowledged,
                                            onChanged: (v) => setState(() => _acknowledged = v ?? false),
                                          ),
                                          Expanded(
                                            child: Text(
                                              'I acknowledge I have uploaded all required documents and the information provided is accurate and complete.',
                                              style: AppText.tileSubtitle,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: (_acknowledged && !_processing) ? _startPaymentFlow : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: (_acknowledged && !_processing) ? AppColors.brand : Colors.grey,
                                          foregroundColor: AppColors.onSurfaceInverse,
                                          minimumSize: const Size.fromHeight(54),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
                                        ),
                                        child: _processing
                                            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.onSurfaceInverse))
                                            : Text(_applicationFee <= 0 ? 'Submit Application' : 'Proceed to Pay', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  myAppCard,
                                  contentBelow,
                                  const SizedBox(height: 12),
                                ],
                              );
                            },
                          )
                        else
                          // Not signed in: show full new-app flow but prompt sign-in
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.surface,
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("My Application", style: AppText.sectionTitle),
                                    const SizedBox(height: 8),
                                    Text("Please sign in to view your applications.", style: AppText.tileSubtitle),
                                  ],
                                ),
                              ),
                              _buildRequiredDocsBlock(context),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Application Fee', style: AppText.tileTitle),
                                  Text(payableText, style: AppText.tileTitle.copyWith(color: _applicationFee <= 0 ? AppColors.success : AppColors.onSurface)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _acknowledged,
                                      onChanged: (v) => setState(() => _acknowledged = v ?? false),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'I acknowledge I have uploaded all required documents and the information provided is accurate and complete.',
                                        style: AppText.tileSubtitle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (_acknowledged && !_processing) ? _startPaymentFlow : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: (_acknowledged && !_processing) ? AppColors.brand : Colors.grey,
                                    foregroundColor: AppColors.onSurfaceInverse,
                                    minimumSize: const Size.fromHeight(54),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
                                  ),
                                  child: _processing
                                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.onSurfaceInverse))
                                      : Text(_applicationFee <= 0 ? 'Submit Application' : 'Proceed to Pay', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),

                        // Spacer to push bottom content up on tall screens
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            }),
    );
  }
}

class _DocItem extends StatelessWidget {
  final String title;
  final String desc;
  const _DocItem({required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppText.tileSubtitle.copyWith(color: AppColors.onSurface),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
