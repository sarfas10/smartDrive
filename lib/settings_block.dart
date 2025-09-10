// lib/settings_block.dart
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
import 'package:smart_drive/theme/app_theme.dart';

class SettingsBlock extends StatefulWidget {
  const SettingsBlock({super.key});

  @override
  State<SettingsBlock> createState() => _SettingsBlockState();
}

class _SettingsBlockState extends State<SettingsBlock> {
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _perKmCtrl = TextEditingController();
  final TextEditingController _policyCtrl = TextEditingController();

  // separate controllers for 8-type and H-type driving test charges
  final TextEditingController _testCharge8Ctrl = TextEditingController();
  final TextEditingController _testChargeHCtrl = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _lastAppliedSettings;
  bool _drivingTestIncluded = true;

  // numeric values cached for quick access
  double _testCharge8 = 0.0;
  double _testChargeH = 0.0;

  @override
  void dispose() {
    _radiusCtrl.dispose();
    _perKmCtrl.dispose();
    _policyCtrl.dispose();
    _testCharge8Ctrl.dispose();
    _testChargeHCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final isDesktop = sw >= 1024;

    double pct(double p) => sw * p;
    final pad = pct(0.04).clamp(12.0, 28.0);
    final gap = (pad * 0.75).clamp(8.0, 24.0);
    final cardRadius = (pct(0.02)).clamp(8.0, 14.0);
    final maxContentWidth = isDesktop ? sw * 0.78 : sw;

    final doc = FirebaseFirestore.instance.collection('settings').doc('app_settings');

    return Container(
      color: AppColors.background,
      child: StreamBuilder<DocumentSnapshot>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          final m = (snap.data?.data() as Map<String, dynamic>?) ?? {};

          if (_lastAppliedSettings == null || !_deepEquals(_lastAppliedSettings!, m)) {
            _lastAppliedSettings = Map<String, dynamic>.from(m);

            final radius = (m['free_radius_km'] ?? 5).toString();
            final perKm = (m['surcharge_per_km'] ?? 10).toString();
            final policy = (m['cancellation_policy'] ?? 'Cancellations within 24 hours incur 20% fee.').toString();

            // load separate charges (defaults to 0.0)
            final raw8 = m['test_charge_8'];
            final rawH = m['test_charge_h'];
            final drivingTestIncluded = (m['driving_test_included'] ?? true) as bool;

            if (_radiusCtrl.text != radius) _radiusCtrl.text = radius;
            if (_perKmCtrl.text != perKm) _perKmCtrl.text = perKm;
            if (_policyCtrl.text != policy) _policyCtrl.text = policy;

            // parse 8-type
            if (raw8 is num) {
              _testCharge8 = raw8.toDouble();
            } else if (raw8 != null) {
              _testCharge8 = double.tryParse(raw8.toString()) ?? 0.0;
            } else {
              _testCharge8 = 0.0;
            }
            // parse H-type
            if (rawH is num) {
              _testChargeH = rawH.toDouble();
            } else if (rawH != null) {
              _testChargeH = double.tryParse(rawH.toString()) ?? 0.0;
            } else {
              _testChargeH = 0.0;
            }

            if (_testCharge8Ctrl.text != _testCharge8.toStringAsFixed(2)) {
              _testCharge8Ctrl.text = _testCharge8.toStringAsFixed(2);
            }
            if (_testChargeHCtrl.text != _testChargeH.toStringAsFixed(2)) {
              _testChargeHCtrl.text = _testChargeH.toStringAsFixed(2);
            }

            _drivingTestIncluded = drivingTestIncluded;
          }

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
        color: AppColors.neuBg,
        border: Border.all(color: AppColors.divider),
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
              color: hasSaved ? AppColors.brand.withOpacity(0.06) : AppColors.warnBg,
              borderRadius: BorderRadius.circular(radius * 0.75),
              border: Border.all(
                color: hasSaved ? AppColors.brand.withOpacity(0.25) : AppColors.warnBg,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasSaved ? Icons.location_on : Icons.info_outline,
                  color: hasSaved ? AppColors.brand : AppColors.warning,
                  size: (pad * 1.2).clamp(18.0, 28.0),
                ),
                SizedBox(width: pad * 0.5),
                Expanded(
                  child: Text(
                    savedText,
                    style: AppText.tileSubtitle.copyWith(
                      fontSize: (pad * 0.6).clamp(11.0, 14.0),
                      color: context.c.onSurface,
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
                      content: Text(hasSaved ? 'Location updated' : 'Location added', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: Icon(Icons.map, color: AppColors.onSurfaceInverse),
              label: Text(buttonLabel, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasSaved ? AppColors.brand : AppColors.warning,
                foregroundColor: AppColors.onSurfaceInverse,
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
  Widget _buildVehicleManagementCard(double pad, double gap, double radius, double sw) {
    final iconBox = (sw * 0.12).clamp(44.0, 64.0);
    final iconSize = (iconBox * 0.56).clamp(22.0, 36.0);

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(Icons.directions_car, color: AppColors.brand, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Vehicles",
                  style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddVehicleDialog(context),
                icon: Icon(Icons.add, size: 18, color: AppColors.onSurfaceInverse),
                label: Text('Add', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onSurfaceInverse,
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
            stream: FirebaseFirestore.instance.collection('vehicles').orderBy('created_at', descending: true).snapshots(),
            builder: (context, vehicleSnap) {
              if (vehicleSnap.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: Center(child: CircularProgressIndicator(color: context.c.primary)),
                );
              }
              if (!vehicleSnap.hasData || vehicleSnap.data!.docs.isEmpty) {
                return Container(
                  padding: EdgeInsets.all(pad * 1.2),
                  decoration: BoxDecoration(
                    color: AppColors.neuBg,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.directions_car_filled, size: 40, color: AppColors.onSurfaceFaint),
                      const SizedBox(height: 8),
                      Text(
                        'No vehicles added yet.\nClick "Add" to get started.',
                        textAlign: TextAlign.center,
                        style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint),
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
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: iconBox,
                          height: iconBox,
                          decoration: BoxDecoration(
                            color: AppColors.brand.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(radius * 0.75),
                          ),
                          child: Icon(icon, color: AppColors.brand, size: iconSize),
                        ),
                        SizedBox(width: pad),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                carType,
                                style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: (gap * 0.25)),
                              Text(
                                '₹${charge.toString()} per session',
                                style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: AppColors.danger),
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

  Widget _buildPaymentSettingsCard(DocumentReference doc, double pad, double radius) {
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.neuBg,
        border: Border.all(color: AppColors.divider),
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
        SizedBox(height: pad * 0.5),

        // UPDATED: separate fields for 8-type and H-type test charges
        Text('Driving Test Charge — 8 type (₹)', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _testCharge8Ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: InputDecoration(
            labelText: '8 type charge',
            prefixText: '₹',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
            filled: true,
            fillColor: AppColors.surface,
          ),
          style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
        ),
        SizedBox(height: pad * 0.5),

        Text('Driving Test Charge — H type (₹)', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _testChargeHCtrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: InputDecoration(
            labelText: 'H type charge',
            prefixText: '₹',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
            filled: true,
            fillColor: AppColors.surface,
          ),
          style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
        ),

        SizedBox(height: pad * 0.5),
        CheckboxListTile(
          value: _drivingTestIncluded,
          onChanged: (val) => setState(() => _drivingTestIncluded = val ?? true),
          title: const Text('Driving Test Included'),
          controlAffinity: ListTileControlAffinity.leading,
        ),

        SizedBox(height: pad * 0.75),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final test8 = double.tryParse(_testCharge8Ctrl.text.trim()) ?? _testCharge8;
              final testH = double.tryParse(_testChargeHCtrl.text.trim()) ?? _testChargeH;

              await doc.set({
                'free_radius_km': double.tryParse(_radiusCtrl.text.trim()) ?? 5,
                'surcharge_per_km': double.tryParse(_perKmCtrl.text.trim()) ?? 10,
                'cancellation_policy': _policyCtrl.text.trim(),
                // write both charges
                'test_charge_8': test8,
                'test_charge_h': testH,
                'driving_test_included': _drivingTestIncluded,
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              setState(() {
                _testCharge8 = test8;
                _testChargeH = testH;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payment settings saved', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                vertical: (pad * 0.6).clamp(10.0, 16.0),
              ),
              backgroundColor: context.c.primary,
              foregroundColor: context.c.onPrimary,
            ),
            child: Text('Save Payment Settings', style: AppText.tileTitle.copyWith(color: context.c.onPrimary)),
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
        color: AppColors.neuBg,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Logout'),
          SizedBox(height: pad * 0.75),
          Text(
            'Sign out from this device.',
            style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
          ),
          SizedBox(height: pad * 0.75),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Logout', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
                    content: Text('Are you sure you want to logout?', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: AppText.tileSubtitle.copyWith(color: context.c.primary)),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _logout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: AppColors.onSurfaceInverse,
                        ),
                        child: Text('Logout', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.logout, color: AppColors.onSurfaceInverse),
              label: Text('Logout', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onSurfaceInverse,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Text _title(String s) => Text(
        s,
        style: AppText.sectionTitle.copyWith(color: context.c.onSurface, fontWeight: FontWeight.bold),
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
                    Text('Add Vehicle Type', style: AppText.sectionTitle.copyWith(color: context.c.onSurface, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: context.c.onSurface),
                    ),
                  ]),
                  SizedBox(height: pad * 0.75),
                  Text('Select a vehicle type to add:', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
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
                                border: Border.all(color: AppColors.divider),
                                borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: iconBox,
                                    height: iconBox,
                                    decoration: BoxDecoration(
                                      color: AppColors.brand.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
                                    ),
                                    child: Icon(icon, color: AppColors.brand, size: iconSize),
                                  ),
                                  SizedBox(width: pad),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(carType, style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600)),
                                        SizedBox(height: pad * 0.25),
                                        Text(vehicle['description'] as String, style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios, color: AppColors.onSurfaceFaint, size: 16),
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
    final feeController = TextEditingController(text: vehicle['defaultFee'].toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(horizontal: (sw * 0.06).clamp(16.0, 60.0), vertical: (sh * 0.06).clamp(16.0, 60.0)),
          title: Text('Set Fee for ${vehicle['type']}', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
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
                  decoration: InputDecoration(
                    labelText: 'Fee (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                    prefixText: '₹',
                    labelStyle: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: AppText.tileSubtitle.copyWith(color: context.c.primary)),
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
              style: ElevatedButton.styleFrom(backgroundColor: context.c.primary, foregroundColor: context.c.onPrimary),
              child: Text('Add Vehicle', style: AppText.tileTitle.copyWith(color: context.c.onPrimary)),
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
        SnackBar(content: Text('Error logging out: $e', style: AppText.tileSubtitle.copyWith(color: AppColors.danger))),
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
