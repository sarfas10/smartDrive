// lib/test_booking_page.dart
// Flutter page that implements a test-slot booking UI with Razorpay
// Stores bookings in Firestore under collection `test_bookings`
// Reads charges from Firestore document: collection "settings", doc "app_settings"
// Writes logged-in user info (uid, name, email, phone) to Firestore
// Uses your design tokens from app_theme.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:smart_drive/reusables/branding.dart' hide AppColors, AppText;
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart'; // adjust import path as needed
import 'view_bookings_page.dart'; // new page to view bookings

enum TestType { classB, classH }

/// NOTE: Replace with your server endpoints that create & verify Razorpay orders.
const String _hostingerBase = 'https://tajdrivingschool.in/smartDrive/payments';

// Pass only public key via --dart-define
const String _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');

class TestBookingPage extends StatefulWidget {
  const TestBookingPage({Key? key}) : super(key: key);

  @override
  State<TestBookingPage> createState() => _TestBookingPageState();
}

class _TestBookingPageState extends State<TestBookingPage> {
  final Set<TestType> _selectedTests = <TestType>{};
  DateTime _visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  String _specialRequests = '';
  bool _saving = false;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;

  // default charges (overridden by settings doc)
  int _chargeB = 85;
  int _chargeH = 120;
  bool _chargesLoaded = false;

  // Razorpay
  Razorpay? _razorpay;
  String? _lastOrderId;
  bool _isProcessingPayment = false;

  // ---------- Admin popup state ----------
  Map<String, dynamic>? _adminPopup;
  VideoPlayerController? _popupVideoController;
  Future<void>? _initializePopupVideoFuture;
  VoidCallback? _popupVideoListener;
  bool _popupBusyOverlay = false;
  Timer? _popupCountdownTimer;

  @override
  void initState() {
    super.initState();
    _listenSettings();
    _initRazorpay();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _razorpay?.clear();
    _removePopupVideoListener();
    try {
      _popupVideoController?.dispose();
    } catch (_) {}
    _popupCountdownTimer?.cancel();
    super.dispose();
  }

  void _initRazorpay() {
    try {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    } catch (e) {
      // ignore init failures in dev
      debugPrint('Razorpay init error: $e');
    }
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
        backgroundColor: color ?? AppColors.onSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _listenSettings() {
    _settingsSub = _db.collection('settings').doc('app_settings').snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data() ?? {};
        final dynamic bVal = data['test_charge_b'] ?? data['test_charge_8'] ?? data['test_charge-8'];
        final dynamic hVal = data['test_charge_h'] ?? data['test_charge-h'];
        setState(() {
          if (bVal != null) {
            try {
              _chargeB = (bVal is num) ? bVal.toInt() : int.parse(bVal.toString());
            } catch (_) {}
          }
          if (hVal != null) {
            try {
              _chargeH = (hVal is num) ? hVal.toInt() : int.parse(hVal.toString());
            } catch (_) {}
          }
          _chargesLoaded = true;
        });
      } else {
        setState(() => _chargesLoaded = true);
      }
    }, onError: (_) {
      setState(() => _chargesLoaded = true);
    });
  }

  int get _selectedTotalMinutes {
    var total = 0;
    for (var t in _selectedTests) {
      total += (t == TestType.classB ? 45 : 60);
    }
    return total;
  }

  int get _selectedTotalPrice {
    var total = 0;
    for (var t in _selectedTests) {
      total += (t == TestType.classB ? _chargeB : _chargeH);
    }
    return total;
  }

  // ---------------- Server helpers ----------------

  Future<Map<String, dynamic>> _postJson(String url, Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) throw Exception('Invalid JSON from server');
    return data;
  }

  Future<String> _createOrderOnServer({required int amountPaise}) async {
    final res = await _postJson('$_hostingerBase/createOrder.php', {
      'amountPaise': amountPaise,
      'receipt': 'test_booking_${DateTime.now().millisecondsSinceEpoch}',
      'notes': {'purpose': 'test_booking'}
    });
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
    final res = await _postJson('$_hostingerBase/verifyPayment.php', {
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
      'expectedAmountPaise': expectedAmountPaise,
    });
    return (res['valid'] == true);
  }

  // ---------------- Payment flow ----------------

  Future<bool> _isBookingFreeForUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      // 1. Fetch planId from user_plans/{uid}
      final planSnap = await _db.collection('user_plans').doc(user.uid).get();
      final planId = planSnap.data()?['planId'];
      if (planId == null || planId.toString().isEmpty) return false;

      // 2. Fetch plan details from plans/{planId}
      final planSnap2 = await _db.collection('plans').doc(planId.toString()).get();
      final planData = planSnap2.data() ?? {};

      bool allowB = planData['driving_test_8'] == true;
      bool allowH = planData['driving_test_h'] == true;

      // 3. Match with selected tests
      if (_selectedTests.contains(TestType.classB) && !allowB) return false;
      if (_selectedTests.contains(TestType.classH) && !allowH) return false;

      // 4. Ensure test not attempted already
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.data()?['test_attempted'] == true) return false;

      // ✅ Eligible for free booking
      return true;
    } catch (e) {
      debugPrint('Free plan check error: $e');
      return false;
    }
  }

  Future<void> _onConfirmPressed() async {
    if (_selectedTests.isEmpty || _selectedDate == null) return;

    // 🔹 Check free plan eligibility
    final isFree = await _isBookingFreeForUser();
    if (isFree) {
      await _saveBookingToFirestore(paymentInfo: null, paidAmount: 0, status: 'pending');

      // also mark test_attempted = true
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await _db.collection('users').doc(user.uid).update({'test_attempted': true});
        } catch (_) {}
      }
      return;
    }

    final total = _selectedTotalPrice;
    if (total <= 0) {
      await _saveBookingToFirestore(paymentInfo: null, paidAmount: 0, status: 'pending');
      return;
    }

    // Normal payment flow
    final amountPaise = total * 100;
    setState(() => _isProcessingPayment = true);
    _snack('Preparing payment…');
    try {
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise);
      _openRazorpayCheckout(orderId: _lastOrderId!, amountPaise: amountPaise);
    } catch (e) {
      _snack('Could not start payment: $e', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
    }
  }

  void _openRazorpayCheckout({required String orderId, required int amountPaise}) {
    if (_razorpay == null) {
      _snack('Payment is unavailable right now. Please try again.', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
      return;
    }
    if (_razorpayKeyId.isEmpty) {
      _snack('Razorpay key missing. Pass --dart-define=RAZORPAY_KEY_ID=your_key', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
      return;
    }

    final options = {
      'key': _razorpayKeyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': AppBrand.appName,
      'description': 'Test Booking Payment',
      'prefill': {'contact': '', 'email': '', 'name': ''},
      'theme': {'color': '#FFFFFF'},
      'method': {'card': true, 'upi': true, 'netbanking': true, 'wallet': false, 'emi': false},
      'timeout': 300
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      _snack('Unable to open payment: $e', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    if (r.orderId == null || r.paymentId == null || r.signature == null) {
      _snack('Payment success response incomplete', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
      return;
    }

    final expectedAmountPaise = _selectedTotalPrice * 100;
    bool valid = false;
    try {
      valid = await _verifyPaymentOnServer(
        razorpayOrderId: r.orderId!,
        razorpayPaymentId: r.paymentId!,
        razorpaySignature: r.signature!,
        expectedAmountPaise: expectedAmountPaise,
      );
    } catch (e) {
      _snack('Verification error: $e', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
      return;
    }

    if (!valid) {
      _snack('Payment verification failed. Please contact support.', color: AppColors.danger);
      setState(() => _isProcessingPayment = false);
      return;
    }

    // Save booking but keep status 'pending' for admin review
    await _saveBookingToFirestore(
      paymentInfo: {
        'razorpay_payment_id': r.paymentId,
        'razorpay_order_id': r.orderId,
        'razorpay_signature': r.signature
      },
      paidAmount: _selectedTotalPrice,
      status: 'pending',
    );
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _snack('Payment failed${msg != null && msg.isNotEmpty ? ': $msg' : ''}', color: AppColors.danger);
    setState(() => _isProcessingPayment = false);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack('Using external wallet: ${r.walletName ?? ''}');
  }

  // ---------------- Firestore write ----------------

  /// Save booking doc. `status` defaults to 'pending' so admin can review/confirm.
  /// Also records the logged-in Firebase Auth user info (uid, displayName, email, phone).
  /// If paymentInfo is provided, this function will attempt to also write a `payments` document
  /// with type = "test booking" (best-effort).
  Future<void> _saveBookingToFirestore({
    Map<String, dynamic>? paymentInfo,
    required num paidAmount,
    String status = 'pending',
  }) async {
    setState(() {
      _saving = true;
      _isProcessingPayment = false;
    });

    try {
      final chargesMap = <String, int>{};
      if (_selectedTests.contains(TestType.classB)) chargesMap['Class B'] = _chargeB;
      if (_selectedTests.contains(TestType.classH)) chargesMap['Class H'] = _chargeH;

      final user = FirebaseAuth.instance.currentUser;
      String? userPhone;
      String? userName;
      String? userEmail;

      if (user != null) {
        // try fetch from users collection for richer profile if auth lacks fields
        try {
          final ud = await _db.collection('users').doc(user.uid).get();
          final map = ud.data();
          if (map != null) {
            userPhone = map['phone']?.toString();
            userName = map['name']?.toString() ?? map['user_name']?.toString();
            userEmail = map['email']?.toString();
          }
        } catch (_) {}
        userPhone ??= user.phoneNumber;
        userName ??= user.displayName;
        userEmail ??= user.email;
      }

      final doc = <String, dynamic>{
        'test_types': _selectedTests.map((t) => t == TestType.classB ? 'Class B' : 'Class H').toList(),
        'date': DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day),
        'created_at': FieldValue.serverTimestamp(),
        'special_requests': _specialRequests,
        'charges': chargesMap,
        'total_minutes': _selectedTotalMinutes,
        'total_price': _selectedTotalPrice,
        'paid_amount': paidAmount,
        'status': status,
        if (paymentInfo != null) 'payment': paymentInfo,
        if (_lastOrderId != null) 'razorpay_order_id': _lastOrderId,
        if (user != null) 'user_id': user.uid,
        if (userName != null) 'user_name': userName,
        if (userEmail != null) 'email': userEmail,
        if (userPhone != null) 'phone': userPhone,
      };

      final added = await _db.collection('test_bookings').add(doc);

      if (!mounted) return;
      _snack('Booking saved successfully', color: AppColors.success);
      setState(() {
        _selectedTests.clear();
        _selectedDate = null;
        _specialRequests = '';
        _lastOrderId = null;
      });

      // If payment info was provided (paid booking), try to save a payment record (best-effort).
      if (paymentInfo != null) {
        try {
          await _savePaymentRecord(
            userId: user?.uid,
            bookingId: added.id,
            amountRupees: paidAmount.toDouble(),
            amountPaise: (paidAmount * 100).toInt(),
            currency: 'INR',
            razorpayPaymentId: paymentInfo['razorpay_payment_id']?.toString() ?? '',
            razorpayOrderId: paymentInfo['razorpay_order_id']?.toString() ?? '',
            razorpaySignature: paymentInfo['razorpay_signature']?.toString() ?? '',
          );
        } catch (e, st) {
          debugPrint('Failed to save payment record (non-fatal): $e\n$st');
        }
      }

      // Fetch & show admin popup (if any) after booking saved
      try {
        final found = await _fetchActiveAdminPopup();
        if (found && _adminPopup != null) {
          final bookingData = {
            'booking_id': added.id,
            'status': status,
            'paid_amount': paidAmount,
          };
          await _showAdminPopup(bookingData);
        } else {
          debugPrint('No admin popup found after saving booking.');
        }
      } catch (e, st) {
        debugPrint('Popup show error after booking: $e\n$st');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to save booking: $e', color: AppColors.danger);
    } finally {
      if (mounted) setState(() {
        _saving = false;
        _isProcessingPayment = false;
      });
    }
  }

  // ------------------ Payments collection helper ------------------

  /// Best-effort save of a payment record to `payments` collection.
  /// userId may be null if the user was not signed in; that field will be omitted in that case.
  Future<void> _savePaymentRecord({
    String? userId,
    required String bookingId,
    required double amountRupees,
    required int amountPaise,
    required String currency,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    try {
      final fs = FirebaseFirestore.instance;

      // Try to get a friendly payer name from users collection -> fallback to FirebaseAuth
      String payerName = '';
      try {
        if (userId != null && userId.isNotEmpty) {
          final userDoc = await fs.collection('users').doc(userId).get();
          if (userDoc.exists) {
            final d = userDoc.data();
            if (d != null) {
              payerName = (d['name'] ?? d['displayName'] ?? d['fullName'] ?? '').toString();
            }
          }
        }
      } catch (_) {
        // ignore - fallback below
      }

      if (payerName.trim().isEmpty) {
        final authUser = FirebaseAuth.instance.currentUser;
        payerName = (authUser?.displayName ?? '').toString();
      }

      final paymentDoc = {
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
        'payer_name': payerName,
        'booking_id': bookingId,
        'amount': amountRupees, // rupees (double)
        'amount_paise': amountPaise, // integer paise
        'currency': currency,
        'type': 'test booking',
        'method': 'razorpay',
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_signature': razorpaySignature,
        'created_at': FieldValue.serverTimestamp(),
        'raw': {
          'saved_at_client_ts': DateTime.now().toIso8601String(),
        },
      };

      await fs.collection('payments').add(paymentDoc);
      debugPrint('Payment saved for booking $bookingId');
    } catch (e, st) {
      debugPrint('Failed to save payment record: $e\n$st');
      // Do not rethrow — booking succeeded, we simply log payment-save failure.
    }
  }

  // ========== Admin popup helpers (copied/adapted from booking_page.dart) ==========

  Future<bool> _fetchActiveAdminPopup() async {
    final fs = FirebaseFirestore.instance;

    try {
      final q = await fs
          .collection('admin_popups')
          .where('active', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        _adminPopup = q.docs.first.data();
        _adminPopup!['id'] = q.docs.first.id;
        debugPrint('Admin popup loaded (indexed): ${_adminPopup!['id']}');
        return true;
      } else {
        _adminPopup = null;
        debugPrint('No active admin popup found (indexed query returned empty)');
        return false;
      }
    } on FirebaseException catch (e) {
      debugPrint('Indexed admin_popups query failed: ${e.code} ${e.message}');
      if (e.code == 'failed-precondition' || (e.message?.toLowerCase().contains('index') ?? false)) {
        try {
          debugPrint('Falling back to non-indexed fetch for admin_popups (client-side sort)');
          final q2 = await fs.collection('admin_popups').where('active', isEqualTo: true).get();
          if (q2.docs.isEmpty) {
            _adminPopup = null;
            return false;
          }

          QueryDocumentSnapshot? best;
          for (final d in q2.docs) {
            if (best == null) {
              best = d;
              continue;
            }
            final a = d.data() as Map<String, dynamic>;
            final b = best.data() as Map<String, dynamic>;
            final ta = a['created_at'];
            final tb = b['created_at'];

            int _tsToMillis(dynamic t) {
              if (t == null) return 0;
              try {
                if (t is Timestamp) return t.millisecondsSinceEpoch;
                if (t is int) return t;
                if (t is double) return t.toInt();
                final s = t.toString();
                return int.tryParse(s) ?? 0;
              } catch (_) {
                return 0;
              }
            }

            if (_tsToMillis(ta) > _tsToMillis(tb)) best = d;
          }

          if (best != null) {
            _adminPopup = best.data() as Map<String, dynamic>;
            _adminPopup!['id'] = best.id;
            debugPrint('Admin popup loaded (fallback): ${_adminPopup!['id']}');
            return true;
          } else {
            _adminPopup = null;
            return false;
          }
        } catch (e2, st2) {
          debugPrint('Fallback fetch also failed: $e2\n$st2');
          _adminPopup = null;
          return false;
        }
      } else {
        debugPrint('Firestore error fetching admin popup: ${e.code} ${e.message}');
        _adminPopup = null;
        return false;
      }
    } catch (e, st) {
      debugPrint('Unexpected error fetching admin popup: $e\n$st');
      _adminPopup = null;
      return false;
    }
  }

  Future<void> _preparePopupVideo(String url) async {
    // Dispose previous controller if any
    try {
      await _popupVideoController?.dispose();
    } catch (_) {}
    _popupVideoController = VideoPlayerController.network(url);
    _initializePopupVideoFuture = _popupVideoController!.initialize();

    // initialize then auto-play
    await _initializePopupVideoFuture;
    _popupVideoController!.setLooping(false);

    // auto play immediately
    try {
      await _popupVideoController!.play();
    } catch (_) {}

    // we don't use play/pause UI, but we keep a listener to update UI if needed
    _removePopupVideoListener();
    _popupVideoListener = () {
      // nothing heavy here — used only to refresh state
      if (mounted) setState(() {});
    };
    _popupVideoController!.addListener(_popupVideoListener!);
  }

  void _removePopupVideoListener() {
    try {
      if (_popupVideoController != null && _popupVideoListener != null) {
        _popupVideoController!.removeListener(_popupVideoListener!);
      }
    } catch (_) {}
    _popupVideoListener = null;
  }

  /// Shows the same non-dismissible admin popup with loader + 10s countdown.
  /// bookingData is optional metadata shown/sent to server in future if needed.
  Future<void> _showAdminPopup(Map<String, dynamic> bookingData) async {
    if (!mounted) return Future.value();

    // Show busy overlay while we prepare the popup
    setState(() {
      _popupBusyOverlay = true;
    });

    // Reset outer helpers
    _popupCountdownTimer?.cancel();
    _popupCountdownTimer = null;
    bool _dialogMediaLoaded = false;
    int dialogCountdown = 10;

    final mediaType = (_adminPopup != null) ? (_adminPopup!['type'] ?? '').toString().toLowerCase() : '';
    final url = (_adminPopup != null) ? (_adminPopup!['url'] ?? '').toString() : '';
    final hasMedia = mediaType == 'image' || mediaType == 'video' || mediaType == 'pdf';

    // If video, prepare controller ahead of showing the dialog (so we can show quickly)
    if (mediaType == 'video' && url.isNotEmpty) {
      try {
        await _preparePopupVideo(url);
      } catch (e, st) {
        debugPrint('Video prepare/init error before dialog: $e\n$st');
        // continue — dialog will handle fallback
      }
    }

    // helper for dialog-local countdown start
    void startDialogCountdown(StateSetter sb, {int seconds = 10}) {
      dialogCountdown = seconds;
      _dialogMediaLoaded = true;
      sb(() {});
      // notify outer that the dialog is ready to be shown (so the outer busy overlay can hide)
      Future.microtask(() {
        if (mounted) setState(() => _popupBusyOverlay = false);
      });

      _popupCountdownTimer?.cancel();
      _popupCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        dialogCountdown -= 1;
        sb(() {});
        if (dialogCountdown <= 0) {
          _popupCountdownTimer?.cancel();
        }
      });
    }

    final infoText = (_adminPopup != null && (_adminPopup!['description'] ?? '').toString().isNotEmpty)
        ? (_adminPopup!['description'] ?? '').toString()
        : 'Important Road Safety Guidelines:\n\n• Please be on time at your booking point.\n• Wear a seatbelt at all times while in the vehicle.\n• Follow instructor directions and local traffic rules.\n• Report any safety concerns to us immediately.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        return StatefulBuilder(builder: (BuildContext dialogContext, StateSetter setDialogState) {
          // auto-start countdown when media ready
          if (!_dialogMediaLoaded && mediaType == 'video' && _popupVideoController != null && _popupVideoController!.value.isInitialized) {
            startDialogCountdown(setDialogState, seconds: 10);
          }
          if (!_dialogMediaLoaded && mediaType == 'image' && url.isNotEmpty) {
            // image will call loadingBuilder to start countdown once loaded.
          }
          if (!_dialogMediaLoaded && mediaType == 'pdf' && url.isNotEmpty) {
            // pdf: mark loaded immediately
            startDialogCountdown(setDialogState, seconds: 10);
          }

          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
              backgroundColor: AppColors.surface,
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              title: Row(
                children: [
                  Icon(Icons.traffic, color: AppColors.brand, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Road Safety',
                      style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasMedia) ...[
                      SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.s),
                          child: Container(
                            color: AppColors.neuBg,
                            child: Stack(
                              children: [
                                // Image handling: use loadingBuilder to trigger startDialogCountdown when loaded
                                if (mediaType == 'image' && url.isNotEmpty)
                                  Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) {
                                        if (!_dialogMediaLoaded) {
                                          startDialogCountdown(setDialogState, seconds: 10);
                                        }
                                        return child;
                                      }
                                      return const SizedBox.shrink();
                                    },
                                    errorBuilder: (c, e, st) {
                                      if (!_dialogMediaLoaded) startDialogCountdown(setDialogState, seconds: 10);
                                      return Center(child: Text('Could not load image', style: AppText.tileSubtitle));
                                    },
                                  )
                                // Video handling: show VideoPlayer when controller is ready
                                else if (mediaType == 'video' && _popupVideoController != null && _popupVideoController!.value.isInitialized)
                                  Center(
                                    child: AspectRatio(
                                      aspectRatio: _popupVideoController!.value.aspectRatio,
                                      child: VideoPlayer(_popupVideoController!),
                                    ),
                                  )
                                // PDF placeholder
                                else if (mediaType == 'pdf' && url.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 8),
                                        Icon(Icons.picture_as_pdf, size: 36, color: AppColors.danger),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text((_adminPopup!['description'] ?? 'Tap Open to view the PDF'), style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted))),
                                        TextButton(
                                          onPressed: () async {
                                            final uri = Uri.parse(url);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            } else {
                                              _snack('Could not open PDF', color: AppColors.danger);
                                            }
                                          },
                                          child: Text('Open', style: AppText.tileTitle.copyWith(color: AppColors.brand)),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  const SizedBox.shrink(),

                                // Circular loader overlay until mediaLoaded == true
                                if (!_dialogMediaLoaded)
                                  const Positioned.fill(
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Text(
                      infoText,
                      style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted, fontWeight: FontWeight.w500),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: AppColors.onSurfaceMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dialogMediaLoaded
                                ? ( (dialogCountdown <= 0) ? 'You may now acknowledge.' : 'Please wait ${dialogCountdown}s to acknowledge.')
                                : 'Loading…',
                            style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                    ),
                    onPressed: (_dialogMediaLoaded && dialogCountdown <= 0)
                        ? () async {
                            // cleanup local timer & dialog video listener
                            _popupCountdownTimer?.cancel();
                            try {
                              await _popupVideoController?.pause();
                              await _popupVideoController?.dispose();
                            } catch (_) {}
                            _popupVideoController = null;
                            _removePopupVideoListener();

                            Navigator.of(dialogContext).pop();
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Text('Acknowledge', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    // after dialog closes: ensure we stop & clean up timers/listeners
    _popupCountdownTimer?.cancel();
    _popupCountdownTimer = null;
    try {
      await _popupVideoController?.pause();
      await _popupVideoController?.dispose();
    } catch (_) {}
    _popupVideoController = null;
    _removePopupVideoListener();

    // ensure overlay hidden
    if (mounted) {
      setState(() {
        _popupBusyOverlay = false;
      });
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final horizontalPadding = math.min(20.0, screenW * 0.04);
    final contentSpacing = math.min(16.0, screenW * 0.04);

    final canConfirm = _selectedTests.isNotEmpty && _selectedDate != null && !_saving && !_isProcessingPayment;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        titleSpacing: 12,
        title: Row(
          children: [
            const Icon(Icons.directions_car),
            const SizedBox(width: 12),
            Text(AppBrand.appName, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceInverse,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                backgroundColor: Colors.transparent,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.list_alt, size: 20),
              label: const Text('My Bookings'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ViewBookingsPage()));
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availWidth = constraints.maxWidth - horizontalPadding * 2;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: contentSpacing),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildImportantNotice(),
                      SizedBox(height: contentSpacing),
                      _buildCardSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Select Test Type', style: AppText.sectionTitle),
                            const SizedBox(height: 12),
                            _buildTestTypeOption(
                              testType: TestType.classB,
                              title: 'Class B License',
                              subtitle: 'Motorcycle Test',
                              minutes: 45,
                              price: _chargeB,
                              icon: Icons.motorcycle,
                              availWidth: availWidth,
                            ),
                            const SizedBox(height: 12),
                            _buildTestTypeOption(
                              testType: TestType.classH,
                              title: 'Class H License',
                              subtitle: 'Heavy Vehicle Test',
                              minutes: 60,
                              price: _chargeH,
                              icon: Icons.local_shipping,
                              availWidth: availWidth,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      _buildCardSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Choose Your Date', style: AppText.sectionTitle),
                            const SizedBox(height: 12),
                            _buildMonthHeader(),
                            const SizedBox(height: 12),
                            _buildCalendarGrid(availWidth),
                          ],
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      _buildCardSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Special Requests', style: AppText.sectionTitle),
                                const SizedBox(width: 6),
                                Text('(Optional)', style: AppText.tileSubtitle),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              minLines: 3,
                              maxLines: 5,
                              onChanged: (v) => setState(() => _specialRequests = v),
                              decoration: InputDecoration(
                                hintText: 'Any specific time preferences, accessibility needs, or other requirements...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.s),
                                  borderSide: BorderSide(color: AppColors.divider),
                                ),
                                filled: true,
                                fillColor: AppColors.surface,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      if (_selectedTests.isNotEmpty) _buildSummaryRow(),
                      SizedBox(height: contentSpacing / 2),
                      ElevatedButton(
                        onPressed: canConfirm ? _onConfirmPressed : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving || _isProcessingPayment
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onSurfaceInverse),
                              )
                            : Text(!_chargesLoaded ? 'Loading…' : 'Confirm Booking', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(height: math.max(16.0, contentSpacing)),
                    ],
                  ),
                );
              },
            ),
          ),

          // Optional busy overlay shown while preparing popup
          if (_popupBusyOverlay)
            Positioned.fill(
              child: Material(
                color: AppColors.onSurface.withOpacity(0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.brand),
                      ),
                      const SizedBox(height: 12),
                      Text('Preparing message…', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final minutes = _selectedTotalMinutes;
    final price = _selectedTotalPrice;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.m),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Text('Total:', style: AppText.tileTitle),
          const SizedBox(width: 12),
          Text('$minutes min', style: AppText.tileSubtitle),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.okBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('₹$price', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.okFg)),
          ),
          const Spacer(),
          if (!_chargesLoaded) Text('Fetching charges…', style: AppText.hintSmall),
        ],
      ),
    );
  }

  Widget _buildImportantNotice() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppRadii.m),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8F00)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Important Notice', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  'Dates shown may become unavailable during booking. We\'ll automatically assign the next available slot and notify you of any changes.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSection({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.l),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }

  Widget _buildTestTypeOption({
    required TestType testType,
    required String title,
    required String subtitle,
    required int minutes,
    required int price,
    required IconData icon,
    required double availWidth,
  }) {
    final bool selected = _selectedTests.contains(testType);
    final small = availWidth < 360;
    final iconSize = small ? 18.0 : 20.0;
    final chipPadding = small ? 8.0 : 10.0;

    return InkWell(
      onTap: () {
        setState(() {
          if (selected) _selectedTests.remove(testType);
          else _selectedTests.add(testType);
        });
      },
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.m),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
          color: AppColors.surface,
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(chipPadding),
              decoration: BoxDecoration(
                gradient: AppGradients.brandChip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.tileTitle),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppText.tileSubtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.okBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('₹$price', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.okFg)),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, color: selected ? AppColors.primary : AppColors.divider),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    final monthLabel = DateFormat.yMMMM().format(_visibleMonth);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(monthLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(double availWidth) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final totalDays = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final startWeekday = first.weekday % 7; // Sunday=0

    const crossSpacing = 8.0;
    final effectiveWidth = availWidth - 8;
    final cellWidth = (effectiveWidth - (6 * crossSpacing)) / 7.0;
    final clampedCellWidth = cellWidth.clamp(36.0, 120.0);
    final desiredCellHeight = math.max(44.0, math.min(110.0, clampedCellWidth * 0.95));
    final childAspectRatio = clampedCellWidth / desiredCellHeight;

    final weekdayFontSize = (clampedCellWidth * 0.18).clamp(10.0, 14.0);
    final dayFontSize = (clampedCellWidth * 0.36).clamp(12.0, 20.0);
    final todayDotSize = (clampedCellWidth * 0.12).clamp(4.0, 8.0);
    final fullDotSize = (clampedCellWidth * 0.15).clamp(5.0, 10.0);

    final weekdayLabelsFull = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final weekdayLabelsShort = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final useShortWeekdays = clampedCellWidth < 44.0;
    final weekdayLabels = useShortWeekdays ? weekdayLabelsShort : weekdayLabelsFull;

    List<Widget> dayWidgets = [];
    dayWidgets.addAll(weekdayLabels
        .map((w) => Center(child: Text(w, style: AppText.hintSmall.copyWith(fontSize: weekdayFontSize))))
        .toList());

    for (int i = 0; i < startWeekday; i++) dayWidgets.add(const SizedBox());

    final now = DateTime.now();
    for (int d = 1; d <= totalDays; d++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, d);
      final isSelected = _selectedDate != null && DateUtils.isSameDay(_selectedDate!, date);
      final isToday = DateUtils.isSameDay(date, now);
      final isFull = false; // TODO: hook availability/limits from server
      dayWidgets.add(_buildCalendarDayResponsive(
        date,
        isSelected: isSelected,
        isToday: isToday,
        isFull: isFull,
        dayFontSize: dayFontSize,
        todayDotSize: todayDotSize,
        fullDotSize: fullDotSize,
        cellWidth: clampedCellWidth,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.m),
        boxShadow: AppShadows.card,
      ),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: crossSpacing,
        crossAxisSpacing: crossSpacing,
        childAspectRatio: childAspectRatio,
        children: dayWidgets,
      ),
    );
  }

  Widget _buildCalendarDayResponsive(
    DateTime date, {
    bool isSelected = false,
    bool isToday = false,
    bool isFull = false,
    required double dayFontSize,
    required double todayDotSize,
    required double fullDotSize,
    required double cellWidth,
  }) {
    final textColor = isFull ? AppColors.onSurfaceFaint : AppColors.onSurface;
    final minTouch = math.max(44.0, cellWidth + 8);
    return GestureDetector(
      onTap: isFull ? null : () => setState(() => _selectedDate = date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: minTouch,
        height: minTouch,
        padding: EdgeInsets.all((cellWidth * 0.08).clamp(4.0, 10.0)),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.s),
          border: isSelected ? Border.all(color: AppColors.primary, width: 1.4) : Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text('${date.day}', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: dayFontSize))),
            SizedBox(height: (cellWidth * 0.06).clamp(4.0, 10.0)),
            if (isToday)
              Container(width: todayDotSize, height: todayDotSize, decoration: BoxDecoration(color: AppColors.info.withOpacity(0.14), shape: BoxShape.circle)),
            if (isFull)
              Container(
                width: fullDotSize,
                height: fullDotSize,
                decoration: BoxDecoration(
                  color: AppColors.errBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.errFg, width: 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
