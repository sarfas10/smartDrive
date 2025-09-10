// lib/plans_view.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:smart_drive/theme/app_theme.dart';

// PUBLIC key via --dart-define
const String _razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
// Hostinger endpoints (same as you use)
const String _hostingerBase = 'https://tajdrivingschool.in/smartDrive/payments';

class PlansView extends StatefulWidget {
  const PlansView({super.key});

  @override
  State<PlansView> createState() => _PlansViewState();
}

class _LatLng {
  final double latitude;
  final double longitude;
  const _LatLng(this.latitude, this.longitude);
}

class _PlansViewState extends State<PlansView> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Razorpay? _razorpay;
  String? _lastOrderId;
  String? _pendingPlanId;
  int _pendingAmountPaise = 0;

  User? _user;
  bool _isLoading = true;
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _currentPlan;
  int _currentPlanSlots = 0;
  int _currentSlotsUsed = 0;
  bool _currentPlanIsPPU = false;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _initRazorpay();
    _loadAll();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      setState(() => _isLoading = true);
      await Future.wait([_loadAvailablePlans(), _loadCurrentPlan()]);
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAvailablePlans() async {
    try {
      Query query = _firestore.collection('plans');
      try {
        query = query.orderBy('price');
      } catch (_) {}
      final snap = await query.get();
      _plans = snap.docs.map((d) {
        final m = d.data() as Map<String, dynamic>;
        return {'id': d.id, ...m};
      }).toList();
    } catch (e) {
      _plans = [];
    }
  }

  Future<void> _loadCurrentPlan() async {
    try {
      final uid = _user?.uid;
      if (uid == null) {
        _currentPlan = null;
        _currentPlanSlots = 0;
        _currentSlotsUsed = 0;
        _currentPlanIsPPU = false;
        return;
      }
      final upDoc = await _firestore.collection('user_plans').doc(uid).get();
      if (!upDoc.exists) {
        _currentPlan = null;
        _currentPlanSlots = 0;
        _currentSlotsUsed = 0;
        _currentPlanIsPPU = false;
        return;
      }
      final up = upDoc.data() as Map<String, dynamic>;
      final planId = (up['planId'] ?? '').toString();
      _currentSlotsUsed = (up['slots_used'] is num) ? (up['slots_used'] as num).toInt() : 0;
      if (planId.isEmpty) {
        _currentPlan = null;
        _currentPlanSlots = 0;
        _currentPlanIsPPU = false;
        return;
      }
      final planDoc = await _firestore.collection('plans').doc(planId).get();
      if (!planDoc.exists || planDoc.data() == null) {
        _currentPlan = null;
        _currentPlanSlots = 0;
        _currentPlanIsPPU = false;
        return;
      }
      final p = planDoc.data()!;
      _currentPlan = {'id': planDoc.id, ...p};
      _currentPlanSlots = (p['slots'] is num) ? (p['slots'] as num).toInt() : 0;
      _currentPlanIsPPU = (p['isPayPerUse'] == true);
    } catch (e) {
      _currentPlan = null;
      _currentPlanSlots = 0;
      _currentPlanIsPPU = false;
      _currentSlotsUsed = 0;
    }
  }

  // -------------------- Razorpay server helpers --------------------
  Future<Map<String, dynamic>> _postJson(String url, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) throw Exception('Invalid JSON');
    return data;
  }

  Future<String> _createOrderOnServer({
    required int amountPaise,
    required String planId,
  }) async {
    final res = await _postJson(
      '$_hostingerBase/createOrder.php',
      {
        'amountPaise': amountPaise,
        'receipt': 'plan_${planId}_${DateTime.now().millisecondsSinceEpoch}',
        'notes': {
          'planId': planId,
          'userId': _user?.uid ?? '',
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

  // -------------------- Payment flow --------------------
  Future<void> _startPayment({
    required String planId,
    required int amountPaise,
    required String planName,
  }) async {
    if (_razorpay == null) {
      _showError('Payment unavailable');
      return;
    }
    if (_razorpayKeyId.isEmpty) {
      _showError('Razorpay key missing. Pass --dart-define=RAZORPAY_KEY_ID=your_key');
      return;
    }

    _pendingPlanId = planId;
    _pendingAmountPaise = amountPaise;

    try {
      _lastOrderId = await _createOrderOnServer(amountPaise: amountPaise, planId: planId);

      final options = {
        'key': _razorpayKeyId,
        'order_id': _lastOrderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': '',
        'description': planName,
        'image': '',
        'prefill': {'contact': '', 'email': '', 'name': ''},
        'config': {
          'display': {
            'hide': [
              {'method': 'emi'},
              {'method': 'wallet'},
              {'method': 'paylater'},
            ],
          }
        },
        'theme': {'color': '#6A1B9A'},
        'timeout': 300,
      };

      _razorpay!.open(options);
    } catch (e) {
      _showError('Could not start payment: $e');
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    if (r.orderId == null || r.paymentId == null || r.signature == null) {
      _showError('Payment response incomplete.');
      return;
    }
    if (_pendingPlanId == null || _pendingAmountPaise <= 0) {
      _showError('No pending plan to upgrade.');
      return;
    }

    bool valid = false;
    try {
      valid = await _verifyPaymentOnServer(
        razorpayOrderId: r.orderId!,
        razorpayPaymentId: r.paymentId!,
        razorpaySignature: r.signature!,
        expectedAmountPaise: _pendingAmountPaise,
      );
    } catch (e) {
      _showError('Verification error: $e');
      return;
    }

    if (!valid) {
      _showError('Payment verification failed. Contact support.');
      return;
    }

    // apply plan
    try {
      await _applyPlanToUser(_pendingPlanId!);

      // log purchase
      await _firestore.collection('plan_purchases').add({
        'user_id': _user?.uid,
        'plan_id': _pendingPlanId,
        'amount': _pendingAmountPaise / 100.0,
        'currency': 'INR',
        'razorpay_order_id': r.orderId,
        'razorpay_payment_id': r.paymentId,
        'razorpay_signature': r.signature,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    _showSuccess('Plan upgraded successfully');
    _pendingPlanId = null;
    _pendingAmountPaise = 0;
    _lastOrderId = null;

    await _loadCurrentPlan();
    if (mounted) setState(() {});
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final msg = r.message?.toString().trim();
    _showError('Payment failed${msg != null && msg.isNotEmpty ? ':\n$msg' : ''}');
    // log failed
    _firestore.collection('plan_purchases').add({
      'user_id': _user?.uid,
      'plan_id': _pendingPlanId,
      'status': 'failed',
      'code': r.code,
      'message': r.message,
      'order_id': _lastOrderId,
      'created_at': FieldValue.serverTimestamp(),
    });
    _pendingPlanId = null;
    _pendingAmountPaise = 0;
    _lastOrderId = null;
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _showSuccess('External wallet: ${r.walletName ?? ''}');
  }

  // Apply plan on server (update user_plans/{uid}) and reset slots_used to 0
  Future<void> _applyPlanToUser(String planId) async {
    final uid = _user?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final ref = _firestore.collection('user_plans').doc(uid);

    // Use set with merge to avoid exceptions if the doc does not exist.
    await ref.set({
      'planId': planId,
      'isActive': true,
      'active': true,
      'startDate': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // Reset used slots when plan changes (upgrade/downgrade)
      'slots_used': 0,
    }, SetOptions(merge: true));
  }

  // -------------------- UI helpers --------------------
  void _showError(String msg) {
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Error'), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------- Boarding & pickup extra calculation --------------------
  Future<_LatLng?> _fetchUserBoardingPoint() async {
    try {
      final uid = _user?.uid;
      if (uid == null) return null;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (data == null) return null;
      final b = data['boarding'];
      if (b is Map<String, dynamic>) {
        final lat = (b['latitude'] as num?)?.toDouble();
        final lng = (b['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) return _LatLng(lat, lng);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<_LatLng?> _fetchOfficePoint() async {
    try {
      final doc = await _firestore.collection('settings').doc('app_settings').get();
      final data = doc.data();
      if (data == null) return null;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) return _LatLng(lat, lng);
      return null;
    } catch (_) {
      return null;
    }
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double d) => d * (math.pi / 180.0);

  // -------------------- Present purchase UI & compute totals --------------------
  Future<void> _presentPurchaseSummary(Map<String, dynamic> plan) async {
    final planId = (plan['id'] ?? '').toString();
    if (planId.isEmpty) {
      _showError('Invalid plan selected');
      return;
    }

    // warn about unused slots (if current plan is not PPU)
    final bool hasUnusedSlotsToLose = !_currentPlanIsPPU && _currentPlanSlots > 0 && _currentSlotsUsed < _currentPlanSlots;
    if (hasUnusedSlotsToLose) {
      final remaining = _currentPlanSlots - _currentSlotsUsed;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Unused Slots Remaining'),
          content: Text('You still have $remaining slot(s) left in your current plan. Upgrading now will forfeit them. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Current')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final String planName = (plan['name'] ?? planId).toString();
    final num planPriceNum = (plan['price'] is num) ? (plan['price'] as num) : 0;
    final bool isPPU = plan['isPayPerUse'] == true;

    // pickup/surcharge flags from plan
    final bool freePickupRadius = plan['freePickupRadius'] == true;
    final int freeRadiusKm = freePickupRadius ? ((plan['freeRadius'] ?? 0) as num).toInt() : 0;
    final bool extraKmSurcharge = plan['extraKmSurcharge'] == true;
    final int surchargePerKm = extraKmSurcharge ? ((plan['surcharge'] ?? 0) as num).toInt() : 0;

    // IMPORTANT: For Pay-Per-Use plans do NOT charge additional costs.
    // Ignore pickup and extra-km surcharge for PPU plans entirely.
    final bool chargePickupOrSurcharge = !isPPU && (freePickupRadius || extraKmSurcharge);

    // get distances (if boarding exists and charging is enabled)
    final _LatLng? userBoarding = await _fetchUserBoardingPoint();
    final _LatLng? officePoint = await _fetchOfficePoint();

    if (!isPPU && userBoarding == null) {
      // Ask user to set boarding point — offer to open profile/boarding page
      await showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Boarding Point Required'),
        content: const Text('Please set your boarding point in your profile to calculate pickup charges.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ));
      return;
    }
    if (!isPPU && officePoint == null) {
      _showError('Office coordinates not configured. Contact admin.');
      return;
    }

    double distanceKm = 0.0;
    if (!isPPU && userBoarding != null && officePoint != null) {
      distanceKm = _haversineKm(userBoarding.latitude, userBoarding.longitude, officePoint.latitude, officePoint.longitude);
    }

    int additionalCharge = 0;
    int billableKm = 0;
    if (!isPPU && extraKmSurcharge) {
      final double extra = math.max(0.0, distanceKm - freeRadiusKm);
      billableKm = extra.ceil();
      additionalCharge = billableKm * surchargePerKm;
    } else {
      // ensure no extra charge for PPU
      additionalCharge = 0;
    }

    final int planPrice = planPriceNum.round();
    final int total = planPrice + additionalCharge;

    // present summary
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Purchase: $planName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line('Plan price', '₹$planPrice'),
            if (!isPPU) _line('Distance to office', '${distanceKm.toStringAsFixed(2)} km'),
            if (!isPPU && freePickupRadius) _line('Free pickup radius', '$freeRadiusKm km'),
            if (!isPPU && extraKmSurcharge) _line('Surcharge per km', '₹$surchargePerKm'),
            if (!isPPU && extraKmSurcharge) _line('Billable km', '$billableKm km'),
            if (!isPPU && extraKmSurcharge) _line('Additional charge', '₹$additionalCharge'),
            if (isPPU) const SizedBox(height: 6),
            const Divider(),
            _line('Total', '₹$total'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm & Pay')),
        ],
      ),
    );

    if (confirm != true) return;

    if (total <= 0) {
      // free or zero → directly apply
      try {
        await _applyPlanToUser(planId);
        _showSuccess('Plan applied successfully');
        await _loadCurrentPlan();
        setState(() {});
      } catch (e) {
        _showError('Error applying plan: $e');
      }
    } else {
      final paise = total * 100;
      await _startPayment(planId: planId, amountPaise: paise, planName: planName);
    }
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text(label)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]),
    );
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    // Use app theme background and surface tokens
    final bg = AppColors.background;
    final surface = AppColors.surface;
    final textOnSurface = AppColors.onSurface;
    final secondaryText = AppColors.onSurfaceMuted;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Choose Your Plan'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    // informational banner (uses tokens)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.warnBg,
                        borderRadius: BorderRadius.circular(AppRadii.m),
                        border: Border.all(color: AppColors.warnFg.withOpacity(0.18)),
                      ),
                      child: Text(
                        'Note: Additional boarding charges may apply if your boarding point is outside the free pickup radius defined in your plan.',
                        style: AppText.tileSubtitle.copyWith(color: AppColors.warnFg, fontWeight: FontWeight.w600),
                      ),
                    ),

                    // subtitle
                    Text(
                      'Unlock more features and grow your potential',
                      style: AppText.tileSubtitle.copyWith(color: secondaryText),
                    ),
                    const SizedBox(height: 12),

                    // list of plans
                    Expanded(
                      child: _plans.isEmpty
                          ? Center(child: Text('No plans available', style: AppText.tileTitle.copyWith(color: textOnSurface)))
                          : ListView.builder(
                              itemCount: _plans.length,
                              itemBuilder: (context, i) {
                                final plan = _plans[i];
                                final id = plan['id'] ?? '';
                                final name = (plan['name'] ?? id).toString();
                                final price = plan['price'];
                                final slots = (plan['slots'] is num) ? (plan['slots'] as num).toInt() : 0;
                                final isPPU = plan['isPayPerUse'] == true;
                                final extraKm = plan['extraKmSurcharge'] == true;
                                final surcharge = (plan['surcharge'] is num) ? (plan['surcharge'] as num).toInt() : 0;
                                final freePickup = plan['freePickupRadius'] == true;
                                final freeRadius = (plan['freeRadius'] is num) ? (plan['freeRadius'] as num).toInt() : 0;
                                final drivingTestIncluded = plan['driving_test_included'] != false;

                                final isCurrent = _currentPlan?['id'] == id;

                                // Card content uses design tokens for color, radius, shadow
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(AppRadii.l),
                                    boxShadow: AppShadows.card,
                                    border: Border.all(color: AppColors.divider),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: AppText.tileTitle.copyWith(color: textOnSurface, fontSize: 18, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            if (isCurrent)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: AppColors.okBg,
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(color: AppColors.okBg),
                                                ),
                                                child: Text('Current', style: AppText.tileSubtitle.copyWith(color: AppColors.okFg, fontWeight: FontWeight.w700)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          isPPU ? 'Pay per session' : (price is num ? '₹${(price as num).toStringAsFixed(0)}' : '₹—'),
                                          style: AppText.tileTitle.copyWith(color: AppColors.slate, fontSize: 20, fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            if (!isPPU) _pill(Icons.event_available, '$slots slots'),
                                            if (isPPU) _pill(Icons.flash_on, 'Pay-Per-Use'),
                                            if (extraKm && !isPPU) _pill(Icons.local_gas_station, '₹$surcharge / km'),
                                            if (freePickup && !isPPU) _pill(Icons.location_on, '$freeRadius km pickup'),
                                            if (drivingTestIncluded) _pill(Icons.verified_user, 'Driving test included'),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () => _showPlanDetails(plan),
                                              style: TextButton.styleFrom(
                                                foregroundColor: AppColors.onSurfaceMuted,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              ),
                                              child: Text('Details', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                                            ),
                                            const SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed: isCurrent ? null : () => _presentPurchaseSummary(plan),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isCurrent ? AppColors.neuBg : Theme.of(context).colorScheme.primary,
                                                foregroundColor: isCurrent ? AppColors.neuFg : Theme.of(context).colorScheme.onPrimary,
                                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                                                elevation: isCurrent ? 0 : 4,
                                              ),
                                              child: Text(isCurrent ? 'Selected' : 'Select', style: AppText.tileTitle.copyWith(color: isCurrent ? AppColors.neuFg : Theme.of(context).colorScheme.onPrimary)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'All plans include support. Boarding pickup beyond free radius may incur charges as described above.',
                      style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.neuBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.onSurfaceFaint),
          const SizedBox(width: 6),
          Text(label, style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint)),
        ],
      ),
    );
  }

  void _showPlanDetails(Map<String, dynamic> plan) {
    final name = (plan['name'] ?? plan['id']).toString();
    final desc = (plan['description'] ?? '').toString();
    final price = plan['price'];
    final slots = (plan['slots'] is num) ? (plan['slots'] as num).toInt() : 0;
    final isPPU = plan['isPayPerUse'] == true;
    final extraKm = plan['extraKmSurcharge'] == true;
    final surcharge = (plan['surcharge'] is num) ? (plan['surcharge'] as num).toInt() : 0;
    final freePickup = plan['freePickupRadius'] == true;
    final freeRadius = (plan['freeRadius'] is num) ? (plan['freeRadius'] as num).toInt() : 0;
    final drivingTestIncluded = plan['driving_test_included'] != false;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desc.isNotEmpty) Text(desc),
              const SizedBox(height: 8),
              Text('Price: ${isPPU ? "Pay as you go" : "₹$price"}'),
              if (!isPPU) Text('Slots: $slots'),
              const SizedBox(height: 8),
              if (extraKm && !isPPU) Text('Extra KM surcharge: ₹$surcharge / km'),
              if (freePickup && !isPPU) Text('Free pickup radius: $freeRadius km'),
              Text('Driving test included: ${drivingTestIncluded ? "Yes" : "No"}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _presentPurchaseSummary(plan);
            },
            child: const Text('Choose this plan'),
          ),
        ],
      ),
    );
  }
}
