import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_common.dart';
import 'package:smart_drive/reusables/vehicle_icons.dart';
import 'maps_page_admin.dart'; 

import 'login.dart';                  
import 'messaging_setup.dart';        
import 'services/session_service.dart'; 

class SettingsBlock extends StatefulWidget {
  const SettingsBlock({super.key});

  @override
  State<SettingsBlock> createState() => _SettingsBlockState();
}

class _SettingsBlockState extends State<SettingsBlock> {
 
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _perKmCtrl = TextEditingController();
  final TextEditingController _policyCtrl = TextEditingController();

  
  final FirebaseAuth _auth = FirebaseAuth.instance;

  
  Map<String, dynamic>? _lastAppliedSettings;

  @override
  void dispose() {
    _radiusCtrl.dispose();
    _perKmCtrl.dispose();
    _policyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ===== Responsive metrics =====
    final sw = MediaQuery.of(context).size.width;
    final isDesktop = sw >= 1024;

    double pct(double p) => sw * p; // p in 0..1
    final pad = pct(0.04).clamp(12.0, 28.0);          // ~4% of width
    final gap = (pad * 0.75).clamp(8.0, 24.0);        // scaled gaps
    final cardRadius = (pct(0.02)).clamp(8.0, 14.0);  // 2% radius
    final maxContentWidth = isDesktop ? sw * 0.78 : sw; // center on large

    // 🔁 FIXED single-doc ID
    final doc = FirebaseFirestore.instance.collection('settings').doc('app_settings');

    return Container(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          final m = (snap.data?.data() as Map<String, dynamic>?) ?? {};

          // Initialize once, or when Firestore changes meaningfully
          if (_lastAppliedSettings == null || !_deepEquals(_lastAppliedSettings!, m)) {
            _lastAppliedSettings = Map<String, dynamic>.from(m);

            // Defaults
            final radius = (m['free_radius_km'] ?? 5).toString();
            final perKm = (m['surcharge_per_km'] ?? 10).toString();
            final policy = (m['cancellation_policy'] ??
                    'Cancellations within 24 hours incur 20% fee.')
                .toString();

            if (_radiusCtrl.text != radius) _radiusCtrl.text = radius;
            if (_perKmCtrl.text != perKm) _perKmCtrl.text = perKm;
            if (_policyCtrl.text != policy) _policyCtrl.text = policy;
          }

          // Presence of saved coordinates
          final savedLat = m['latitude'];
          final savedLng = m['longitude'];
          final hasSaved = (savedLat is num) && (savedLng is num);

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: maxContentWidth,
              child: ListView(
                padding: EdgeInsets.all(pad),
                children: [
                  _buildOfficeLocationCard(
                    doc: doc,
                    pad: pad,
                    gap: gap,
                    radius: cardRadius,
                    hasSaved: hasSaved,
                    savedLat: savedLat,
                    savedLng: savedLng,
                  ),
                  SizedBox(height: gap),
                  _buildVehicleManagementCard(pad, gap, cardRadius, sw),
                  SizedBox(height: gap),
                  _buildPaymentSettingsCard(doc, pad, cardRadius),
                  SizedBox(height: gap),
                  // 🔽 NEW: logout card
                  _buildLogoutCard(pad, cardRadius),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- UI SECTIONS ----------------

  /// Office Location card:
  Widget _buildOfficeLocationCard({
    required DocumentReference doc,
    required double pad,
    required double gap,
    required double radius,
    required bool hasSaved,
    required dynamic savedLat,
    required dynamic savedLng,
  }) {
    final savedText = hasSaved
        ? 'Lat: ${(savedLat as num).toDouble().toStringAsFixed(6)}\n'
          'Lng: ${(savedLng as num).toDouble().toStringAsFixed(6)}'
        : 'No lat/long saved';

    final buttonLabel = hasSaved ? 'Update Location' : 'Add Location';

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Office Location'),
          SizedBox(height: gap),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(pad * 0.75),
            decoration: BoxDecoration(
              color: hasSaved ? Colors.blue[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(radius * 0.75),
              border: Border.all(
                color: hasSaved ? Colors.blue[200]! : Colors.orange[200]!,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasSaved ? Icons.location_on : Icons.info_outline,
                  color: hasSaved ? Colors.blue[600] : Colors.orange[700],
                  size: (pad * 1.2).clamp(18.0, 28.0),
                ),
                SizedBox(width: pad * 0.5),
                Expanded(
                  child: Text(
                    savedText,
                    style: TextStyle(
                      fontSize: (pad * 0.6).clamp(11.0, 14.0),
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                // Navigate to the dedicated maps page to add/update
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MapsPageAdmin(),
                  ),
                );
                if (mounted && result == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(hasSaved ? 'Location updated' : 'Location added'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.map),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasSaved ? Colors.blue : Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: (pad * 0.6).clamp(10.0, 16.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vehicles card
  Widget _buildVehicleManagementCard(
      double pad, double gap, double radius, double sw) {
    final iconBox = (sw * 0.12).clamp(44.0, 64.0);
    final iconSize = (iconBox * 0.56).clamp(22.0, 36.0);

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(Icons.directions_car, color: Colors.blue[600], size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Vehicles",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddVehicleDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: (pad * 0.8).clamp(10.0, 16.0),
                    vertical: (pad * 0.4).clamp(6.0, 12.0),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          SizedBox(height: gap),

          // Vehicle List
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('vehicles')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, vehicleSnap) {
              if (vehicleSnap.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              if (!vehicleSnap.hasData || vehicleSnap.data!.docs.isEmpty) {
                return Container(
                  padding: EdgeInsets.all(pad * 1.2),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.directions_car_filled,
                          size: 40, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      const Text(
                        'No vehicles added yet.\nClick "Add" to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: vehicleSnap.data!.docs.map((vehicleDoc) {
                  final data = vehicleDoc.data() as Map<String, dynamic>? ?? {};
                  final carType = (data['car_type'] ?? 'Unknown Vehicle').toString();
                  final charge = data['vehicle_charge'] ?? 0;
                  final icon = VehicleIcons.forType(carType);

                  return Container(
                    margin: EdgeInsets.only(bottom: gap),
                    padding: EdgeInsets.all(pad),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: iconBox,
                          height: iconBox,
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(radius * 0.75),
                          ),
                          child: Icon(icon, color: Colors.blue[600], size: iconSize),
                        ),
                        SizedBox(width: pad),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                carType,
                                style: TextStyle(
                                  fontSize: (iconBox * 0.32).clamp(14.0, 18.0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: (gap * 0.25)),
                              Text(
                                '₹${charge.toString()} per session',
                                style: TextStyle(
                                  fontSize: (iconBox * 0.28).clamp(12.0, 16.0),
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async => await vehicleDoc.reference.delete(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSettingsCard(
      DocumentReference doc, double pad, double radius) {
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Payment Settings'),
        SizedBox(height: pad * 0.75),
        field('Free Radius (km)', _radiusCtrl, number: true),
        SizedBox(height: pad * 0.5),
        field('Surcharge per km (₹)', _perKmCtrl, number: true),
        SizedBox(height: pad * 0.5),
        area('Cancellation Policy', _policyCtrl),
        SizedBox(height: pad * 0.75),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              await doc.set({
                'free_radius_km': double.tryParse(_radiusCtrl.text.trim()) ?? 5,
                'surcharge_per_km': double.tryParse(_perKmCtrl.text.trim()) ?? 10,
                'cancellation_policy': _policyCtrl.text.trim(),
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment settings saved'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                vertical: (pad * 0.6).clamp(10.0, 16.0),
              ),
            ),
            child: const Text('Save Payment Settings'),
          ),
        ),
      ]),
    );
  }

  // 🔽 NEW: Logout card
  Widget _buildLogoutCard(double pad, double radius) {
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Logout'),
          SizedBox(height: pad * 0.75),
          Text(
            'Sign out from this device.',
            style: TextStyle(color: Colors.grey[700]),
          ),
          SizedBox(height: pad * 0.75),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _logout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Text _title(String s) => Text(
        s,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      );

  // ---------------- Vehicles: Add dialogs ----------------

  void _showAddVehicleDialog(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final isDesktop = sw >= 1024;
    final dialogW = sw * (isDesktop ? 0.6 : 0.92);
    final dialogH = sh * (isDesktop ? 0.72 : 0.8);
    final pad = (sw * 0.04).clamp(12.0, 28.0);

    final predefinedVehicles = [
      {'type': 'Manual Sedan', 'description': 'Standard transmission', 'defaultFee': 500},
      {'type': 'Automatic Sedan', 'description': 'Automatic transmission', 'defaultFee': 600},
      {'type': 'Manual Hatchback', 'description': 'Compact car with manual transmission', 'defaultFee': 450},
      {'type': 'Automatic Hatchback', 'description': 'Compact car with automatic transmission', 'defaultFee': 550},
      {'type': 'Manual SUV', 'description': 'Sports utility vehicle', 'defaultFee': 700},
      {'type': 'Automatic SUV', 'description': 'Sports utility vehicle', 'defaultFee': 800},
      {'type': 'Motorcycle', 'description': 'Two wheeler vehicle', 'defaultFee': 300},
      {'type': 'Scooter', 'description': 'Automatic two wheeler', 'defaultFee': 250},
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: (sw * 0.04).clamp(12.0, 40.0),
            vertical: (sh * 0.04).clamp(12.0, 40.0),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0))),
          child: SizedBox(
            width: dialogW,
            height: dialogH,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Add Vehicle Type',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  SizedBox(height: pad * 0.75),
                  Text('Select a vehicle type to add:', style: TextStyle(color: Colors.grey[600])),
                  SizedBox(height: pad * 0.75),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: predefinedVehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = predefinedVehicles[index];
                        final carType = vehicle['type'] as String;
                        final icon = VehicleIcons.forType(carType);

                        final iconBox = (sw * 0.12).clamp(44.0, 64.0);
                        final iconSize = (iconBox * 0.56).clamp(22.0, 36.0);

                        return Container(
                          margin: EdgeInsets.only(bottom: pad * 0.5),
                          child: InkWell(
                            onTap: () => _showFeeDialog(context, vehicle),
                            borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
                            child: Container(
                              padding: EdgeInsets.all(pad),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: iconBox,
                                    height: iconBox,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
                                    ),
                                    child: Icon(icon, color: Colors.blue[600], size: iconSize),
                                  ),
                                  SizedBox(width: pad),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(carType,
                                            style: const TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.w600)),
                                        SizedBox(height: pad * 0.25),
                                        Text(
                                          vehicle['description'] as String,
                                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFeeDialog(BuildContext context, Map<String, dynamic> vehicle) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final isDesktop = sw >= 1024;
    final feeController =
        TextEditingController(text: vehicle['defaultFee'].toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: (sw * 0.06).clamp(16.0, 60.0),
            vertical: (sh * 0.06).clamp(16.0, 60.0),
          ),
          title: Text('Set Fee for ${vehicle['type']}'),
          content: SizedBox(
            width: sw * (isDesktop ? 0.4 : 0.9), // % width
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Fee (₹)',
                    border: OutlineInputBorder(),
                    prefixText: '₹',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final fee = double.tryParse(feeController.text.trim()) ?? vehicle['defaultFee'];
                final carType = vehicle['type'] as String;

                final col = FirebaseFirestore.instance.collection('vehicles');
                final docRef = col.doc();
                await docRef.set({
                  'vehicle_id': docRef.id,
                  'car_type': carType,
                  'vehicle_charge': fee,
                  'created_at': FieldValue.serverTimestamp(),
                });

                Navigator.of(context).pop(); // fee dialog
                Navigator.of(context).pop(); // list dialog
              },
              child: const Text('Add Vehicle'),
            ),
          ],
        );
      },
    );
  }

  // ---------------- Logout logic ----------------

  Future<void> _logout({bool wipeAllPrefs = false}) async {
  try {
    // 1) Stop role/status notifications (set alsoAll: true to silence everything)
    await unsubscribeRoleStatusTopics(alsoAll: false);

    // 2) Clear saved session
    await SessionService().clear(); // removes userId/role/status

    // 3) Clear remember-me prefs so auto-redirect won’t happen
    final sp = await SharedPreferences.getInstance();
    await sp.remove('sd_saved_email');
    await sp.setBool('sd_remember_me', false);

    // Optional: nuke ALL prefs if you ever want a hard logout
    if (wipeAllPrefs) {
      await sp.clear();
    }

    // 4) Firebase sign out
    await _auth.signOut();

    // 5) Navigate to Login (reset stack)
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error logging out: $e')),
    );
  }
}


  // ---------------- Utils ----------------

  bool _deepEquals(Map a, Map b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final va = a[key];
      final vb = b[key];
      if (va is Map && vb is Map) {
        if (!_deepEquals(va, vb)) return false;
      } else if (va != vb) {
        return false;
      }
    }
    return true;
  }
}
