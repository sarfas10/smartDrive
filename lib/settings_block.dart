// lib/settings_block.dart
// SettingsBlock with Admin Popup (signed Cloudinary upload) integrated.
// + Simplified "Generate Report" UI: preset date selectors (30D, 90D, 6 months, 1 year) + Generate button.
// The Generate button now opens a dedicated ReportPage.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_drive/report_page.dart';

import 'ui_common.dart';
import 'package:smart_drive/reusables/vehicle_icons.dart';
import 'maps_page_admin.dart';

import 'login.dart';
import 'messaging_setup.dart';
import 'services/session_service.dart';
import 'package:smart_drive/theme/app_theme.dart';

// New dependencies for signed Cloudinary upload & file picking
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';

// Report page import

class SettingsBlock extends StatefulWidget {
  const SettingsBlock({super.key});

  @override
  State<SettingsBlock> createState() => _SettingsBlockState();
}

class _SettingsBlockState extends State<SettingsBlock> {
  // ===== Settings controllers =====
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _perKmCtrl = TextEditingController();
  final TextEditingController _policyCtrl = TextEditingController();
  final TextEditingController _testCharge8Ctrl = TextEditingController();
  final TextEditingController _testChargeHCtrl = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _lastAppliedSettings;
  bool _drivingTestIncluded = true;

  // numeric values cached for quick access
  double _testCharge8 = 0.0;
  double _testChargeH = 0.0;

  // ===== Admin Popup state =====
  PlatformFile? _pickedPopupFile;
  bool _popupUploading = false;
  bool _showRecentPopups = true;

  // Cloudinary signer endpoint (your signature.php)
  static const String _signatureEndpoint =
      'https://tajdrivingschool.in/smartDrive/cloudinary/signature.php';
  static const String _cloudBaseFolder = 'smartDrive/admin_popups';
  static const String _cloudName = 'dnxj5r6rc'; // update if different

  // ===== Generate Report UI state (UI only) =====
  // only selected preset is kept; date range is computed when Generate is pressed
  String _selectedPreset = '30D'; // options: 30D, 90D, 6M, 1Y

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

    final doc = FirebaseFirestore.instance
        .collection('settings')
        .doc('app_settings');

    return Container(
      color: AppColors.background,
      child: StreamBuilder<DocumentSnapshot>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          final m = (snap.data?.data() as Map<String, dynamic>?) ?? {};

          if (_lastAppliedSettings == null ||
              !_deepEquals(_lastAppliedSettings!, m)) {
            _lastAppliedSettings = Map<String, dynamic>.from(m);

            final radius = (m['free_radius_km'] ?? 5).toString();
            final perKm = (m['surcharge_per_km'] ?? 10).toString();
            final policy =
                (m['cancellation_policy'] ??
                        'Cancellations within 24 hours incur 20% fee.')
                    .toString();

            // load separate charges (defaults to 0.0)
            final raw8 = m['test_charge_8'];
            final rawH = m['test_charge_h'];
            final drivingTestIncluded =
                (m['driving_test_included'] ?? true) as bool;

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
                  _buildAdminPopupCard(pad, gap, cardRadius),
                  SizedBox(height: gap),
                  // ── NEW: Generate Report UI (simplified preset selector + generate)
                  _buildGenerateReportCard(pad, gap, cardRadius),
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
              color: hasSaved
                  ? AppColors.brand.withOpacity(0.06)
                  : AppColors.warnBg,
              borderRadius: BorderRadius.circular(radius * 0.75),
              border: Border.all(
                color: hasSaved
                    ? AppColors.brand.withOpacity(0.25)
                    : AppColors.warnBg,
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
                  MaterialPageRoute(builder: (_) => const MapsPageAdmin()),
                );
                if (mounted && result == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        hasSaved ? 'Location updated' : 'Location added',
                        style: AppText.tileSubtitle.copyWith(
                          color: AppColors.onSurfaceInverse,
                        ),
                      ),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: Icon(Icons.map, color: AppColors.onSurfaceInverse),
              label: Text(
                buttonLabel,
                style: AppText.tileSubtitle.copyWith(
                  color: AppColors.onSurfaceInverse,
                ),
              ),
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
  Widget _buildVehicleManagementCard(
    double pad,
    double gap,
    double radius,
    double sw,
  ) {
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
                  style: AppText.sectionTitle.copyWith(
                    color: context.c.onSurface,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddVehicleDialog(context),
                icon: Icon(
                  Icons.add,
                  size: 18,
                  color: AppColors.onSurfaceInverse,
                ),
                label: Text(
                  'Add',
                  style: AppText.tileSubtitle.copyWith(
                    color: AppColors.onSurfaceInverse,
                  ),
                ),
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
            stream: FirebaseFirestore.instance
                .collection('vehicles')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, vehicleSnap) {
              if (vehicleSnap.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: Center(
                    child: CircularProgressIndicator(color: context.c.primary),
                  ),
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
                      Icon(
                        Icons.directions_car_filled,
                        size: 40,
                        color: AppColors.onSurfaceFaint,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No vehicles added yet.\nClick "Add" to get started.',
                        textAlign: TextAlign.center,
                        style: AppText.hintSmall.copyWith(
                          color: AppColors.onSurfaceFaint,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: vehicleSnap.data!.docs.map((vehicleDoc) {
                  final data = vehicleDoc.data() as Map<String, dynamic>? ?? {};
                  final carType = (data['car_type'] ?? 'Unknown Vehicle')
                      .toString();
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
                          child: Icon(
                            icon,
                            color: AppColors.brand,
                            size: iconSize,
                          ),
                        ),
                        SizedBox(width: pad),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                carType,
                                style: AppText.tileTitle.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: (gap * 0.25)),
                              Text(
                                '₹${charge.toString()} per session',
                                style: AppText.hintSmall.copyWith(
                                  color: AppColors.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                          ),
                          onPressed: () async =>
                              await vehicleDoc.reference.delete(),
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
    DocumentReference doc,
    double pad,
    double radius,
  ) {
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
          _title('Payment Settings'),
          SizedBox(height: pad * 0.75),
          field('Free Radius (km)', _radiusCtrl, number: true),
          SizedBox(height: pad * 0.5),
          field('Surcharge per km (₹)', _perKmCtrl, number: true),
          SizedBox(height: pad * 0.5),
          area('Cancellation Policy', _policyCtrl),
          SizedBox(height: pad * 0.5),

          // UPDATED: separate fields for 8-type and H-type test charges
          Text(
            'Driving Test Charge — 8 type (₹)',
            style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _testCharge8Ctrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: '8 type charge',
              prefixText: '₹',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.s),
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
            style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
          ),
          SizedBox(height: pad * 0.5),

          Text(
            'Driving Test Charge — H type (₹)',
            style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _testChargeHCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'H type charge',
              prefixText: '₹',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.s),
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
            style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
          ),

          SizedBox(height: pad * 0.5),
          CheckboxListTile(
            value: _drivingTestIncluded,
            onChanged: (val) =>
                setState(() => _drivingTestIncluded = val ?? true),
            title: const Text('Driving Test Included'),
            controlAffinity: ListTileControlAffinity.leading,
          ),

          SizedBox(height: pad * 0.75),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final test8 =
                    double.tryParse(_testCharge8Ctrl.text.trim()) ??
                    _testCharge8;
                final testH =
                    double.tryParse(_testChargeHCtrl.text.trim()) ??
                    _testChargeH;

                await doc.set({
                  'free_radius_km':
                      double.tryParse(_radiusCtrl.text.trim()) ?? 5,
                  'surcharge_per_km':
                      double.tryParse(_perKmCtrl.text.trim()) ?? 10,
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
                    content: Text(
                      'Payment settings saved',
                      style: AppText.tileSubtitle.copyWith(
                        color: AppColors.onSurfaceInverse,
                      ),
                    ),
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
              child: Text(
                'Save Payment Settings',
                style: AppText.tileTitle.copyWith(color: context.c.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Admin Popup upload card ----------------

  Widget _buildAdminPopupCard(double pad, double gap, double radius) {
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
          _title('Admin Popup (Image / Video / PDF)'),
          SizedBox(height: gap * 0.5),
          Text(
            'Upload a one-time popup that will be shown to users after booking/payment. Supported: JPG, PNG, MP4, WEBM, PDF.',
            style: AppText.tileSubtitle.copyWith(
              color: AppColors.onSurfaceMuted,
            ),
          ),
          SizedBox(height: gap),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _popupUploading ? null : _pickPopupFile,
                  icon: Icon(
                    Icons.attach_file,
                    color: AppColors.onSurfaceInverse,
                  ),
                  label: Text(
                    _pickedPopupFile == null ? 'Choose File' : 'Change File',
                    style: AppText.tileSubtitle.copyWith(
                      color: AppColors.onSurfaceInverse,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.c.primary,
                  ),
                ),
              ),
              SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: (_pickedPopupFile == null || _popupUploading)
                    ? null
                    : _uploadPickedPopupSigned,
                icon: Icon(
                  Icons.cloud_upload,
                  color: AppColors.onSurfaceInverse,
                ),
                label: Text(
                  'Upload & Activate',
                  style: AppText.tileSubtitle.copyWith(
                    color: AppColors.onSurfaceInverse,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                ),
              ),
            ],
          ),
          if (_pickedPopupFile != null) ...[
            SizedBox(height: gap * 0.6),
            Row(
              children: [
                Icon(Icons.insert_drive_file, color: AppColors.onSurfaceMuted),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_pickedPopupFile!.name} • ${(_pickedPopupFile!.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                    style: AppText.tileSubtitle,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent popups',
                style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showRecentPopups = !_showRecentPopups),
                icon: Icon(
                  _showRecentPopups ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(_showRecentPopups ? 'Hide' : 'Show'),
              ),
            ],
          ),
          if (_showRecentPopups) SizedBox(height: 8),
          if (_showRecentPopups)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_popups')
                  .orderBy('created_at', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.all(pad),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.c.primary,
                      ),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Text(
                    'No popups yet',
                    style: AppText.tileSubtitle.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  );
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final active = (data['active'] ?? false) as bool;
                    final title = (data['title'] ?? '').toString();
                    final url = (data['url'] ?? '').toString();
                    final type = (data['type'] ?? '').toString();
                    final cloudId = (data['cloudinary_public_id'] ?? '')
                        .toString();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        type == 'image'
                            ? Icons.image
                            : (type == 'video'
                                  ? Icons.videocam
                                  : Icons.picture_as_pdf),
                        color: active
                            ? AppColors.brand
                            : AppColors.onSurfaceMuted,
                      ),
                      title: Text(
                        title.isEmpty ? url.split('/').last : title,
                        style: AppText.tileSubtitle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${type.toUpperCase()} • ${active ? 'ACTIVE' : 'inactive'}',
                        style: AppText.hintSmall.copyWith(
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (choice) async {
                          try {
                            if (choice == 'deactivate') {
                              await d.reference.set({
                                'active': false,
                              }, SetOptions(merge: true));
                            } else if (choice == 'activate') {
                              await _deactivateOtherPopups();
                              await d.reference.set({
                                'active': true,
                              }, SetOptions(merge: true));
                            } else if (choice == 'delete') {
                              await _confirmAndDeletePopup(d);
                            } else if (choice == 'open') {
                              final uri = Uri.tryParse(url);
                              if (uri != null && await canLaunchUrl(uri))
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              else
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not open URL')),
                                );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Action failed: $e'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          if (!active)
                            PopupMenuItem(
                              value: 'activate',
                              child: Text('Activate'),
                            ),
                          if (active)
                            PopupMenuItem(
                              value: 'deactivate',
                              child: Text('Deactivate'),
                            ),
                          PopupMenuItem(value: 'open', child: Text('Open')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                            textStyle: TextStyle(color: AppColors.danger),
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

  // ---------------- Generate Report UI (simplified) ----------------

  Widget _buildGenerateReportCard(double pad, double gap, double radius) {
    final labelStyle = AppText.tileSubtitle.copyWith(
      color: context.c.onSurface,
    );

    Widget _presetButton(String id, String label) {
      final selected = _selectedPreset == id;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedPreset = id),
        selectedColor: context.c.primary.withOpacity(0.14),
        backgroundColor: AppColors.neuBg,
        labelStyle: TextStyle(
          color: selected ? context.c.primary : context.c.onSurface,
        ),
      );
    }

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
          _title('Generate Report'),
          SizedBox(height: gap * 0.4),
          Text(
            'Select period and generate report. (Opens Report page to create PDF.)',
            style: AppText.tileSubtitle.copyWith(
              color: AppColors.onSurfaceMuted,
            ),
          ),
          SizedBox(height: gap),

          Text(
            'Preset ranges',
            style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _presetButton('30D', '30 days'),
              _presetButton('90D', '90 days'),
              _presetButton('6M', '6 months'),
              _presetButton('1Y', '1 year'),
            ],
          ),

          SizedBox(height: gap),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // show computed range text next to the Generate button
              Expanded(
                child: Text(_describeSelectedRange(), style: labelStyle),
              ),
              SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  // Navigate to the ReportPage and pass the selected preset
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ReportPage(initialPreset: _selectedPreset),
                    ),
                  );
                },
                icon: Icon(
                  Icons.open_in_new,
                  color: AppColors.onSurfaceInverse,
                ),
                label: Text(
                  'Open Report',
                  style: AppText.tileSubtitle.copyWith(
                    color: AppColors.onSurfaceInverse,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                ),
              ),
            ],
          ),

          SizedBox(height: gap * 0.6),
          Text(
            'Note: Report page will query Firestore and call your server endpoint to fetch Razorpay totals and generate a PDF.',
            style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  String _describeSelectedRange() {
    final now = DateTime.now();
    final range = _computeRangeMillis(_selectedPreset, now);
    final start = range.item1;
    final end = range.item2;
    return 'From ${_formatDate(start)} to ${_formatDate(end)}';
  }

  // returns (start, end) DateTimes
  Tuple2<DateTime, DateTime> _computeRangeMillis(String preset, DateTime now) {
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    DateTime start;
    switch (preset) {
      case '30D':
        start = end
            .subtract(const Duration(days: 30))
            .copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '90D':
        start = end
            .subtract(const Duration(days: 90))
            .copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '6M':
        // subtracting months safely
        final m = (now.month - 6);
        final year = m <= 0 ? now.year - 1 : now.year;
        final month = m <= 0 ? m + 12 : m;
        // ensure day validity
        final day = now.day.clamp(1, DateUtils.getDaysInMonth(year, month));
        start = DateTime(
          year,
          month,
          day,
        ).copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '1Y':
        start = DateTime(
          now.year - 1,
          now.month,
          now.day,
        ).copyWith(hour: 0, minute: 0, second: 0);
        break;
      default:
        start = end
            .subtract(const Duration(days: 30))
            .copyWith(hour: 0, minute: 0, second: 0);
    }
    return Tuple2(start, end);
  }

  void _onGeneratePressed() {
    final now = DateTime.now();
    final range = _computeRangeMillis(_selectedPreset, now);
    final start = range.item1;
    final end = range.item2;
    final name =
        'report_${_selectedPreset}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Generate requested for ${_selectedPreset}: ${_formatDate(start)} → ${_formatDate(end)} (simulated).',
          style: AppText.tileSubtitle.copyWith(
            color: AppColors.onSurfaceInverse,
          ),
        ),
        backgroundColor: AppColors.warnBg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Generation Requested',
          style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
        ),
        content: Text(
          'Report: $name\nPeriod: ${_formatDate(start)} → ${_formatDate(end)}\n\nThis is a UI-only simulation. Integrate your backend export endpoint to generate the actual file.',
          style: AppText.tileSubtitle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: AppText.tileSubtitle.copyWith(color: context.c.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Vehicles: Add dialogs ----------------

  void _showAddVehicleDialog(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final isDesktop = sw >= 1024;
    final dialogW = sw * (isDesktop ? 0.6 : 0.92);
    final dialogH = sh * (isDesktop ? 0.72 : 0.8);
    final pad = (sw * 0.04).clamp(12.0, 28.0);

    final predefinedVehicles = [
      {
        'type': 'Manual Sedan',
        'description': 'Standard transmission',
        'defaultFee': 500,
      },
      {
        'type': 'Automatic Sedan',
        'description': 'Automatic transmission',
        'defaultFee': 600,
      },
      {
        'type': 'Manual Hatchback',
        'description': 'Compact car with manual transmission',
        'defaultFee': 450,
      },
      {
        'type': 'Automatic Hatchback',
        'description': 'Compact car with automatic transmission',
        'defaultFee': 550,
      },
      {
        'type': 'Manual SUV',
        'description': 'Sports utility vehicle',
        'defaultFee': 700,
      },
      {
        'type': 'Automatic SUV',
        'description': 'Sports utility vehicle',
        'defaultFee': 800,
      },
      {
        'type': 'Motorcycle',
        'description': 'Two wheeler vehicle',
        'defaultFee': 300,
      },
      {
        'type': 'Scooter',
        'description': 'Automatic two wheeler',
        'defaultFee': 250,
      },
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: (sw * 0.04).clamp(12.0, 40.0),
            vertical: (sh * 0.04).clamp(12.0, 40.0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular((sw * 0.02).clamp(8.0, 14.0)),
          ),
          child: SizedBox(
            width: dialogW,
            height: dialogH,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Add Vehicle Type',
                        style: AppText.sectionTitle.copyWith(
                          color: context.c.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: context.c.onSurface),
                      ),
                    ],
                  ),
                  SizedBox(height: pad * 0.75),
                  Text(
                    'Select a vehicle type to add:',
                    style: AppText.tileSubtitle.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
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
                            borderRadius: BorderRadius.circular(
                              (sw * 0.02).clamp(8.0, 14.0),
                            ),
                            child: Container(
                              padding: EdgeInsets.all(pad),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.divider),
                                borderRadius: BorderRadius.circular(
                                  (sw * 0.02).clamp(8.0, 14.0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: iconBox,
                                    height: iconBox,
                                    decoration: BoxDecoration(
                                      color: AppColors.brand.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(
                                        (sw * 0.02).clamp(8.0, 14.0),
                                      ),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: AppColors.brand,
                                      size: iconSize,
                                    ),
                                  ),
                                  SizedBox(width: pad),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          carType,
                                          style: AppText.tileTitle.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: pad * 0.25),
                                        Text(
                                          vehicle['description'] as String,
                                          style: AppText.hintSmall.copyWith(
                                            color: AppColors.onSurfaceMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: AppColors.onSurfaceFaint,
                                    size: 16,
                                  ),
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
    final feeController = TextEditingController(
      text: vehicle['defaultFee'].toString(),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: (sw * 0.06).clamp(16.0, 60.0),
            vertical: (sh * 0.06).clamp(16.0, 60.0),
          ),
          title: Text(
            'Set Fee for ${vehicle['type']}',
            style: AppText.tileTitle.copyWith(color: context.c.onSurface),
          ),
          content: SizedBox(
            width: sw * (isDesktop ? 0.4 : 0.9), // % width
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Fee (₹)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.s),
                    ),
                    prefixText: '₹',
                    labelStyle: AppText.tileSubtitle.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  style: AppText.tileSubtitle.copyWith(
                    color: context.c.onSurface,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: AppText.tileSubtitle.copyWith(color: context.c.primary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final fee =
                    double.tryParse(feeController.text.trim()) ??
                    vehicle['defaultFee'];
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
              style: ElevatedButton.styleFrom(
                backgroundColor: context.c.primary,
                foregroundColor: context.c.onPrimary,
              ),
              child: Text(
                'Add Vehicle',
                style: AppText.tileTitle.copyWith(color: context.c.onPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- Popup helpers: pick, signed upload, destroy ----------------

  Future<void> _pickPopupFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'webm', 'pdf'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      setState(() => _pickedPopupFile = f);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File pick error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // NOTE: keep this helper for internal cleaning when you want to store safe identifiers.
  // We will NOT use it for signing because signature must be calculated on exactly the string
  // the signer expects (no client-side transformation before sending to signer).
  String _clean(String s) =>
      s.replaceAll(RegExp(r'\s+'), '_').replaceAll('/', '_');

  /// Request a signature from your PHP signer.
  /// Simple contract: send public_id, folder, overwrite and get { api_key, timestamp, signature, cloud_name }.
  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    String overwrite = 'false',
  }) async {
    final uri = Uri.parse(_signatureEndpoint);
    final body = {
      'op': 'upload',
      'public_id': publicId,
      'folder': folder,
      'overwrite': overwrite,
    };

    final res = await http.post(uri, body: body);
    if (res.statusCode != 200) {
      throw Exception('Signature server error: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    debugPrint('Signer response: $json'); // remove in prod
    if (json['signature'] == null ||
        json['api_key'] == null ||
        json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

  /// Upload bytes to Cloudinary, using the exact params returned by the signer.
  /// This avoids mismatches between what was signed and what is uploaded.
  /// Upload bytes to Cloudinary using the 'auto' endpoint and the exact params returned by the signer.
  /// Keeps the contract simple: signer provides api_key, timestamp, signature (which were calculated for the
  /// public_id and folder you pass here).
  Future<String> _uploadToCloudinarySigned({
    required Uint8List bytes,
    required String filename,
    required String publicId,
    required String folder,
    String overwrite = 'false',
  }) async {
    final signed = await _getSignature(
      publicId: publicId,
      folder: folder,
      overwrite: overwrite,
    );

    final cloudName = (signed['cloud_name'] ?? '').toString();
    final apiKey = signed['api_key'].toString();
    final timestamp = signed['timestamp'].toString();
    final signature = signed['signature'].toString();

    final endpoint = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
    final req = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['signature'] = signature
      ..fields['public_id'] = publicId
      ..fields['folder'] = folder
      ..fields['overwrite'] = overwrite;

    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    final contentType = _inferMediaType(ext);
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );

    debugPrint('Uploading to Cloudinary (auto): $endpoint');
    debugPrint('Upload fields: ${req.fields}');
    debugPrint('Upload filename: $filename, bytes: ${bytes.lengthInBytes}');

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['secure_url'] as String?) ?? (json['url'] as String);
  }

  MediaType _inferMediaType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webm':
        return MediaType('video', 'webm');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  Future<void> _uploadPickedPopupSigned() async {
    if (_pickedPopupFile == null) return;
    setState(() => _popupUploading = true);

    try {
      final picked = _pickedPopupFile!;
      final filename = picked.name;
      final ext = (picked.extension ?? '').toLowerCase();

      // folder per-day
      final now = DateTime.now();
      final datePart =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final folder = '$_cloudBaseFolder/$datePart';

      // generate safer publicId: base + ts
      final baseName = filename.contains('.')
          ? filename.split('.').first
          : filename;
      final publicId =
          '${_clean(baseName)}_${DateTime.now().millisecondsSinceEpoch}';

      // obtain bytes (web or native)
      late Uint8List bytes;
      if (picked.bytes != null) {
        bytes = picked.bytes!;
      } else if (picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      } else {
        throw Exception('No file bytes available');
      }

      // upload signed — always use auto endpoint (no 'raw' special-case)
      final secureUrl = await _uploadToCloudinarySigned(
        bytes: bytes,
        filename: filename,
        publicId: publicId,
        folder: folder,
        overwrite: 'false', // safer default
      );

      final popupType = _mapCloudinaryTypeFromExt(ext);

      // deactivate others and create doc
      await _deactivateOtherPopups();

      await FirebaseFirestore.instance.collection('admin_popups').add({
        'active': true,
        'url': secureUrl,
        'type': popupType,
        'title': filename,
        'description': '',
        'created_at': FieldValue.serverTimestamp(),
        // store the cloudinary id as folder/publicId (matching what we requested)
        'cloudinary_public_id': '$folder/$publicId',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Popup uploaded & activated'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        _pickedPopupFile = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      setState(() => _popupUploading = false);
    }
  }

  String _mapCloudinaryTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(e)) return 'image';
    if (['mp4', 'webm', 'mov', 'mkv'].contains(e)) return 'video';
    if (['pdf'].contains(e)) return 'pdf';
    return 'image';
  }

  Future<void> _deactivateOtherPopups() async {
    final fs = FirebaseFirestore.instance;
    final q = await fs
        .collection('admin_popups')
        .where('active', isEqualTo: true)
        .get();
    final batch = fs.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'active': false});
    }
    await batch.commit();
  }

  // ---------------- Cloudinary destroy (signed) ----------------
  // Uses signature.php with op=destroy, then calls Cloudinary /destroy endpoint.
  String? _resourceTypeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('/image/upload/')) return 'image';
    if (u.contains('/video/upload/')) return 'video';
    if (u.contains('/raw/upload/')) return 'raw';
    return null;
  }

  String _resourceTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg'].contains(e))
      return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(e)) return 'video';
    return 'raw';
  }

  Future<Map<String, dynamic>> _getSignatureForDestroy({
    required String fullPublicId,
  }) async {
    final uri = Uri.parse(_signatureEndpoint);
    final body = {
      'op': 'destroy',
      'public_id': fullPublicId,
      'invalidate': 'true',
    };
    final res = await http.post(uri, body: body);
    if (res.statusCode != 200) {
      throw Exception('Signature server error: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['signature'] == null ||
        json['api_key'] == null ||
        json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

  Future<String> _cloudinaryDestroyOnce({
    required String fullPublicId,
    required String resourceType, // image|raw|video
    required Map<String, dynamic> signed,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy',
    );

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = signed['api_key'].toString()
      ..fields['timestamp'] = signed['timestamp'].toString()
      ..fields['signature'] = signed['signature'].toString()
      ..fields['public_id'] = fullPublicId
      ..fields['invalidate'] = 'true';

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception(
        'Cloudinary destroy failed: ${streamed.statusCode} $body',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = (json['result'] ?? '').toString();
    return result.isEmpty ? 'error' : result; // 'ok', 'not found', etc.
  }

  // Try primary resource type, then fall back through others if {result: "not found"}
  Future<void> _cloudinaryDestroyWithFallback({
    required String fullPublicId,
    required String primaryType,
  }) async {
    final signed = await _getSignatureForDestroy(fullPublicId: fullPublicId);

    final candidates = <String>[
      primaryType,
      if (primaryType != 'image') 'image',
      if (primaryType != 'raw') 'raw',
      if (primaryType != 'video') 'video',
    ];

    for (final t in candidates) {
      final result = await _cloudinaryDestroyOnce(
        fullPublicId: fullPublicId,
        resourceType: t,
        signed: signed,
      );
      if (result == 'ok') return; // success
      if (result != 'not found') {
        // Any other result -> stop and throw
        throw Exception('Cloudinary destroy unexpected result: $result');
      }
      // else continue to next candidate
    }
    throw Exception(
      'Cloudinary destroy did not find the asset under any resource_type.',
    );
  }

  /// Delete an admin_popup document and its Cloudinary asset (if present).
  /// Shows confirmation dialog and a modal progress indicator while deleting (no persistent snackbar).
  /// Tries stored cloudinary_public_id, then fallbacks (last segment, folder/publicId, cleaned).
  Future<void> _confirmAndDeletePopup(DocumentSnapshot docSnap) async {
    final docRef = docSnap.reference;
    final data = docSnap.data() as Map<String, dynamic>? ?? {};
    final storedCloudId = (data['cloudinary_public_id'] ?? '')
        .toString()
        .trim();
    final storedFolder = (data['cloudinary_folder'] ?? '').toString().trim();
    final title = (data['title'] ?? docSnap.id).toString();
    final fileUrl = (data['url'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete popup',
          style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
        ),
        content: Text(
          'Delete \"$title\"? This will remove the Firestore record and the Cloudinary asset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppText.tileSubtitle.copyWith(color: context.c.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(
              'Delete',
              style: AppText.tileTitle.copyWith(
                color: AppColors.onSurfaceInverse,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // ── DELETION UI FIX ──
    // Use a modal progress dialog instead of an indefinite SnackBar.
    void _showProgressDialog() {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(context.c.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Deleting...',
                      style: AppText.tileSubtitle.copyWith(
                        color: context.c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Future<void> _deleteDocOnly() async {
      await docRef.delete();
      // ensure any progress dialog is closed
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Popup deleted',
            style: AppText.tileSubtitle.copyWith(
              color: AppColors.onSurfaceInverse,
            ),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }

    try {
      // show modal progress
      _showProgressDialog();

      if (storedCloudId.isEmpty) {
        await _deleteDocOnly();
        return;
      }

      // Build candidate list (try stored first, then fallbacks)
      final candidates = <String>[];
      candidates.add(storedCloudId);

      // If storedCloudId has slashes, try last segment
      if (storedCloudId.contains('/')) {
        final parts = storedCloudId.split('/');
        final last = parts.isNotEmpty ? parts.last : storedCloudId;
        if (last.isNotEmpty && last != storedCloudId) candidates.add(last);
      } else {
        // storedCloudId is just a name — if folder exists, try folder/publicId
        if (storedFolder.isNotEmpty)
          candidates.add(
            '${storedFolder.replaceAll(RegExp(r'\/$'), '')}/$storedCloudId',
          );
      }

      // cleaned variant (spaces -> underscores)
      final cleaned = storedCloudId.replaceAll(' ', '_');
      if (cleaned != storedCloudId) candidates.add(cleaned);

      // Map popup type -> resource_type for initial detection (image, video => video, else raw)
      final popupType = (data['type'] ?? '').toString().toLowerCase();
      String primaryFromType = (popupType == 'image')
          ? 'image'
          : (popupType == 'video')
          ? 'video'
          : 'raw';

      // But prefer detection from stored URL if available
      final detectedFromUrl = _resourceTypeFromUrl(fileUrl);
      final primaryType = detectedFromUrl ?? primaryFromType;

      Exception? lastError;
      for (final cand in candidates) {
        try {
          await _cloudinaryDestroyWithFallback(
            fullPublicId: cand,
            primaryType: primaryType,
          );
          // success — remove doc
          await _deleteDocOnly();
          return;
        } catch (e) {
          debugPrint('Delete attempt failed for "$cand": $e');
          lastError = e is Exception ? e : Exception(e.toString());
        }
      }

      // If we reach here none of the attempts worked
      throw lastError ??
          Exception('All delete attempts failed for stored id: $storedCloudId');
    } catch (e) {
      // ensure progress dialog is closed
      if (Navigator.canPop(context)) Navigator.pop(context);

      // Offer to delete Firestore doc anyway (if Cloudinary deletion failed)
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            'Delete failed',
            style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
          ),
          content: Text(
            'Could not delete Cloudinary asset: $e\n\nDelete Firestore record only?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppText.tileSubtitle.copyWith(color: context.c.primary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: Text(
                'Delete doc only',
                style: AppText.tileTitle.copyWith(
                  color: AppColors.onSurfaceInverse,
                ),
              ),
            ),
          ],
        ),
      );

      if (proceed == true) {
        await docRef.delete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Popup record deleted (Cloud asset may still exist)',
              style: AppText.tileSubtitle,
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Delete failed: $e',
              style: AppText.tileSubtitle.copyWith(color: AppColors.danger),
            ),
          ),
        );
      }
    }
  }

  // ---------------- Logout logic ----------------

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
                    title: Text(
                      'Logout',
                      style: AppText.tileTitle.copyWith(
                        color: context.c.onSurface,
                      ),
                    ),
                    content: Text(
                      'Are you sure you want to logout?',
                      style: AppText.tileSubtitle.copyWith(
                        color: context.c.onSurface,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: AppText.tileSubtitle.copyWith(
                            color: context.c.primary,
                          ),
                        ),
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
                        child: Text(
                          'Logout',
                          style: AppText.tileTitle.copyWith(
                            color: AppColors.onSurfaceInverse,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.logout, color: AppColors.onSurfaceInverse),
              label: Text(
                'Logout',
                style: AppText.tileTitle.copyWith(
                  color: AppColors.onSurfaceInverse,
                ),
              ),
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

  Future<void> _logout({bool wipeAllPrefs = false}) async {
    try {
      // 1) Stop role/status notifications (set alsoAll: true to silence everything)
      await unsubscribeRoleStatusTopics(alsoAll: false);

      // 2) Clear saved session
      await SessionService().clear(); // removes userId/role,status

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
        SnackBar(
          content: Text(
            'Error logging out: $e',
            style: AppText.tileSubtitle.copyWith(color: AppColors.danger),
          ),
        ),
      );
    }
  }

  // ---------------- Utils ----------------

  Text _title(String s) => Text(
    s,
    style: AppText.sectionTitle.copyWith(
      color: context.c.onSurface,
      fontWeight: FontWeight.bold,
    ),
  );

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

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

/// Small utility tuple to return start/end from _computeRangeMillis
class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}
