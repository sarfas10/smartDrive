// lib/maps_page_admin.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import your design tokens & theme helpers — adjust this path if needed
import 'theme/app_theme.dart';

class MapsPageAdmin extends StatefulWidget {
  const MapsPageAdmin({super.key});

  @override
  _MapsPageAdminState createState() => _MapsPageAdminState();
}

class _MapsPageAdminState extends State<MapsPageAdmin> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  LatLng? _selectedLocation;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _isMapLoading = true;
  bool _isLocationLoading = true;

  // Default camera (New Delhi)
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(28.6139, 77.2090),
    zoom: 12,
  );

  // Called when map is created
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() {
      _isMapLoading = false;
    });
    _goToCurrentLocation();
  }

  // Add or update marker at the tapped location
  void _addMarker(LatLng position) {
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          infoWindow: InfoWindow(
            title: 'Selected Location',
            snippet:
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
      _selectedLocation = position;
      _hasUnsavedChanges = true;
    });
  }

  // Handle map tap
  void _onMapTap(LatLng position) {
    _addMarker(position);
  }

  // Fetch and move to current location
  Future<void> _goToCurrentLocation() async {
    setState(() {
      _isLocationLoading = true;
    });

    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location services are disabled.'), backgroundColor: AppColors.warning),
        );
        setState(() {
          _isLocationLoading = false;
        });
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLocationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLocationLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final currentLocation = LatLng(position.latitude, position.longitude);

      _addMarker(currentLocation);

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentLocation,
            zoom: 16,
          ),
        ),
      );

      setState(() {
        _isLocationLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLocationLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  // Clear the marker and coordinates
  void _clearMarker() {
    setState(() {
      _markers.clear();
      _selectedLocation = null;
      _hasUnsavedChanges = false;
    });
  }

  // Save coordinates to Firebase
  Future<void> _saveToDatabase() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a location first'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      const String settingsDocId = 'app_settings';

      final DocumentReference settingsDoc =
          firestore.collection('settings').doc(settingsDocId);

      final DocumentSnapshot docSnapshot = await settingsDoc.get();

      final Map<String, dynamic> locationData = {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (docSnapshot.exists) {
        await settingsDoc.update(locationData);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        setState(() {
          _hasUnsavedChanges = false;
        });
      } else {
        await settingsDoc.set({
          ...locationData,
          'created_at': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        setState(() {
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving location: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
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
                borderRadius: BorderRadius.circular(AppRadii.l),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
                  const SizedBox(width: 12),
                  Text('Unsaved Changes', style: context.t.titleMedium?.copyWith(color: context.c.onSurface)),
                ],
              ),
              content: Text(
                'You have unsaved location changes. Do you want to leave without saving?',
                style: context.t.bodyMedium?.copyWith(color: context.c.onSurface),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel', style: context.t.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: context.c.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.m),
                    ),
                  ),
                  child: Text(
                    'Leave',
                    style: context.t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // Handle back navigation
  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges) {
      return await _showUnsavedChangesDialog();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
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
        body: Stack(
          children: [
            // Map
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
              onMapCreated: _onMapCreated,
              onTap: _onMapTap,
              onLongPress: null,
            ),

            // Loading overlay
            if (_isMapLoading || _isLocationLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.c.surface,
                      borderRadius: BorderRadius.circular(AppRadii.l),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(context.c.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isMapLoading ? 'Loading Map...' : 'Getting Current Location...',
                          style: context.t.bodyMedium?.copyWith(color: context.c.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Back button (top left)
            Positioned(
              left: 16,
              top: MediaQuery.of(context).padding.top + 10,
              child: Container(
                decoration: BoxDecoration(
                  color: context.c.surface,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: AppShadows.card,
                ),
                child: IconButton(
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
                  icon: Icon(Icons.arrow_back, color: context.c.onSurface),
                  tooltip: 'Go Back',
                ),
              ),
            ),

            // Custom Zoom Controls
            Positioned(
              right: 16,
              bottom: 200,
              child: Column(
                children: [
                  // Zoom In Button
                  _roundIconButton(
                    icon: Icons.add,
                    onTap: () async {
                      if (_mapController != null) {
                        await _mapController!.animateCamera(CameraUpdate.zoomIn());
                      }
                    },
                    tooltip: 'Zoom In',
                  ),
                  const SizedBox(height: 8),
                  // Zoom Out Button
                  _roundIconButton(
                    icon: Icons.remove,
                    onTap: () async {
                      if (_mapController != null) {
                        await _mapController!.animateCamera(CameraUpdate.zoomOut());
                      }
                    },
                    tooltip: 'Zoom Out',
                  ),
                ],
              ),
            ),

            // Clear button
            Positioned(
              right: 16,
              bottom: 120,
              child: _roundIconButton(
                icon: Icons.delete_sweep,
                onTap: _clearMarker,
                tooltip: 'Clear All Markers',
                iconColor: AppColors.danger,
              ),
            ),

            // Current location button
            Positioned(
              right: 16,
              bottom: 60,
              child: _roundIconButton(
                icon: Icons.my_location,
                onTap: _goToCurrentLocation,
                tooltip: 'Go to Current Location',
                iconColor: context.c.primary,
              ),
            ),

            // Coordinates display at top right
            if (_selectedLocation != null)
              Positioned(
                right: 16,
                left: 100,
                top: MediaQuery.of(context).padding.top + 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: context.c.surface,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: context.c.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Selected Location',
                              style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                              style: context.t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: context.c.onSurface),
                            ),
                            Text(
                              'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                              style: context.t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: context.c.onSurface),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveToDatabase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.c.primary,
                          foregroundColor: context.c.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.l),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(context.c.onPrimary),
                                ),
                              )
                            : Text(
                                'Save',
                                style: context.t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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

  // Helper to create the round icon buttons with consistent theme
  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: BorderRadius.circular(25),
        boxShadow: AppShadows.card,
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: iconColor ?? context.c.onSurface),
        tooltip: tooltip,
      ),
    );
  }
}
