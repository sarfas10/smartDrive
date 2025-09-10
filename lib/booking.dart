// booking_page.dart
// Booking page with Google Maps boarding point selector, distance-based surcharge,
// Razorpay checkout (order+verify via Hostinger PHP), and Firestore transaction
// that marks slots/{slotId}.status = "booked" only after successful booking.
// EMI, Wallet, and Paylater are disabled in Razorpay (mobile + web fallback).

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

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadInitialData();
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
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

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

  Future<void> _loadInitialData() async {
    setState(() => _isDataLoading = true);
    try {
      // Settings
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app_settings')
          .get();

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
      final slotDoc = await FirebaseFirestore.instance
          .collection('slots')
          .doc(widget.slotId)
          .get();
      if (slotDoc.exists) _slotData = slotDoc.data()!;

      // Plan
      final userPlanDoc = await FirebaseFirestore.instance
          .collection('user_plans')
          .doc(widget.userId)
          .get();

      if (userPlanDoc.exists) {
        final up = userPlanDoc.data()!;
        _activePlanId = (up['planId'] ?? '').toString().trim().isEmpty
            ? null
            : (up['planId'] as String);

        final used = (up['slots_used'] ?? 0);
        _slotsUsed = used is num ? used.toInt() : 0;

        if (_activePlanId != null) {
          final planDoc = await FirebaseFirestore.instance
              .collection('plans')
              .doc(_activePlanId)
              .get();
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
            // NOTE: google_maps_flutter Circle has no onTap; handled via map tap.
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
            snippet:
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
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
  double get _baseTotalCost =>
      double.parse((_vehicleCost + _additionalCost + _surcharge).toStringAsFixed(2));
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
      await _createBookingAndMaybeIncrement(
        status: 'confirmed',
        paidAmount: 0,
        paymentInfo: null,
      );
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
        'wallet': false,   // hide
        'emi': false,      // hide
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
    await _createBookingAndMaybeIncrement(
      status: 'paid',
      paidAmount: _finalPayable,
      paymentInfo: {
        'razorpay_payment_id': r.paymentId,
        'razorpay_order_id': r.orderId,
        'razorpay_signature': r.signature,
      },
    );
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _snack('Payment failed${msg != null && msg.isNotEmpty ? ': $msg' : ''}', color: AppColors.danger);

    // Optional: log failed attempt
    // FirebaseFirestore.instance.collection('payment_attempts').add({
    //   'user_id': widget.userId,
    //   'slot_id': widget.slotId,
    //   'status': 'failed',
    //   'code': r.code,
    //   'message': r.message,
    //   'order_id': _lastOrderId,
    //   'created_at': FieldValue.serverTimestamp(),
    // });
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack('Using external wallet: ${r.walletName ?? ''}');
  }

  // -------------------- FIRESTORE WRITE (Transaction) --------------------

  Future<void> _createBookingAndMaybeIncrement({
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
        status == 'paid'
            ? 'Payment successful. Booking created.'
            : 'Booking created successfully (FREE under your plan)!',
        color: AppColors.success,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // If anything fails inside the transaction, no writes were committed.
      final msg = e.toString();
      if (msg.contains('already booked')) {
        _snack('Sorry, this slot was just booked by someone else.', color: AppColors.danger);
      } else {
        _snack('Error creating booking: $e', color: AppColors.danger);
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
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
                  initialCameraPosition: _officeLocation != null
                      ? CameraPosition(target: _officeLocation!, zoom: 12)
                      : _initialCameraPosition,
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
                if (_isMapLoading || _isLocationLoading)
                  const _LoadingOverlay(text: 'Initializing map & location...'),

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

  Widget _costRow(String label, double amount,
      {bool isHighlight = false, bool strike = false}) {
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
