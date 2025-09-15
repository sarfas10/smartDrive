// booking_page.dart
// Booking page with Google Maps boarding point selector, distance-based surcharge,
// Razorpay checkout (order+verify via Hostinger PHP), and Firestore transaction
// that marks slots/{slotId}.status = "booked" only after successful booking.
// Admin can publish a one-time popup (image / video / pdf) via admin_popups collection.
// The popup is shown once per user (users/{userId}.pop_up_shown = true).
// Booking documents are NOT modified to store popup_shown (per request).

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

  // Track whether this user has already seen ANY admin popup (persisted at users/{userId}.pop_up_shown)
  bool _userPopupShown = false;

  // Whether the Acknowledge button in the popup is enabled (becomes true only after user opens/interacts with file)
  bool _acknowledgeEnabled = true;

  // Video listener to detect playback position / start
  VoidCallback? _popupVideoListener;

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    // load initial data and then admin popup + check pending popups
    _loadInitialData().whenComplete(() async {
      // fetch admin popup once initially (but we'll re-fetch right before showing)
      await _fetchActiveAdminPopup();
      await _checkPendingSuccessPopups();
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

  /// Load initial data including settings, slot, plan, boarding and user pop_up_shown flag
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

      // Load saved boarding marker (if any)
      await _loadUserBoardingPoint();

      // ── NEW: load whether user has already seen an admin popup
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
        final ud = userDoc.data();
        _userPopupShown = (ud != null && (ud['pop_up_shown'] == true));
        debugPrint('User pop_up_shown initial value: $_userPopupShown');
      } catch (e, st) {
        debugPrint('Error reading user pop_up_shown: $e\n$st');
        _userPopupShown = false;
      }

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
  double get _finalPayable => _isFreeByPlan ? 0.0 : _baseTotalCost;

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

      // After successful write, show popup (if any) and mark user-level flag
      if (bookingRef != null) {
        try {
          final found = await _fetchActiveAdminPopup();
          if (!_userPopupShown && found && _adminPopup != null) {
            final bookingData = {
              'booking_id': bookingRef.id,
              'status': 'confirmed',
              'paid_amount': 0,
            };
            await _showSuccessPopupAndMark(bookingRef, bookingData);
          } else {
            debugPrint('Skipping popup after free booking (userSeen=$_userPopupShown, found=$found).');
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

    // After the booking is successfully written, show popup and mark user flag
    if (bookingRef != null) {
      try {
        final found = await _fetchActiveAdminPopup();
        if (!_userPopupShown && found && _adminPopup != null) {
          final bookingData = {
            'booking_id': bookingRef.id,
            'status': 'paid',
            'paid_amount': _finalPayable,
            'payment': {'razorpay_payment_id': r.paymentId},
            if (_lastOrderId != null) 'razorpay_order_id': _lastOrderId,
          };
          await _showSuccessPopupAndMark(bookingRef, bookingData);
        } else {
          debugPrint('Skipping popup after paid booking (userSeen=$_userPopupShown, found=$found).');
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

      final bookingData = {
        'user_id': widget.userId,
        'slot_id': widget.slotId,
        'boarding_point_latitude': _selectedLocation!.latitude,
        'boarding_point_longitude': _selectedLocation!.longitude,
        'distance_km': _distanceKm,
        'surcharge': _surcharge,
        'vehicle_cost': _vehicleCost,
        'additional_cost': _additionalCost,
        'total_cost': _finalPayable,
        'status': status, // 'paid' or 'confirmed'
        'created_at': FieldValue.serverTimestamp(),

        // plan info
        'plan_id': _activePlanId,
        'plan_slots': _planSlots,
        'plan_slots_used': _slotsUsed,
        'free_by_plan': _isFreeByPlan,

        // payment info
        if (paymentInfo != null) 'payment': paymentInfo,
        if (_lastOrderId != null) 'razorpay_order_id': _lastOrderId,
        'paid_amount': paidAmount,

        // NOTE: booking-level popup_shown intentionally omitted (we only write user-level flag)
      };

      // Transaction to prevent double-booking
      await fs.runTransaction((tx) async {
        // 1) Check slot is not already booked
        final slotSnap = await tx.get(slotRef);
        final currentStatus = (slotSnap.data()?['status'] ?? '').toString();
        if (currentStatus.toLowerCase() == 'booked') {
          throw Exception('Slot already booked');
        }

        // 2) Create booking
        tx.set(bookingRef, bookingData);

        // 3) If free by plan, increment user's slots_used
        if (_activePlanId != null && _isFreeByPlan) {
          tx.set(userPlanRef, {'slots_used': _slotsUsed + 1}, SetOptions(merge: true));
        }

        // 4) Mark slot as booked
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
        status == 'paid' ? 'Payment successful. Booking created.' : 'Booking created successfully (FREE under your plan)!',
        color: AppColors.success,
      );

      // Return booking reference to caller (so popup can be shown/marked by caller)
      return bookingRef;
    } catch (e) {
      // If anything fails inside the transaction, no writes were committed.
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

  // -------------------- ONE-TIME SUCCESS POPUP & ADMIN MEDIA --------------------

  /// Fetch the active admin popup (one document where active == true).
  /// Returns true if an active popup was found and loaded.
  /// Tries the efficient indexed query first; on index error falls back to
  /// a client-side sort (safer while you create the index).
  Future<bool> _fetchActiveAdminPopup() async {
    final fs = FirebaseFirestore.instance;

    try {
      // Preferred, efficient query (requires composite index for active + created_at)
      final q = await fs.collection('admin_popups').where('active', isEqualTo: true).orderBy('created_at', descending: true).limit(1).get();

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
      // If the error indicates a missing index, fallback
      debugPrint('Indexed admin_popups query failed: ${e.code} ${e.message}');
      if (e.code == 'failed-precondition' || (e.message?.toLowerCase().contains('index') ?? false)) {
        try {
          debugPrint('Falling back to non-indexed fetch for admin_popups (client-side sort)');
          final q2 = await fs.collection('admin_popups').where('active', isEqualTo: true).get();
          if (q2.docs.isEmpty) {
            _adminPopup = null;
            return false;
          }

          // Find the doc with max created_at on client-side
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

            // Timestamps may be Timestamp or milliseconds, handle safely
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
        // Other firestore exception — don't swallow it silently
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
    try {
      await _popupVideoController?.dispose();
    } catch (_) {}
    _popupVideoController = VideoPlayerController.network(url);
    _initializePopupVideoFuture = _popupVideoController!.initialize();
    await _initializePopupVideoFuture;
    _popupVideoController!.setLooping(false);

    // Add a listener to update progress and detect playback start
    _removePopupVideoListener();
    _popupVideoListener = () {
      try {
        if (_popupVideoController != null) {
          final pos = _popupVideoController!.value.position;
          // Enable acknowledge after any playback > 0
          if (!_acknowledgeEnabled && pos.inMilliseconds > 0) {
            setState(() {
              _acknowledgeEnabled = true;
            });
          }
          // Update UI for progress (rebuild)
          if (mounted) setState(() {});
        }
      } catch (_) {}
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

  // Helper to format Duration as mm:ss
  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// Show the popup (await) and then mark the user (users/{userId}.pop_up_shown = true).
  /// IMPORTANT: we DO NOT write booking.popup_shown here (per request).
  Future<void> _showSuccessPopupAndMark(DocumentReference bookingRef, Map<String, dynamic> bookingData) async {
    try {
      // Show popup (await so we know when user dismissed it)
      await _showSuccessPopup(bookingData);

      // Mark user-level flag so they never see admin popups again.
      final fs = FirebaseFirestore.instance;
      final userRef = fs.collection('users').doc(widget.userId);

      if (!_userPopupShown) {
        await userRef.set({'pop_up_shown': true}, SetOptions(merge: true));
        _userPopupShown = true;
        debugPrint('Marked users.pop_up_shown = true (no booking modification).');
      } else {
        debugPrint('User already marked pop_up_shown locally; skipping user write.');
      }
    } catch (e, st) {
      // If marking fails, you could retry or log.
      debugPrint('Popup show/mark failed: $e\n$st');
      try {
        _snack('Popup error: $e', color: AppColors.warning);
      } catch (_) {}
    } finally {
      // Clean up listener if any
      _removePopupVideoListener();
    }
  }

  /// ROAD SAFETY — Non-skippable popup UI
  /// Shows only road-safety information + optional admin media. No booking/txn details, no "View Bookings".
  /// Acknowledge is disabled until user opens/interacts with the media file (pdf/image/video).
  Future<void> _showSuccessPopup(Map<String, dynamic> bookingData) async {
    if (!mounted) return Future.value();

    // If adminPopup has media (pdf/image/video), require interaction to enable acknowledge
    final mediaType = (_adminPopup != null) ? (_adminPopup!['type'] ?? '').toString().toLowerCase() : '';
    final hasMedia = mediaType == 'pdf' || mediaType == 'image' || mediaType == 'video';

    // Default: enabled unless there's a media file requiring open/play/tap
    setState(() {
      _acknowledgeEnabled = !hasMedia;
    });

    // If video, prepare controller (prepares listener to enable ack once playback starts)
    if (mediaType == 'video' && (_adminPopup!['url'] ?? '').toString().isNotEmpty) {
      try {
        await _preparePopupVideo(_adminPopup!['url']);
      } catch (e, st) {
        debugPrint('Video prepare failed: $e\n$st');
        // If video init fails, allow acknowledge to avoid blocking user forever
        setState(() => _acknowledgeEnabled = true);
      }
    }

    // Informational text: prefer admin description, fallback to a default road-safety message
    final infoText = (_adminPopup != null && (_adminPopup!['description'] ?? '').toString().isNotEmpty)
        ? (_adminPopup!['description'] ?? '').toString()
        : 'Important Road Safety Guidelines:\n\n• Please be on time at your boarding point.\n• Wear a seatbelt at all times while in the vehicle.\n• Follow instructor directions and local traffic rules.\n• Report any safety concerns to us immediately.';

    debugPrint('Preparing to show Road Safety popup (userSeen=$_userPopupShown, mediaType=$mediaType)');

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // require acknowledgement
      builder: (c) {
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
                  // Admin media (image/video/pdf) — if present show it above info text
                  if (_adminPopup != null) ...[
                    if (mediaType == 'image' && (_adminPopup!['url'] ?? '').toString().isNotEmpty) ...[
                      GestureDetector(
                        onTap: () async {
                          final url = _adminPopup!['url'].toString();
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                            // mark acknowledge enabled after user opened image externally
                            setState(() => _acknowledgeEnabled = true);
                          } else {
                            _snack('Could not open image', color: AppColors.danger);
                          }
                        },
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.s),
                            child: Image.network(
                              _adminPopup!['url'],
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1) : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (c, e, st) => Container(
                                height: 200,
                                color: AppColors.neuBg,
                                child: Center(child: Text('Could not load image', style: AppText.tileSubtitle)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (mediaType == 'video' && (_adminPopup!['url'] ?? '').toString().isNotEmpty) ...[
                      SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.s),
                          child: Container(
                            color: AppColors.neuBg,
                            child: Column(
                              children: [
                                // Video display area
                                Expanded(
                                  child: Center(
                                    child: _popupVideoController != null
                                        ? FutureBuilder(
                                            future: _initializePopupVideoFuture,
                                            builder: (context, snap) {
                                              if (snap.connectionState == ConnectionState.done) {
                                                return GestureDetector(
                                                  onTap: () {
                                                    // toggle play/pause on tap
                                                    if (_popupVideoController!.value.isPlaying) {
                                                      _popupVideoController!.pause();
                                                    } else {
                                                      _popupVideoController!.play();
                                                      // ensure acknowledge becomes enabled
                                                      setState(() => _acknowledgeEnabled = true);
                                                    }
                                                    setState(() {});
                                                  },
                                                  child: AspectRatio(
                                                    aspectRatio: _popupVideoController!.value.aspectRatio,
                                                    child: VideoPlayer(_popupVideoController!),
                                                  ),
                                                );
                                              } else {
                                                return const Center(child: CircularProgressIndicator());
                                              }
                                            },
                                          )
                                        : Center(child: Text('Video not available', style: AppText.tileSubtitle)),
                                  ),
                                ),

                                // Playback controls: play/pause + progress + time
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                                  child: Column(
                                    children: [
                                      // Slider progress (seekable)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _popupVideoController != null && _popupVideoController!.value.isInitialized
                                                ? Slider(
                                                    min: 0,
                                                    max: _popupVideoController!.value.duration.inMilliseconds.toDouble().clamp(0, double.infinity),
                                                    value: _popupVideoController!.value.position.inMilliseconds.toDouble().clamp(0, _popupVideoController!.value.duration.inMilliseconds.toDouble().clamp(0, double.infinity)),
                                                    onChanged: (v) {
                                                      if (_popupVideoController == null) return;
                                                      final pos = Duration(milliseconds: v.round());
                                                      _popupVideoController!.seekTo(pos);
                                                    },
                                                  )
                                                : LinearProgressIndicator(),
                                          ),
                                        ],
                                      ),
                                      // time labels + play/pause button
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // play/pause small button
                                          Row(
                                            children: [
                                              Material(
                                                color: AppColors.brand.withOpacity(0.95),
                                                borderRadius: BorderRadius.circular(20),
                                                child: InkWell(
                                                  onTap: () {
                                                    if (_popupVideoController == null || !_popupVideoController!.value.isInitialized) return;
                                                    if (_popupVideoController!.value.isPlaying) {
                                                      _popupVideoController!.pause();
                                                    } else {
                                                      _popupVideoController!.play();
                                                      setState(() => _acknowledgeEnabled = true);
                                                    }
                                                    setState(() {});
                                                  },
                                                  borderRadius: BorderRadius.circular(20),
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(8.0),
                                                    child: Icon(
                                                      _popupVideoController != null && _popupVideoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                                      color: AppColors.onSurfaceInverse,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _popupVideoController != null && _popupVideoController!.value.isInitialized
                                                    ? _formatDuration(_popupVideoController!.value.position)
                                                    : '00:00',
                                                style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted),
                                              ),
                                            ],
                                          ),

                                          // total duration
                                          Text(
                                            _popupVideoController != null && _popupVideoController!.value.isInitialized
                                                ? _formatDuration(_popupVideoController!.value.duration)
                                                : '00:00',
                                            style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (mediaType == 'pdf' && (_adminPopup!['url'] ?? '').toString().isNotEmpty) ...[
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppColors.neuBg,
                          borderRadius: BorderRadius.circular(AppRadii.s),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Icon(Icons.picture_as_pdf, size: 36, color: AppColors.danger),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                (_adminPopup!['description'] ?? 'Tap Open to view the PDF'),
                                style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final url = _adminPopup!['url'].toString();
                                final uri = Uri.parse(url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  // mark acknowledge enabled after user opened PDF externally
                                  setState(() => _acknowledgeEnabled = true);
                                } else {
                                  _snack('Could not open PDF', color: AppColors.danger);
                                }
                              },
                              child: Text('Open', style: AppText.tileTitle.copyWith(color: AppColors.brand)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Informational text only — concise, focused on road safety
                  Text(
                    infoText,
                    style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            actions: [
              // Single acknowledge button (non-skippable). Disabled until user opens/interacts with file when required.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                  ),
                  onPressed: _acknowledgeEnabled
                      ? () async {
                          // On acknowledge: stop video if playing and dispose controller
                          try {
                            await _popupVideoController?.pause();
                            await _popupVideoController?.dispose();
                            _popupVideoController = null;
                            _removePopupVideoListener();
                          } catch (_) {}
                          Navigator.of(context).pop();
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
      },
    );
  }

  /// On app start, check for any bookings for this user that haven't shown popup.
  /// But skip if user already saw any popup (users/{userId}.pop_up_shown == true).
  /// This version does NOT rely on booking.popup_shown; it finds the earliest paid/confirmed booking.
  Future<void> _checkPendingSuccessPopups() async {
    try {
      if (_userPopupShown) {
        debugPrint('User already saw admin popup (users/${widget.userId}.pop_up_shown == true). Skipping pending booking popups.');
        return; // user already saw a popup -> skip
      }

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
          if (!_userPopupShown && found && _adminPopup != null) {
            await _showSuccessPopupAndMark(bookingRef, {...bookingData, 'booking_id': bookingRef.id});
          } else {
            debugPrint('Not showing pending popup (userSeen=$_userPopupShown, found=$found)');
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

      // find the doc with smallest created_at (earliest)
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
        if (!_userPopupShown && found && _adminPopup != null) {
          await _showSuccessPopupAndMark(bookingRef, {...bookingData, 'booking_id': bookingRef.id});
        } else {
          debugPrint('Not showing pending popup after fallback (userSeen=$_userPopupShown, found=$found)');
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
            planSlots: _planSlots,
            slotsUsed: _slotsUsed,
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
    required this.planSlots,
    required this.slotsUsed,
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
  final int planSlots;
  final int slotsUsed;

  @override
  Widget build(BuildContext context) {
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
                    showBadge: hintVisible, // draws attention until user selects a point
                  ),
                ],
              ),

              if (showHintBubble) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    _SpeechBubble(
                      text: 'Tip: Hide the radius to select points inside the free area.',
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              if (isFreeByPlan) ...[
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
                    Text(
                      'Cost Breakdown',
                      style: AppText.tileTitle.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 12),

                    _costRow('Vehicle Cost', vehicleCost, strike: isFreeByPlan),
                    const SizedBox(height: 8),
                    _costRow('Additional Cost', additionalCost, strike: isFreeByPlan),

                    if (!isFreeByPlan) ...[
                      if (surcharge > 0) ...[
                        const SizedBox(height: 8),
                        _costRow(
                          'Distance Surcharge (${distanceKm.toStringAsFixed(2)} km)',
                          surcharge,
                          isHighlight: true,
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        _noteRow(
                          'Within free radius (${distanceKm.toStringAsFixed(2)} km, free up to ${freeRadiusKm.toStringAsFixed(1)} km)',
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 8),
                      _noteRow('Covered under your plan — no charges'),
                    ],

                    const SizedBox(height: 12),
                    Container(height: 1, color: AppColors.divider),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        ),
                        Text(
                          isFreeByPlan ? 'FREE' : '₹${totalCost.toStringAsFixed(2)}',
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.l),
                    ),
                    elevation: 2,
                  ),
                  child: isBooking
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.onSurfaceInverse),
                          ),
                        )
                      : Text(
                          isFreeByPlan ? 'Confirm Booking' : 'Proceed to Pay',
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
                        child: Text(
                          'Tap on the map to select your boarding point',
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
          child: Text(
            label,
            style: AppText.tileSubtitle.copyWith(
              color: highlightColor,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
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
          child: Text(
            text,
            style: AppText.tileSubtitle.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
