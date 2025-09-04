import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      // Clear existing markers (only one marker allowed)
      _markers.clear();
      
      // Add new marker
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          infoWindow: InfoWindow(
            title: 'Selected Location',
            snippet: '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
      
      // Update selected location and mark as unsaved
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
      // Check if location services are enabled
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        setState(() {
          _isLocationLoading = false;
        });
        return;
      }

      // Check permission
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

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final currentLocation = LatLng(position.latitude, position.longitude);

      // Add marker at current location
      _addMarker(currentLocation);

      // Move the camera to current location
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
        SnackBar(content: Text('Error getting location: $e')),
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
        const SnackBar(content: Text('Please select a location first')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      const String settingsDocId = 'app_settings'; // Fixed document ID
      
      final DocumentReference settingsDoc = firestore.collection('settings').doc(settingsDocId);
      
      // Check if document exists
      final DocumentSnapshot docSnapshot = await settingsDoc.get();
      
      final Map<String, dynamic> locationData = {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (docSnapshot.exists) {
        // Update existing document
        await settingsDoc.update(locationData);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Mark as saved
        setState(() {
          _hasUnsavedChanges = false;
        });
      } else {
        // Create new document
        await settingsDoc.set({
          ...locationData,
          'created_at': FieldValue.serverTimestamp(),
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Mark as saved
        setState(() {
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving location: $e'),
          backgroundColor: Colors.red,
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
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Unsaved Changes'),
            ],
          ),
          content: const Text(
            'You have unsaved location changes. Do you want to leave without saving?',
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    ) ?? false;
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
              zoomControlsEnabled: false, // Disable default zoom controls
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
              onLongPress: null, // Disable long press to avoid conflicts
            ),

            // Loading overlay
            if (_isMapLoading || _isLocationLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
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
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isMapLoading 
                            ? 'Loading Map...' 
                            : 'Getting Current Location...',
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
            
            // Back button (top left)
            Positioned(
              left: 16,
              top: 50,
              child: Container(
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
                  icon: const Icon(Icons.arrow_back),
                  color: Colors.black87,
                  tooltip: 'Go Back',
                ),
              ),
            ),
            
            // Custom Zoom Controls (styled to match other buttons)
            Positioned(
              right: 16,
              bottom: 200, // Above current location button
              child: Column(
                children: [
                  // Zoom In Button
                  Container(
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
                      onPressed: () async {
                        if (_mapController != null) {
                          await _mapController!.animateCamera(CameraUpdate.zoomIn());
                        }
                      },
                      icon: const Icon(Icons.add),
                      color: Colors.black87,
                      tooltip: 'Zoom In',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Zoom Out Button
                  Container(
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
                      onPressed: () async {
                        if (_mapController != null) {
                          await _mapController!.animateCamera(CameraUpdate.zoomOut());
                        }
                      },
                      icon: const Icon(Icons.remove),
                      color: Colors.black87,
                      tooltip: 'Zoom Out',
                    ),
                  ),
                ],
              ),
            ),
            
            // Clear button (above current location button)
            Positioned(
              right: 16,
              bottom: 120, // Above current location button
              child: Container(
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
                  onPressed: _clearMarker,
                  icon: const Icon(Icons.delete_sweep),
                  color: Colors.red,
                  tooltip: 'Clear All Markers',
                ),
              ),
            ),
            
            // Current location button
            Positioned(
              right: 16,
              bottom: 60, // Bottom position
              child: Container(
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
                  onPressed: _goToCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  color: Colors.blue,
                  tooltip: 'Go to Current Location',
                ),
              ),
            ),
            
            // Coordinates display at top right (circular radius box)
            if (_selectedLocation != null)
              Positioned(
                right: 16,
                left: 100, // More space from left, positioned towards right
                top: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      const Icon(
                        Icons.location_on,
                        color: Colors.blue,
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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