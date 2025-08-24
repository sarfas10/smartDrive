
// booking_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show Factory, OneSequenceGestureRecognizer, EagerGestureRecognizer;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Accent color for Hide Radius button and bubble
const Color _kAccent = Color(0xFF4C63D2);

class BookingPage extends StatefulWidget {
  final String userId;
  final String slotId;

  const BookingPage({
    Key? key,
    required this.userId,
    required this.slotId,
  }) : super(key: key);

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  GoogleMapController? _mapController;

  // Map layers
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  // Locations
  LatLng? _selectedLocation;
  LatLng? _officeLocation;

  // Loading flags
  bool _isMapLoading = true;
  bool _isLocationLoading = true;
  bool _isDataLoading = true;
  bool _isBooking = false;

  // Distance/Cost
  double _distanceKm = 0.0;
  double _surcharge = 0.0;

  // Settings (from Firestore)
  double _freeRadiusKm = 0.0;
  double _surchargePerKm = 0.0;

  // Slot data (kept for later save)
  Map<String, dynamic>? _slotData;

  // Free-radius visibility + hint bubble
  bool _isRadiusVisible = true;
  bool _showHintBubble = false;
  Timer? _hintTimer;

  // Default camera
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090), // New Delhi
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isDataLoading = true);
    try {
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

      final slotDoc = await FirebaseFirestore.instance
          .collection('slots')
          .doc(widget.slotId)
          .get();

      if (slotDoc.exists) {
        _slotData = slotDoc.data()!;
      }

      setState(() => _isDataLoading = false);
    } catch (e) {
      setState(() => _isDataLoading = false);
      _snack('Error loading data: $e');
    }
  }

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
            fillColor: Colors.blue.withOpacity(0.08),
            strokeColor: Colors.blue.withOpacity(0.4),
            strokeWidth: 2,
            consumeTapEvents: true,
            onTap: _showBubbleHint,
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
    _goToCurrentLocation();
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
        color: Colors.orange.shade700,
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
      _addBoardingPointMarker(current);

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: current, zoom: 16),
        ),
      );
    } catch (e) {
      _snack('Error getting location: $e');
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
  double get _totalCost =>
      double.parse((_vehicleCost + _additionalCost + _surcharge).toStringAsFixed(2));

  Future<void> _proceedToPay() async {
    if (_selectedLocation == null) {
      _snack('Please select a boarding point');
      return;
    }

    setState(() => _isBooking = true);
    try {
      final bookingData = {
        'user_id': widget.userId,
        'slot_id': widget.slotId,
        'boarding_point_latitude': _selectedLocation!.latitude,
        'boarding_point_longitude': _selectedLocation!.longitude,
        'distance_km': _distanceKm,
        'surcharge': _surcharge,
        'total_cost': _totalCost,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('bookings').add(bookingData);

      _snack('Booking created successfully!', color: Colors.green);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Error creating booking: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  void _snack(String msg, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDataLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                        onPressed: () =>
                            _mapController?.animateCamera(CameraUpdate.zoomIn()),
                        icon: const Icon(Icons.add),
                        tooltip: 'Zoom In',
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: () =>
                            _mapController?.animateCamera(CameraUpdate.zoomOut()),
                        icon: const Icon(Icons.remove),
                        tooltip: 'Zoom Out',
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
                        color: Colors.red,
                        tooltip: 'Clear Boarding Point',
                      ),
                    ],
                  ),
                ),

                // Go to Office (no toast)
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
                        color: Colors.indigo,
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
                        color: Colors.blue,
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
            totalCost: _totalCost,
            freeRadiusKm: _freeRadiusKm,
            isBooking: _isBooking,
            onProceed: _proceedToPay,
            hintVisible: _selectedLocation == null,
            isRadiusVisible: _isRadiusVisible,
            onToggleRadius: _toggleRadiusVisibility,
            showHintBubble: _showHintBubble,
          ),
        ],
      ),
    );
  }
}

// ... (rest of _LoadingOverlay, _RoundedButtonsColumn, _RadiusToggleButton, 
// _SpeechBubble, _TrianglePointer, and _SummarySheet remain as in my previous response)

/// Translucent blocking overlay
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.30),
      child: Center(
        child: Material(
          color: Colors.white,
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 14),
                Text(
                  'Initializing map & location...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A column for rounded icon buttons (used for map controls)
class _RoundedButtonsColumn extends StatelessWidget {
  const _RoundedButtonsColumn({Key? key, required this.children})
      : super(key: key);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
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

/// Toggle button for showing/hiding the free radius (colored)
class _RadiusToggleButton extends StatelessWidget {
  const _RadiusToggleButton({
    Key? key,
    required this.isVisible,
    required this.onPressed,
    this.showBadge = false,
  }) : super(key: key);

  final bool isVisible;
  final VoidCallback onPressed;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: _kAccent,
          elevation: 3,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVisible ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVisible ? 'Hide Radius' : 'Show Radius',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
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
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// A small speech bubble used to "nudge" the user near the toggle button.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    Key? key,
    required this.text,
    this.background = _kAccent,
    this.textColor = Colors.white,
  }) : super(key: key);

  final String text;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600),
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
  const _TrianglePointer({Key? key, required this.color}) : super(key: key);
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

/// Bottom cost summary with CTA (lesson details UI removed)
class _SummarySheet extends StatelessWidget {
  const _SummarySheet({
    required this.slotData,           // kept for later save
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

  @override
  Widget build(BuildContext context) {
    return Container(
      // No rounded corners on the summary container
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
                  const Text(
                    'Booking Summary',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  _RadiusToggleButton(
                    isVisible: isRadiusVisible,
                    onPressed: onToggleRadius,
                  ),
                ],
              ),

              // Bubble prompting to hide radius (shown near the button)
              if (showHintBubble) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Spacer(),
                    _SpeechBubble(
                      text:
                          'Tip: Hide the radius to select points inside the free area.',
                      background: _kAccent,
                      textColor: Colors.white,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // === Cost Breakdown ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cost Breakdown',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _costRow('Vehicle Cost', vehicleCost),
                    const SizedBox(height: 8),
                    _costRow('Additional Cost', additionalCost),

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

                    const SizedBox(height: 12),
                    Container(height: 1, color: Colors.grey[300]),
                    const SizedBox(height: 12),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '₹${totalCost.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Proceed Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isBooking ? null : onProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: isBooking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Proceed to Pay',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              if (hintVisible) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.amber[800]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tap on the map to select your boarding point',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber[800],
                            fontWeight: FontWeight.w500,
                          ),
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

  // ---- helpers ----
  Widget _costRow(String label, double amount, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isHighlight ? Colors.orange[700] : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isHighlight ? Colors.orange[700] : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _noteRow(String text) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.green[800],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
