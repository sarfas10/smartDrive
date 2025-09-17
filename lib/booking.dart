// booking_page.dart
// Booking page with Google Maps boarding point selector, distance-based surcharge,
// Razorpay checkout (order+verify via Hostinger PHP), and Firestore transaction
// that marks slots/{slotId}.status = "booked" only after successful booking.
// Admin can publish a one-time popup (image / video / pdf) via admin_popups collection.
// NOTE: This variant SHOWS the popup every time (no users/{userId}.pop_up_shown checks/writes).
// Popup changes: show circular loader until media ready, video auto-plays,
// removed video controls/progress, 10s countdown enabling Acknowledge.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show Factory, OneSequenceGestureRecognizer, EagerGestureRecognizer;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;
import 'theme/app_theme.dart';

// New imports for admin media popup
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _kAccent = AppColors.brand;

// Set via --dart-define (public key only!)
const String _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');

// 🔗 Your Hostinger PHP endpoints base (update this!)
const String _hostingerBase = 'https://tajdrivingschool.in/smartDrive/payments';

class BookingPage extends StatefulWidget {
  final String userId;
  final String slotId;

  const BookingPage({
    super.key,
    required this.userId,
    required this.slotId,
  });

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  GoogleMapController? _mapController;

  // Map layers
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  // Locations
  LatLng? _selectedLocation; // boarding point
  LatLng? _officeLocation;

  // Flags
  bool _isMapLoading = true;
  bool _isLocationLoading = false;
  bool _isDataLoading = true;
  bool _isBooking = false;

  // Distance/Cost
  double _distanceKm = 0.0;
  double _surcharge = 0.0;

  // Settings (from Firestore)
  double _freeRadiusKm = 0.0;
  double _surchargePerKm = 0.0;

  // Slot data
  Map<String, dynamic>? _slotData;

  // User plan/slots info
  String? _activePlanId;
  int _planSlots = 0;
  int _slotsUsed = 0;
  bool _isFreeByPlan = false;


  int _freeBenefitCount = 0;
  bool _isFreeByBenefit = false;

  // UI helpers
  bool _isRadiusVisible = true;
  bool _showHintBubble = false;
  Timer? _hintTimer;

  // Razorpay
  Razorpay? _razorpay;
  String? _lastOrderId; // set after server creates an order

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090), // New Delhi
    zoom: 12,
  );

  // Admin popup metadata fetched from Firestore
  Map<String, dynamic>? _adminPopup;

  // Video player controller (only used if popup type == 'video')
  VideoPlayerController? _popupVideoController;
  Future<void>? _initializePopupVideoFuture;

  // Countdown & media loaded state (outer, used for cleanup)
  bool _acknowledgeEnabled = false; // will be enabled after countdown reaches zero
  int _popupCountdownSeconds = 10;
  Timer? _popupCountdownTimer;
  bool _popupMediaLoaded = false; // show spinner until true

  // Video listener placeholder (not used for controls now)
  VoidCallback? _popupVideoListener;

  // NEW: overlay shown while popup is being prepared / until popup dialog reports it's ready
  bool _popupBusyOverlay = false;

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    // load initial data and then admin popup
    _loadInitialData().whenComplete(() async {
      // fetch admin popup once initially (we'll re-fetch right before showing)
      await _fetchActiveAdminPopup();
      // NOTE: Do NOT call _checkPendingSuccessPopups() here.
      // We only show admin popup after successful booking/payment (or on free booking).
    });
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _hintTimer?.cancel();
    _razorpay?.clear();
    _removePopupVideoListener();
    _popupVideoController?.dispose();
    _popupCountdownTimer?.cancel();
    super.dispose();
  }

  // ===== Snackbar / Logger =====
  void _snack(String message, {Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse),
        ),
        backgroundColor: color ?? AppColors.onSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // -------------------- DATA LOAD --------------------

  Future<void> _loadUserBoardingPoint() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();

      final data = userDoc.data();
      if (data == null) return;

      final b = data['boarding'];
      if (b is Map<String, dynamic>) {
        final lat = (b['latitude'] as num?)?.toDouble();
        final lng = (b['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final saved = LatLng(lat, lng);
          _addBoardingPointMarker(saved);
          if (mounted) setState(() => _isLocationLoading = false);
          if (_mapController != null) {
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: saved, zoom: 16),
              ),
            );
          }
        }
      }
    } catch (e) {
      _snack('Could not load saved boarding point: $e', color: AppColors.danger);
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  /// Load initial data including settings, slot, plan, boarding
  Future<void> _loadInitialData() async {
    setState(() => _isDataLoading = true);
    try {
      // Settings
      final settingsDoc = await FirebaseFirestore.instance.collection('settings').doc('app_settings').get();

      if (settingsDoc.exists) {
        final s = settingsDoc.data()!;
        final lat = (s['latitude'] as num?)?.toDouble();
        final lng = (s['longitude'] as num?)?.toDouble();
        _officeLocation = LatLng(lat ?? 28.6139, lng ?? 77.2090);

        _freeRadiusKm = (s['free_radius_km'] as num?)?.toDouble() ?? 0.0;
        _surchargePerKm = (s['surcharge_per_km'] as num?)?.toDouble() ?? 0.0;
        _refreshRadiusOverlay();
      }

      // Slot
      final slotDoc = await FirebaseFirestore.instance.collection('slots').doc(widget.slotId).get();
      if (slotDoc.exists) _slotData = slotDoc.data()!;

      // Plan
      final userPlanDoc = await FirebaseFirestore.instance.collection('user_plans').doc(widget.userId).get();

      if (userPlanDoc.exists) {
        final up = userPlanDoc.data()!;
        _activePlanId = (up['planId'] ?? '').toString().trim().isEmpty ? null : (up['planId'] as String);

        final used = (up['slots_used'] ?? 0);
        _slotsUsed = used is num ? used.toInt() : 0;

        if (_activePlanId != null) {
          final planDoc = await FirebaseFirestore.instance.collection('plans').doc(_activePlanId).get();
          if (planDoc.exists) {
            final pd = planDoc.data()!;
            final slots = (pd['slots'] ?? 0);
            _planSlots = slots is num ? slots.toInt() : 0;
          }
        }
      } else {
        _activePlanId = null;
        _planSlots = 0;
        _slotsUsed = 0;
      }

      _isFreeByPlan = (_planSlots != 0) && (_slotsUsed < _planSlots);

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (userDoc.exists) {
        final u = userDoc.data()!;
        _freeBenefitCount = (u['free_benefit'] ?? 0) is num ? (u['free_benefit'] as num).toInt() : 0;
        _isFreeByBenefit = _freeBenefitCount > 0;
      }

      // Load saved boarding marker (if any)
      await _loadUserBoardingPoint();

      setState(() => _isDataLoading = false);
    } catch (e) {
      setState(() => _isDataLoading = false);
      _snack('Error loading data: $e', color: AppColors.danger);
    }
  }

  // -------------------- MAP HELPERS --------------------

  void _refreshRadiusOverlay() {
    if (_officeLocation == null) return;
    setState(() {
      _circles.clear();
      if (_isRadiusVisible && _freeRadiusKm > 0) {
        _circles.add(
          Circle(
            circleId: const CircleId('free_radius'),
            center: _officeLocation!,
            radius: _freeRadiusKm * 1000,
            fillColor: AppColors.brand.withOpacity(0.08),
            strokeColor: AppColors.brand.withOpacity(0.4),
            strokeWidth: 2,
            consumeTapEvents: true,
          ),
        );
      }
    });
  }

  void _toggleRadiusVisibility() {
    setState(() {
      _isRadiusVisible = !_isRadiusVisible;
      _showHintBubble = false;
    });
    _hintTimer?.cancel();
    _refreshRadiusOverlay();
  }

  bool _isInsideFreeRadius(LatLng p) {
    if (_officeLocation == null || _freeRadiusKm <= 0) return false;
    final meters = Geolocator.distanceBetween(
      _officeLocation!.latitude,
      _officeLocation!.longitude,
      p.latitude,
      p.longitude,
    );
    return meters <= _freeRadiusKm * 1000.0;
  }

  void _showBubbleHint() {
    _hintTimer?.cancel();
    setState(() => _showHintBubble = true);
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHintBubble = false);
    });
  }

  void _calculateHaversineDistance() {
    if (_selectedLocation == null || _officeLocation == null) return;
    final meters = Geolocator.distanceBetween(
      _officeLocation!.latitude,
      _officeLocation!.longitude,
      _selectedLocation!.latitude,
      _selectedLocation!.longitude,
    );
    final km = meters / 1000.0;
    setState(() {
      _distanceKm = km;
      _surcharge = _computeSurcharge(km);
    });
  }

  double _computeSurcharge(double km) {
    if (km <= _freeRadiusKm) return 0.0;
    final extraKm = km - _freeRadiusKm;
    return double.parse((extraKm * _surchargePerKm).toStringAsFixed(2));
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() => _isMapLoading = false);
    _addOfficeMarker();
    Future.delayed(const Duration(milliseconds: 300), _refreshRadiusOverlay);

    if (_selectedLocation != null) {
      _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _selectedLocation!, zoom: 16),
        ),
      );
      if (mounted) setState(() => _isLocationLoading = false);
      _calculateHaversineDistance();
    } else {
      _goToCurrentLocation();
    }
  }

  void _addOfficeMarker() {
    if (_officeLocation == null) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'office_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('office_location'),
          position: _officeLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Office',
            snippet: 'Driving School Office',
          ),
        ),
      );
    });
  }

  void _addBoardingPointMarker(LatLng position) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'boarding_point');
      _markers.add(
        Marker(
          markerId: const MarkerId('boarding_point'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Boarding Point',
            snippet: '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
          consumeTapEvents: false,
        ),
      );
      _selectedLocation = position;
    });
    _calculateHaversineDistance();
  }

  void _onMapTap(LatLng position) {
    if (_isRadiusVisible && _isInsideFreeRadius(position)) {
      _showBubbleHint();
      _snack(
        'Tip: Hide the free-radius overlay for easier selection inside it.',
        color: AppColors.warning,
      );
    }
    _addBoardingPointMarker(position);
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLocationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('Location services are disabled.');
        setState(() => _isLocationLoading = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLocationLoading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLocationLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      final current = LatLng(position.latitude, position.longitude);

      if (_selectedLocation == null) {
        _addBoardingPointMarker(current);
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: current, zoom: 16),
          ),
        );
      } else {
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _selectedLocation!, zoom: 16),
          ),
        );
      }
    } catch (e) {
      _snack('Error getting location: $e', color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  void _clearBoardingPoint() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'boarding_point');
      _selectedLocation = null;
      _distanceKm = 0.0;
      _surcharge = 0.0;
    });
  }

  double _numToDouble(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  double get _vehicleCost => _numToDouble(_slotData?['vehicle_cost']);
  double get _additionalCost => _numToDouble(_slotData?['additional_cost']);
  double get _baseTotalCost => double.parse((_vehicleCost + _additionalCost + _surcharge).toStringAsFixed(2));
  double get _finalPayable {
  if (_isFreeByBenefit) return 0.0; // free benefit
  if (_isFreeByPlan) return 0.0;    // plan-based free
  return _baseTotalCost;
}


  // -------------------- SERVER HELPERS --------------------

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid JSON from server');
    }
    return data;
  }

  Future<String> _createOrderOnServer({required int amountPaise}) async {
    final res = await _postJson(
      '$_hostingerBase/createOrder.php',
      {
        'amountPaise': amountPaise,
        'receipt': 'slot_${widget.slotId}_${DateTime.now().millisecondsSinceEpoch}',
        'notes': {
          'slotId': widget.slotId,
          'userId': widget.userId,
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

  // -------------------- PAYMENT FLOW --------------------

  Future<void> _proceedToPay() async {
    if (_selectedLocation == null) {
      _snack('Please select a boarding point', color: AppColors.warning);
      return;
    }

    // Free under plan → create booking immediately and increment slots_used
    if (_finalPayable <= 0.0) {
      final bookingRef = await _createBookingAndMaybeIncrement(
        status: 'confirmed',
        paidAmount: 0,
        paymentInfo: null,
      );

      // After successful write, show popup (if any)
      if (bookingRef != null) {
        try {
          final found = await _fetchActiveAdminPopup();
          if (found && _adminPopup != null) {
            final bookingData = {
              'booking_id': bookingRef.id,
              'status': 'confirmed',
              'paid_amount': 0,
            };
            await _showSuccessPopup(bookingData);
          } else {
            debugPrint('No admin popup to show after free booking (found=$found).');
          }
        } catch (e, st) {
          debugPrint('Popup after free booking failed: $e\n$st');
        }
        if (mounted) Navigator.of(context).pop();
      }
      return;
    }

    // Paid → create order on server, then open Razorpay
    try {
      final amountPaise = (_finalPayable * 100).round();
      _snack('Preparing payment…');
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise);
      _openRazorpayCheckout(orderId: _lastOrderId!, amountPaise: amountPaise);
    } catch (e) {
      _snack('Could not start payment: $e', color: AppColors.danger);
    }
  }

  void _openRazorpayCheckout({required String orderId, required int amountPaise}) {
    if (_razorpay == null) {
      _snack('Payment is unavailable right now. Please try again.', color: AppColors.danger);
      return;
    }
    if (_razorpayKeyId.isEmpty) {
      _snack('Razorpay key missing. Pass --dart-define=RAZORPAY_KEY_ID=your_key', color: AppColors.danger);
      return;
    }

    final options = {
      'key': _razorpayKeyId,
      'order_id': orderId, // IMPORTANT: server-created order
      'amount': amountPaise, // paise
      'currency': 'INR',

      // optional branding
      'name': '',
      'description': '',
      'image': '',
      'prefill': {'contact': '', 'email': '', 'name': ''},
      'theme': {'color': '#FFFFFF'},

      // ✅ Native SDK toggles (Android/iOS)
      'method': {
        'card': true,
        'upi': true,
        'netbanking': true,
        'wallet': false, // hide
        'emi': false, // hide
        'paylater': false, // hide
      },

      // 🌐 Web fallback (if using web checkout anywhere)
      'config': {
        'display': {
          'hide': [
            {'method': 'emi'},
            {'method': 'wallet'},
            {'method': 'paylater'},
          ],
        }
      },

      'timeout': 300,
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      _snack('Unable to open payment: $e', color: AppColors.danger);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    // Guard: we must have created an order
    if (r.orderId == null || r.paymentId == null || r.signature == null) {
      _snack('Payment success response incomplete', color: AppColors.danger);
      return;
    }

    final amountPaise = (_finalPayable * 100).round();

    // Show an immediate snackbar so user sees payment returned from Razorpay
    _snack('Payment completed — verifying…', color: AppColors.info);

    // Verify with server before writing booking
    bool valid = false;
    try {
      valid = await _verifyPaymentOnServer(
        razorpayOrderId: r.orderId!,
        razorpayPaymentId: r.paymentId!,
        razorpaySignature: r.signature!,
        expectedAmountPaise: amountPaise,
      );
    } catch (e) {
      _snack('Verification error: $e', color: AppColors.danger);
      return;
    }

    if (!valid) {
      _snack('Payment verification failed. Please contact support.', color: AppColors.danger);
      return;
    }

    // Verified → write booking as paid
    final bookingRef = await _createBookingAndMaybeIncrement(
      status: 'paid',
      paidAmount: _finalPayable,
      paymentInfo: {
        'razorpay_payment_id': r.paymentId,
        'razorpay_order_id': r.orderId,
        'razorpay_signature': r.signature,
      },
    );

    // After the booking is successfully written, show popup
    if (bookingRef != null) {
      try {
        final found = await _fetchActiveAdminPopup();
        if (found && _adminPopup != null) {
          final bookingData = {
            'booking_id': bookingRef.id,
            'status': 'paid',
            'paid_amount': _finalPayable,
            'payment': {'razorpay_payment_id': r.paymentId},
            if (_lastOrderId != null) 'razorpay_order_id': _lastOrderId,
          };
          // Show popup only after payment verification + booking write succeeded
          await _showSuccessPopup(bookingData);
        } else {
          debugPrint('No admin popup to show after paid booking (found=$found).');
        }
      } catch (e, st) {
        debugPrint('Popup show failed after payment: $e\n$st');
      }

      if (mounted) Navigator.of(context).pop();
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _snack('Payment failed${msg != null && msg.isNotEmpty ? ': $msg' : ''}', color: AppColors.danger);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack('Using external wallet: ${r.walletName ?? ''}');
  }

  // -------------------- FIRESTORE WRITE (Transaction) --------------------

  /// Creates the booking inside a transaction and returns the booking DocumentReference on success.
  /// Returns null on failure. (This function no longer shows the admin popup; caller will.)
  Future<DocumentReference?> _createBookingAndMaybeIncrement({
  required String status,
  required num paidAmount,
  Map<String, dynamic>? paymentInfo,
}) async {
  setState(() => _isBooking = true);
  try {
    final fs = FirebaseFirestore.instance;

    final bookingRef = fs.collection('bookings').doc();
    final userPlanRef = fs.collection('user_plans').doc(widget.userId);
    final slotRef = fs.collection('slots').doc(widget.slotId);
    final userRef = fs.collection('users').doc(widget.userId);

    // Base booking payload; some fields are added inside the transaction after we decide free path
    final baseBookingData = {
      'user_id': widget.userId,
      'slot_id': widget.slotId,
      'boarding_point_latitude': _selectedLocation!.latitude,
      'boarding_point_longitude': _selectedLocation!.longitude,
      'distance_km': _distanceKm,
      'surcharge': _surcharge,
      'vehicle_cost': _vehicleCost,
      'additional_cost': _additionalCost,
      'total_cost': _finalPayable,
      'status': status,
      'created_at': FieldValue.serverTimestamp(),
      if (_slotData != null && _slotData!['slot_day'] != null) 'slot_day': _slotData!['slot_day'],
      if (_slotData != null && _slotData!['slot_time'] != null) 'slot_time': _slotData!['slot_time'],
      if (_slotData != null && _slotData!['vehicle_type'] != null) 'vehicle_type': _slotData!['vehicle_type'],
      if (_slotData != null && _slotData!['instructor_name'] != null) 'instructor_name': _slotData!['instructor_name'],
      'plan_id': _activePlanId,
      'plan_slots': _planSlots,
      'plan_slots_used': _slotsUsed,
      if (paymentInfo != null) 'payment': paymentInfo,
      if (_lastOrderId != null) 'razorpay_order_id': _lastOrderId,
      'paid_amount': paidAmount,
    };

    await fs.runTransaction((tx) async {
      // 1) Ensure slot is still free
      final slotSnap = await tx.get(slotRef);
      final currentStatus = (slotSnap.data()?['status'] ?? '').toString().toLowerCase();
      if (currentStatus == 'booked') {
        throw Exception('Slot already booked');
      }

      // 2) Read user's current benefit count INSIDE the txn to avoid races
      final userSnap = await tx.get(userRef);
      int freeBenefit = 0;
      if (userSnap.exists) {
        final raw = userSnap.data()?['free_benefit'];
        freeBenefit = (raw is num) ? raw.toInt() : 0;
      }

      // Decide free path atomically (benefit has priority, then plan)
      final bool useBenefit = freeBenefit > 0;
      final bool usePlan = !useBenefit && _activePlanId != null && _planSlots != 0 && _slotsUsed < _planSlots;

      final bookingPayload = Map<String, dynamic>.from(baseBookingData)
        ..addAll({
          'free_by_benefit': useBenefit,
          'free_by_plan': usePlan,
        });

      // If it’s free by either route, make sure total_cost reflects FREE (= 0.0)
      if (useBenefit || usePlan) {
        bookingPayload['total_cost'] = 0.0;
        bookingPayload['paid_amount'] = 0;
      }

      // 3) Write booking
      tx.set(bookingRef, bookingPayload);

      // 4) Update counters
      if (useBenefit) {
        tx.update(userRef, {'free_benefit': FieldValue.increment(-1)});
      } else if (usePlan) {
        tx.set(userPlanRef, {'slots_used': _slotsUsed + 1}, SetOptions(merge: true));
      }

      // 5) Mark slot as booked
      tx.set(
        slotRef,
        {
          'status': 'booked',
          'booked_by': widget.userId,
          'booking_id': bookingRef.id,
          'booked_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    _snack(
      status == 'paid'
          ? 'Payment successful. Booking created.'
          : 'Booking created successfully (FREE)!',
      color: AppColors.success,
    );

    return bookingRef;
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('already booked')) {
      _snack('Sorry, this slot was just booked by someone else.', color: AppColors.danger);
    } else {
      _snack('Error creating booking: $e', color: AppColors.danger);
    }
    return null;
  } finally {
    if (mounted) setState(() => _isBooking = false);
  }
}


  // -------------------- POPUP MEDIA HELPERS --------------------

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

  // -------------------- COUNTDOWN --------------------

  void _startPopupCountdown({int seconds = 10}) {
    _popupCountdownTimer?.cancel();
    setState(() {
      _popupCountdownSeconds = seconds;
      _acknowledgeEnabled = false;
    });

    _popupCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_popupCountdownSeconds > 0) {
          _popupCountdownSeconds -= 1;
        }
        if (_popupCountdownSeconds <= 0) {
          _acknowledgeEnabled = true;
          _popupCountdownTimer?.cancel();
        }
      });
    });
  }

  void _stopPopupCountdown() {
    _popupCountdownTimer?.cancel();
    _popupCountdownTimer = null;
  }

  // -------------------- POPUP UI --------------------

  Future<void> _showSuccessPopup(Map<String, dynamic> bookingData) async {
    if (!mounted) return Future.value();

    // Show busy overlay while we prepare the popup
    setState(() {
      _popupBusyOverlay = true;
    });

    // Reset outer helpers
    _popupCountdownTimer?.cancel();
    _popupMediaLoaded = false;
    _acknowledgeEnabled = false;
    _popupCountdownSeconds = 10;

    final mediaType = (_adminPopup != null) ? (_adminPopup!['type'] ?? '').toString().toLowerCase() : '';
    final url = (_adminPopup != null) ? (_adminPopup!['url'] ?? '').toString() : '';
    final hasMedia = mediaType == 'image' || mediaType == 'video' || mediaType == 'pdf';

    // If video, prepare controller ahead of showing the dialog (so we can show quickly)
    if (mediaType == 'video' && url.isNotEmpty) {
      try {
        await _preparePopupVideo(url);
        // Note: dialog manages its own mediaLoaded local state
      } catch (e, st) {
        debugPrint('Video prepare/init error before dialog: $e\n$st');
        // continue — dialog will handle fallback
      }
    }

    // Callback that inner dialog can call when it's ready to be visible (media loaded/countdown started).
    void Function()? onMediaReady;

    final infoText = (_adminPopup != null && (_adminPopup!['description'] ?? '').toString().isNotEmpty)
        ? (_adminPopup!['description'] ?? '').toString()
        : 'Important Road Safety Guidelines:\n\n• Please be on time at your boarding point.\n• Wear a seatbelt at all times while in the vehicle.\n• Follow instructor directions and local traffic rules.\n• Report any safety concerns to us immediately.';

    // when dialog reports media ready, hide the outer blocking overlay
    onMediaReady = () {
      if (!mounted) return;
      setState(() {
        _popupBusyOverlay = false;
      });
    };

    // Show dialog and manage countdown / media-loaded inside it
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        // dialog-local state
        bool mediaLoaded = false;
        int countdown = 10;
        Timer? localTimer;

        // helper to start the countdown inside the dialog
        void startLocalCountdown([int seconds = 10, StateSetter? sb]) {
          localTimer?.cancel();
          countdown = seconds;
          // mark loaded
          final wasNotLoaded = !mediaLoaded;
          mediaLoaded = true;
          sb?.call(() {}); // refresh immediately so spinner hides and text updates

          // notify outer that the dialog is ready to be shown (so the outer busy overlay can hide)
          if (wasNotLoaded) {
            // small microtask to ensure setState ordering doesn't conflict
            Future.microtask(() {
              onMediaReady?.call();
            });
          }

          localTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) return;
            if (countdown <= 0) {
              localTimer?.cancel();
              sb?.call(() {});
              return;
            }
            countdown -= 1;
            sb?.call(() {});
          });
        }

        return StatefulBuilder(builder: (BuildContext dialogContext, StateSetter setDialogState) {
          // If media is video and controller is initialized and we haven't marked mediaLoaded yet,
          // mark loaded and start countdown.
          if (!mediaLoaded && mediaType == 'video' && _popupVideoController != null && _popupVideoController!.value.isInitialized) {
            // Start countdown immediately when video is ready (and playing)
            startLocalCountdown(10, setDialogState);
          }

          // For PDF, mark loaded immediately (we don't block)
          if (!mediaLoaded && mediaType == 'pdf' && url.isNotEmpty) {
            startLocalCountdown(10, setDialogState);
          }

          // Dialog widget
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
                                // Image handling: use loadingBuilder to trigger startLocalCountdown when loaded
                                if (mediaType == 'image' && url.isNotEmpty)
                                  Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) {
                                        // image loaded -> start countdown if not started
                                        if (!mediaLoaded) {
                                          startLocalCountdown(10, setDialogState);
                                        }
                                        return child;
                                      }
                                      return const SizedBox.shrink();
                                    },
                                    errorBuilder: (c, e, st) {
                                      // image failed -> allow countdown to start so user isn't blocked
                                      if (!mediaLoaded) startLocalCountdown(10, setDialogState);
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
                                if (!mediaLoaded)
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
                            mediaLoaded ? (countdown <= 0 ? 'You may now acknowledge.' : 'Please wait ${countdown}s to acknowledge.') : 'Loading…',
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
                    onPressed: (mediaLoaded && countdown <= 0)
                        ? () async {
                            // cleanup local timer & dialog video listener
                            localTimer?.cancel();
                            // stop & dispose outer video controller if present
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
        _popupMediaLoaded = false;
        _acknowledgeEnabled = false;
        _popupCountdownSeconds = 10;
      });
    }
  }

  /// On app start, check for any bookings for this user that haven't shown popup.
  /// This version does NOT rely on any users/{userId}.pop_up_shown flag and will
  /// show the popup for the earliest paid/confirmed booking if an admin popup exists.
  /// NOTE: This function is intentionally NOT called in initState() in the current variant.
  Future<void> _checkPendingSuccessPopups() async {
    try {
      final fs = FirebaseFirestore.instance;

      // Try the indexed query first
      try {
        final q = await fs
            .collection('bookings')
            .where('user_id', isEqualTo: widget.userId)
            .where('status', whereIn: ['paid', 'confirmed'])
            .orderBy('created_at', descending: false)
            .limit(1)
            .get();

        if (q.docs.isNotEmpty) {
          final doc = q.docs.first;
          final bookingRef = doc.reference;
          final bookingDataRaw = doc.data();
          final bookingData = bookingDataRaw is Map<String, dynamic> ? Map<String, dynamic>.from(bookingDataRaw) : <String, dynamic>{};

          // Re-fetch admin popup right before showing
          final found = await _fetchActiveAdminPopup();
          if (found && _adminPopup != null) {
            await _showSuccessPopup({...bookingData, 'booking_id': bookingRef.id});
          } else {
            debugPrint('Not showing pending popup (found=$found)');
          }
        }
        return;
      } on FirebaseException catch (e) {
        if (!(e.code == 'failed-precondition' || (e.message?.toLowerCase().contains('index') ?? false))) {
          rethrow; // unknown firestore error, rethrow
        }
        debugPrint('Indexed bookings query failed, falling back: ${e.message}');
      }

      // Fallback: fetch all bookings for this user (paid/confirmed) and pick the earliest one
      final q2 = await fs.collection('bookings').where('user_id', isEqualTo: widget.userId).where('status', whereIn: ['paid', 'confirmed']).get();

      if (q2.docs.isEmpty) {
        debugPrint('No pending bookings found (fallback).');
        return;
      }

      QueryDocumentSnapshot? best;
      int _tsToMillis(dynamic t) {
        if (t == null) return 0;
        if (t is Timestamp) return t.millisecondsSinceEpoch;
        if (t is int) return t;
        if (t is double) return t.toInt();
        return int.tryParse(t.toString()) ?? 0;
      }

      for (final d in q2.docs) {
        if (best == null) {
          best = d;
          continue;
        }
        final a = d.data() as Map<String, dynamic>;
        final b = best.data() as Map<String, dynamic>;
        if (_tsToMillis(a['created_at']) < _tsToMillis(b['created_at'])) best = d;
      }

      if (best != null) {
        final bookingRef = best.reference;
        final bookingDataRaw = best.data();
        final bookingData = bookingDataRaw is Map<String, dynamic> ? Map<String, dynamic>.from(bookingDataRaw) : <String, dynamic>{};

        final found = await _fetchActiveAdminPopup();
        if (found && _adminPopup != null) {
          await _showSuccessPopup({...bookingData, 'booking_id': bookingRef.id});
        } else {
          debugPrint('Not showing pending popup after fallback (found=$found)');
        }
      }
    } catch (e, st) {
      debugPrint('checkPendingSuccessPopups error: $e\n$st');
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    if (_isDataLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.brand)));
    }
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _officeLocation != null ? CameraPosition(target: _officeLocation!, zoom: 12) : _initialCameraPosition,
                  mapType: MapType.normal,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  minMaxZoomPreference: const MinMaxZoomPreference(2.0, 20.0),
                  markers: _markers,
                  circles: _circles,
                  onMapCreated: _onMapCreated,
                  onTap: _onMapTap,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                ),
                if (_isMapLoading || _isLocationLoading) const _LoadingOverlay(text: 'Initializing map & location...'),

                // FULLSCREEN overlay shown while popup is being prepared/loaded
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

                // Zoom controls
                Positioned(
                  right: 16,
                  bottom: 140,
                  child: _RoundedButtonsColumn(
                    children: [
                      IconButton(
                        onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                        icon: const Icon(Icons.add),
                        tooltip: 'Zoom In',
                        color: AppColors.onSurface,
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                        icon: const Icon(Icons.remove),
                        tooltip: 'Zoom Out',
                        color: AppColors.onSurface,
                      ),
                    ],
                  ),
                ),

                // Clear boarding point
                Positioned(
                  right: 16,
                  bottom: 76,
                  child: _RoundedButtonsColumn(
                    children: [
                      IconButton(
                        onPressed: _clearBoardingPoint,
                        icon: const Icon(Icons.clear),
                        color: AppColors.danger,
                        tooltip: 'Clear Boarding Point',
                      ),
                    ],
                  ),
                ),

                // Go to Office
                Positioned(
                  left: 16,
                  bottom: 140,
                  child: _RoundedButtonsColumn(
                    children: [
                      IconButton(
                        onPressed: () async {
                          if (_officeLocation != null) {
                            await _mapController?.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(target: _officeLocation!, zoom: 16),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.apartment),
                        color: AppColors.brand,
                        tooltip: 'Go to Office',
                      ),
                    ],
                  ),
                ),

                // Current location
                Positioned(
                  left: 16,
                  bottom: 76,
                  child: _RoundedButtonsColumn(
                    children: [
                      IconButton(
                        onPressed: _goToCurrentLocation,
                        icon: const Icon(Icons.my_location),
                        color: AppColors.info,
                        tooltip: 'Use Current Location',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

         _SummarySheet(
  slotData: _slotData,
  vehicleCost: _vehicleCost,
  additionalCost: _additionalCost,
  surcharge: _surcharge,
  distanceKm: _distanceKm,
  totalCost: _finalPayable,
  freeRadiusKm: _freeRadiusKm,
  isBooking: _isBooking,
  onProceed: _proceedToPay,
  hintVisible: _selectedLocation == null,
  isRadiusVisible: _isRadiusVisible,
  onToggleRadius: _toggleRadiusVisibility,
  showHintBubble: _showHintBubble,
  isFreeByPlan: _isFreeByPlan,
  isFreeByBenefit: _isFreeByBenefit,       // NEW
  planSlots: _planSlots,
  slotsUsed: _slotsUsed,
  freeBenefitCount: _freeBenefitCount,      // NEW
),

        ],
      ),
    );
  }
}

// -------------------- Small UI helpers --------------------

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.onSurface.withOpacity(0.30),
      child: Center(
        child: Material(
          color: AppColors.surface,
          elevation: 6,
          borderRadius: BorderRadius.circular(AppRadii.l),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.brand),
                ),
                const SizedBox(width: 14),
                Text(
                  text,
                  style: AppText.tileTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ... (rest of small UI helpers unchanged: _RoundedButtonsColumn, _RadiusToggleButton, _SpeechBubble, _TrianglePointer, _SummarySheet, helpers)

class _RoundedButtonsColumn extends StatelessWidget {
  const _RoundedButtonsColumn({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(AppRadii.s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _RadiusToggleButton extends StatelessWidget {
  const _RadiusToggleButton({
    super.key,
    required this.isVisible,
    required this.onPressed,
    this.showBadge = false,
  });

  final bool isVisible;
  final VoidCallback onPressed;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.brand,
          elevation: 3,
          borderRadius: BorderRadius.circular(AppRadii.s),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadii.s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVisible ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: AppColors.onSurfaceInverse,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVisible ? 'Hide Radius' : 'Show Radius',
                    style: AppText.hintSmall.copyWith(
                      color: AppColors.onSurfaceInverse,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    super.key,
    required this.text,
    this.background = AppColors.warnBg,
    this.textColor = AppColors.warnFg,
  });

  final String text;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              text,
              style: AppText.tileSubtitle.copyWith(color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            right: -6,
            top: 16,
            child: _TrianglePointer(color: background),
          ),
        ],
      ),
    );
  }
}

class _TrianglePointer extends StatelessWidget {
  const _TrianglePointer({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45 degrees
      child: Container(
        width: 12,
        height: 12,
        color: color,
      ),
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({
    required this.slotData,
    required this.vehicleCost,
    required this.additionalCost,
    required this.surcharge,
    required this.distanceKm,
    required this.totalCost,
    required this.freeRadiusKm,
    required this.isBooking,
    required this.onProceed,
    required this.hintVisible,
    required this.isRadiusVisible,
    required this.onToggleRadius,
    required this.showHintBubble,
    required this.isFreeByPlan,
    required this.isFreeByBenefit,   // NEW
    required this.planSlots,
    required this.slotsUsed,
    required this.freeBenefitCount,  // NEW
  });

  final Map<String, dynamic>? slotData;
  final double vehicleCost;
  final double additionalCost;
  final double surcharge;
  final double distanceKm;
  final double totalCost;
  final double freeRadiusKm;
  final bool isBooking;
  final VoidCallback onProceed;
  final bool hintVisible;
  final bool isRadiusVisible;
  final VoidCallback onToggleRadius;
  final bool showHintBubble;

  final bool isFreeByPlan;
  final bool isFreeByBenefit;    // NEW
  final int planSlots;
  final int slotsUsed;
  final int freeBenefitCount;    // NEW

  @override
  Widget build(BuildContext context) {
    final bool isFree = isFreeByPlan || isFreeByBenefit;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and radius toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Booking Summary',
                    style: AppText.sectionTitle.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  _RadiusToggleButton(
                    isVisible: isRadiusVisible,
                    onPressed: onToggleRadius,
                    showBadge: hintVisible,
                  ),
                ],
              ),

              if (showHintBubble) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    _SpeechBubble(text: 'Tip: Hide the radius to select points inside the free area.'),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Free banners
              if (isFreeByBenefit) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.okBg,
                    borderRadius: BorderRadius.circular(AppRadii.s),
                    border: Border.all(color: AppColors.okBg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 16, color: AppColors.okFg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This session will be FREE using your benefit. Remaining after this: ${freeBenefitCount - 1}',
                          style: AppText.tileSubtitle.copyWith(color: AppColors.okFg, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (isFreeByPlan) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.okBg,
                    borderRadius: BorderRadius.circular(AppRadii.s),
                    border: Border.all(color: AppColors.okBg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.card_membership, size: 16, color: AppColors.okFg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free under your plan: ${planSlots - slotsUsed} of $planSlots slots remaining after this booking.',
                          style: AppText.tileSubtitle.copyWith(color: AppColors.okFg, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Cost card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.neuBg,
                  borderRadius: BorderRadius.circular(AppRadii.l),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cost Breakdown', style: AppText.tileTitle.copyWith(color: AppColors.onSurface)),
                    const SizedBox(height: 12),

                    _costRow('Vehicle Cost', vehicleCost, strike: isFree),
                    const SizedBox(height: 8),
                    _costRow('Additional Cost', additionalCost, strike: isFree),

                    if (!isFree) ...[
                      if (surcharge > 0) ...[
                        const SizedBox(height: 8),
                        _costRow('Distance Surcharge (${distanceKm.toStringAsFixed(2)} km)', surcharge, isHighlight: true),
                      ] else ...[
                        const SizedBox(height: 8),
                        _noteRow('Within free radius (${distanceKm.toStringAsFixed(2)} km, free up to ${freeRadiusKm.toStringAsFixed(1)} km)'),
                      ],
                    ] else ...[
                      const SizedBox(height: 8),
                      _noteRow(isFreeByBenefit ? 'Covered by your free benefit — no charges'
                                               : 'Covered under your plan — no charges'),
                    ],

                    const SizedBox(height: 12),
                    Container(height: 1, color: AppColors.divider),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Amount',
                          style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        ),
                        Text(
                          isFree ? 'FREE' : '₹${totalCost.toStringAsFixed(2)}',
                          style: AppText.tileTitle.copyWith(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.success),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isBooking ? null : onProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onSurfaceInverse,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
                    elevation: 2,
                  ),
                  child: isBooking
                      ? SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.onSurfaceInverse)),
                        )
                      : Text(
                          isFree ? 'Confirm Booking' : 'Proceed to Pay',
                          style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse, fontSize: 16),
                        ),
                ),
              ),

              if (hintVisible) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warnBg,
                    borderRadius: BorderRadius.circular(AppRadii.s),
                    border: Border.all(color: AppColors.warnBg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.warnFg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Tap on the map to select your boarding point',
                          style: AppText.tileSubtitle.copyWith(color: AppColors.warnFg, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _costRow(String label, double amount, {bool isHighlight = false, bool strike = false}) {
    final valueText = '₹${amount.toStringAsFixed(2)}';
    final highlightColor = isHighlight ? AppColors.warning : AppColors.onSurfaceMuted;
    final valueColor = isHighlight ? AppColors.warning : AppColors.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label, style: AppText.tileSubtitle.copyWith(color: highlightColor, fontWeight: FontWeight.w500, fontSize: 14)),
        ),
        Text(
          valueText,
          style: AppText.tileTitle.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor,
            decoration: strike ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: AppColors.danger,
            decorationThickness: 2,
          ),
        ),
      ],
    );
  }

  Widget _noteRow(String text) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: AppColors.success),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: AppText.tileSubtitle.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

