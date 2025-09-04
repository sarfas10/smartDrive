// lib/maps_page_user.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapsPageUser extends StatefulWidget {
  final String userId; // required: user document id

  const MapsPageUser({
    super.key,
    required this.userId,
  });

  @override
  State<MapsPageUser> createState() => _MapsPageUserState();
}

class _MapsPageUserState extends State<MapsPageUser> {
  GoogleMapController? _mapController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Set<Marker> _markers = {};
  LatLng? _selectedLocation;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _isMapLoading = true;
  bool _isLocationLoading = false;
  bool _isPrefillLoading = true;

  // Default camera (New Delhi)
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    // We’ll prefill the marker with saved boarding point (if any)
    _prefillFromUser();
  }

  Future<void> _prefillFromUser() async {
    setState(() => _isPrefillLoading = true);
    try {
      final doc =
          await _firestore.collection('users').doc(widget.userId).get();

      final data = doc.data();
      if (data != null && data['boarding'] is Map<String, dynamic>) {
        final b = data['boarding'] as Map<String, dynamic>;
        final lat = (b['latitude'] as num?)?.toDouble();
        final lng = (b['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final pos = LatLng(lat, lng);
          _addMarker(pos, markUnsaved: false);
          // Also move camera there once map is ready
          _animateTo(pos, zoom: 16);
        }
      }
    } catch (e) {
      // non-fatal; user may not have a boarding point yet
      // ignore
    } finally {
      if (mounted) setState(() => _isPrefillLoading = false);
    }
  }

  // Called when map is created
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() {
      _isMapLoading = false;
    });
  }

  // Add or update marker at the tapped location
  void _addMarker(LatLng position, {bool markUnsaved = true}) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('boarding_point'),
          position: position,
          infoWindow: InfoWindow(
            title: 'Boarding Point',
            snippet:
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
        ),
      };
      _selectedLocation = position;
      if (markUnsaved) _hasUnsavedChanges = true;
    });
  }

  // Handle map tap
  void _onMapTap(LatLng position) {
    _addMarker(position);
  }

  // Fetch and move to current location
  Future<void> _goToCurrentLocation() async {
    setState(() => _isLocationLoading = true);

    try {
      // Check services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _toast('Location services are disabled.');
        setState(() => _isLocationLoading = false);
        return;
      }

      // Check permissions
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

      // Get position
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final current = LatLng(pos.latitude, pos.longitude);

      _addMarker(current);
      await _animateTo(current, zoom: 16);

    } catch (e) {
      _toast('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  Future<void> _animateTo(LatLng target, {double zoom = 16}) async {
    if (_mapController == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  // Clear the marker and coordinates
  void _clearMarker() {
    setState(() {
      _markers.clear();
      _selectedLocation = null;
      _hasUnsavedChanges = true; // clearing counts as a change
    });
  }

  // Save coordinates to users/{userId}
  Future<void> _saveToDatabase() async {
    if (_selectedLocation == null) {
      _toast('Please select a location first');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final data = {
        'boarding': {
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
        },
        'boarding_updated_at': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('users')
          .doc(widget.userId)
          .set(data, SetOptions(merge: true));

      _toast('Boarding point saved!', success: true);
      setState(() => _hasUnsavedChanges = false);
    } catch (e) {
      _toast('Error saving location: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Show warning dialog for unsaved changes
  Future<bool> _showUnsavedChangesDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 28),
                  SizedBox(width: 12),
                  Text('Unsaved Changes'),
                ],
              ),
              content: const Text(
                'You have unsaved changes to your boarding point. Leave without saving?',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Leave',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _toast(String msg, {bool success = false, bool error = false}) {
    final bg = error
        ? Colors.red
        : (success ? Colors.green : Colors.black87);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = _isMapLoading || _isLocationLoading || _isPrefillLoading;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (didPop) async {
        if (!didPop && _hasUnsavedChanges) {
          final shouldPop = await _showUnsavedChangesDialog();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select Boarding Point'),
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: _initialCameraPosition,
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
              onMapCreated: (c) {
                _onMapCreated(c);
                // If there was no prefill, we can optionally jump to GPS.
                // (Leave it manual to avoid extra prompts; user can tap the button.)
              },
              onTap: _onMapTap,
              onLongPress: null,
            ),

            // Loading overlay
            if (showOverlay)
              Container(
                color: Colors.black.withOpacity(0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isMapLoading
                              ? 'Loading Map...'
                              : (_isPrefillLoading
                                  ? 'Loading saved location...'
                                  : 'Getting Current Location...'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Back FAB (top-left)
            Positioned(
              left: 16,
              top: 24,
              child: _CircleButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () async {
                  if (_hasUnsavedChanges) {
                    final shouldPop = await _showUnsavedChangesDialog();
                    if (shouldPop && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),

            // Zoom controls (top-right)
            Positioned(
              right: 16,
              top: 24,
              child: Column(
                children: [
                  _CircleButton(
                    icon: Icons.add,
                    tooltip: 'Zoom In',
                    onPressed: () async {
                      await _mapController?.animateCamera(CameraUpdate.zoomIn());
                    },
                  ),
                  const SizedBox(height: 10),
                  _CircleButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom Out',
                    onPressed: () async {
                      await _mapController?.animateCamera(CameraUpdate.zoomOut());
                    },
                  ),
                ],
              ),
            ),

            // Clear marker (right side)
            Positioned(
              right: 16,
              bottom: 120,
              child: _CircleButton(
                icon: Icons.delete_sweep,
                tooltip: 'Clear Marker',
                color: Colors.red,
                onPressed: _clearMarker,
              ),
            ),

            // Go to current location (right side bottom)
            Positioned(
              right: 16,
              bottom: 60,
              child: _CircleButton(
                icon: Icons.my_location,
                tooltip: 'My Location',
                color: Colors.blue,
                onPressed: _goToCurrentLocation,
              ),
            ),

            // Coordinates & Save (top-ish bar)
            if (_selectedLocation != null)
              Positioned(
                right: 16,
                left: 100,
                top: 70,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Boarding Point',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveToDatabase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Small circular button used throughout
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black87;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: c,
        tooltip: tooltip,
      ),
    );
  }
}
