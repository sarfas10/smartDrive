// lib/student_dashboard.dart
import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_drive/downloadables.dart';
import 'package:smart_drive/learners_application_page.dart';
import 'package:smart_drive/upload_document_page.dart';
import 'package:smart_drive/onboarding_forms.dart';
import 'package:smart_drive/UserAttendancePanel.dart';
import 'package:smart_drive/mock_tests_list_page.dart';
import 'package:smart_drive/user_materials_page.dart';
import 'package:smart_drive/user_settings.dart';
import 'package:smart_drive/user_slot_booking.dart';
import 'package:smart_drive/test_booking_page.dart';
import 'package:smart_drive/plans_view.dart';
import 'package:url_launcher/url_launcher.dart';

// THEME
import 'package:smart_drive/theme/app_theme.dart';

/// ───────────────────────── Background grain painter ─────────────────────
class _GrainPainter extends CustomPainter {
  final double opacity;
  _GrainPainter({this.opacity = 0.06});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final dotPaint = Paint()..color = Colors.white.withOpacity(opacity);
    final count = (size.width * size.height / 220).toInt();
    for (int i = 0; i < count; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() * 0.8 + 0.2;
      canvas.drawCircle(Offset(dx, dy), r, dotPaint);
    }
    final brush = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white24, Colors.transparent, Colors.white12],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size)
      ..blendMode = BlendMode.overlay
      ..color = Colors.white.withOpacity(opacity * 0.5);
    canvas.drawRect(Offset.zero & size, brush);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});
  @override
  _StudentDashboardState createState() => _StudentDashboardState();
}

/// NOTE: mixin WidgetsBindingObserver to detect app lifecycle resume,
/// and RouteAware to detect navigator route events (pop/push).
class _StudentDashboardState extends State<StudentDashboard>
    with WidgetsBindingObserver, RouteAware {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String userStatus = '';
  Map<String, dynamic> userData = {};
  bool isLoading = true;

  // local hide flag for onboarding banner (not persisted)
  bool _hideOnboardingBanner = false;

  // local hide flag for license banner (not persisted)
  bool _hideLicenseBanner = false;

  // whether the user has either a learner or license recorded (from user_profiles)
  bool _hasDrivingDocument = false;

  // RouteObserver found in Navigator observers (if any)
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  ModalRoute<dynamic>? _modalRoute;

  // Realtime subscription to user_profiles doc
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserData(); // initial read
    _ensureProfileListener(); // create realtime listener
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Try to find a RouteObserver in the current Navigator observers and subscribe
    // so we can detect when this route becomes visible again (didPopNext).
    // This will work if your MaterialApp/WidgetsApp has a RouteObserver in its observers.
    try {
      _modalRoute = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      final obs = navigator.widget.observers;
      for (final o in obs) {
        if (o is RouteObserver<ModalRoute<dynamic>>) {
          _routeObserver = o;
          break;
        }
      }
      if (_routeObserver != null && _modalRoute != null) {
        // subscribe safely (avoid double-subscribe)
        _routeObserver!.unsubscribe(this);
        _routeObserver!.subscribe(this, _modalRoute as PageRoute<dynamic>);
      }
    } catch (e) {
      // ignore - best-effort subscription
      debugPrint('RouteObserver subscription failed: $e');
    }

    // Also refresh user data whenever dependencies change (best-effort)
    _fetchUserData();
    _ensureProfileListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_routeObserver != null) {
        _routeObserver!.unsubscribe(this);
      }
    } catch (_) {}
    _profileSub?.cancel();
    super.dispose();
  }

  // Called when app lifecycle changes (e.g., resumed from background)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // re-fetch user data and re-check listener when app is foregrounded
      _fetchUserData();
      _ensureProfileListener();
    }
  }

  // RouteAware callbacks (if subscribed)
  @override
  void didPush() {
    // Route was pushed onto navigator: a fresh view - refresh
    _fetchUserData();
    _ensureProfileListener();
  }

  @override
  void didPopNext() {
    // Returned to this route (another route was popped) - refresh
    _fetchUserData();
    _ensureProfileListener();
  }

  @override
  void didPushNext() {
    // Another route pushed above this one - nothing needed
  }

  @override
  void didPop() {
    // This route was popped - nothing needed
  }

  /// Ensure there's an active realtime listener on user_profiles/{uid}.
  /// This immediately updates `_hasDrivingDocument` when the Firestore doc changes.
  void _ensureProfileListener() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // cancel existing subscription if user logged out
      _profileSub?.cancel();
      _profileSub = null;
      return;
    }

    // Cancel any existing and re-subscribe (safe)
    _profileSub?.cancel();
    _profileSub = _firestore
        .collection('user_profiles')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      try {
        final Map<String, dynamic>? prof = snap.data();
        final isLearner = (prof?['is_learner_holder'] as bool?) ?? false;
        final isLicense = (prof?['is_license_holder'] as bool?) ?? false;
        final hasDoc = isLearner || isLicense;

        // Optionally pick up photo_url changes into userData (so UI updates faster)
        final photo = (prof?['photo_url'] as String?)?.trim();

        if (mounted) {
          setState(() {
            _hasDrivingDocument = hasDoc;
            // Keep a lightweight copy of some profile fields if present
            if (photo != null && photo.isNotEmpty) {
              userData = {...userData, 'photo_url': photo};
            }
            isLoading = false;
          });
        }
        debugPrint(
            'PROFILE LISTENER: uid=$uid isLearner=$isLearner isLicense=$isLicense hasDoc=$hasDoc');
      } catch (e, st) {
        debugPrint('PROFILE LISTENER error: $e\n$st');
      }
    }, onError: (err) {
      debugPrint('PROFILE LISTENER failed: $err');
    });
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            userData = (doc.data() as Map<String, dynamic>?) ?? {};
            userStatus = (userData['status'] ?? 'pending').toString();
          });
        } else {
          setState(() => isLoading = false);
        }

        // --- ALWAYS: read user_profiles to detect learner/license flags as a fallback ---
        try {
          final profSnap =
              await _firestore.collection('user_profiles').doc(user.uid).get();
          bool hasDoc = false;
          if (profSnap.exists) {
            final prof = (profSnap.data() as Map<String, dynamic>?) ?? {};
            final isLearner = (prof['is_learner_holder'] as bool?) ?? false;
            final isLicense = (prof['is_license_holder'] as bool?) ?? false;
            hasDoc = isLearner || isLicense;
          }
          if (mounted) {
            setState(() {
              _hasDrivingDocument = hasDoc;
              isLoading = false;
            });
          }
        } catch (e) {
          debugPrint('Error fetching user_profiles (one-time): $e');
          if (mounted) {
            setState(() {
              _hasDrivingDocument = false;
              isLoading = false;
            });
          }
        }

        // Make sure the realtime listener is active
        _ensureProfileListener();
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // photo stream from user_profiles/{uid}.photo_url
  Stream<String?> _photoUrlStream(String uid) {
    return _firestore
        .collection('user_profiles')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['photo_url'] as String?)?.trim())
        .distinct();
  }

  // planId stream from user_plans/{uid}.planId (shown as-is)
  Stream<String?> _planIdStream(String uid) {
    return _firestore
        .collection('user_plans')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['planId'] as String?)?.toString())
        .distinct();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final uid = _auth.currentUser?.uid;
    final role = (userData['role'] ?? 'student').toString();
    final bool isBlocked = userStatus.toLowerCase() == 'blocked';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Pinned top bar
            SliverAppBar(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.onSurface,
              pinned: true,
              elevation: 0,
              title: const Text('Student Dashboard'),
              actions: [
                if (uid != null)
                  NotificationBell(
                    uid: uid,
                    role: role.toLowerCase(),
                    userStatus: userStatus.toLowerCase(),
                  ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _navigateToSettings,
                ),
                const SizedBox(width: 8),
              ],
            ),

            // ── Name card with photo + planId string (live)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Builder(
                  builder: (_) {
                    if (uid == null) {
                      return _NameCard(
                        name: (userData['name'] ?? 'Student').toString(),
                        email: (userData['email'] ?? '').toString(),
                        role: role,
                        photoUrl: null,
                        planIdString: null,
                        isBlocked: isBlocked,
                      );
                    }
                    return StreamBuilder<String?>(
                      stream: _photoUrlStream(uid),
                      builder: (context, photoSnap) {
                        final photoUrl = photoSnap.data;
                        return StreamBuilder<String?>(
                          stream: _planIdStream(uid),
                          builder: (context, planSnap) {
                            final planId = planSnap.data;
                            return _NameCard(
                              name: (userData['name'] ?? 'Student').toString(),
                              email: (userData['email'] ?? '').toString(),
                              role: role,
                              photoUrl: photoUrl,
                              planIdString: planId,
                              isBlocked: isBlocked,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // ── Onboarding / Blocked banner (shown for pending users or blocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    if (!_hideOnboardingBanner && isBlocked) _blockedBanner(),
                    if (!_hideOnboardingBanner &&
                        !isBlocked &&
                        userStatus.toLowerCase() == 'pending')
                      _onboardingBanner(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Quick Actions (primary tiles will be restricted when blocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Quick Actions'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.calendar_month,
                            color: AppColors.warning,
                            title: 'Book Slot',
                            onTap: _navigateToSlotBooking,
                            // require either learner or license AND not blocked
                            enabled: !isBlocked && _hasDrivingDocument,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.access_time,
                            color: AppColors.accentTeal,
                            title: 'Attendance Tracker',
                            onTap: _navigateToAttendance,
                            enabled: !isBlocked,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.menu_book,
                            color: AppColors.info,
                            title: 'Study Materials',
                            onTap: _navigateToStudyMaterials,
                            enabled: !isBlocked,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.book_online,
                            color: AppColors.purple,
                            title: 'Test Booking',
                            onTap: _navigateToTestBooking,
                            // require either learner or license AND not blocked
                            enabled: !isBlocked && _hasDrivingDocument,
                          ),
                        ),
                      ],
                    ),

                    // NEW: license unlock banner (dismissible locally)
                    if (!isBlocked && !_hasDrivingDocument && !_hideLicenseBanner)
                      const SizedBox(height: 12),
                    if (!isBlocked && !_hasDrivingDocument && !_hideLicenseBanner)
                      _licenseUnlockBanner(),

                    if (!isBlocked && !_hasDrivingDocument && _hideLicenseBanner)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'To book slots or tests you must add a learner or license in onboarding.',
                          style: AppText.tileSubtitle,
                        ),
                      ),

                    if (isBlocked) const SizedBox(height: 12),
                    if (isBlocked)
                      Text(
                        'Your account is blocked — primary features are restricted.',
                        style: AppText.tileSubtitle,
                      ),
                  ],
                ),
              ),
            ),

            // ── More options
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('More Options'),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.upload_file_rounded,
                      iconColor: AppColors.primary,
                      title: 'Upload Documents',
                      subtitle: 'Add or manage KYC and other files',
                      onTap: _navigateToUploadDocuments,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.download_rounded,
                      iconColor: AppColors.slate,
                      title: 'Downloadables',
                      subtitle: 'Forms, PDFs, guides & resources',
                      onTap: _navigateToDownloadables,
                    ),
                    const SizedBox(height: 12),
                    // NEW: Apply Learners (secondary feature as requested)
                    _ActionTile(
                      icon: Icons.how_to_reg,
                      iconColor: AppColors.brand,
                      title: 'Apply Learner',
                      subtitle: 'Apply for learner license / start application',
                      onTap: () {
                        // Reuse onboarding flow for learner application
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LearnersApplicationPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // Moved: Questionaries (was Mock Tests)
                    _ActionTile(
                      icon: Icons.quiz,
                      iconColor: AppColors.purple,
                      title: 'Questionaries',
                      subtitle:
                          'Attempt practice questionnaires and previous tests',
                      onTap: _navigateToQuestionaries,
                    ),
                  ],
                ),
              ),
            ),
            // ── Contact Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _SectionTitle('Contact Us'),
                    SizedBox(height: 12),
                    _ContactTile(
                      phone: '+91 98765 43210',
                      email: 'support@smartdrive.com',
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ── Navigation hooks
  void _navigateToSlotBooking() {
    final isBlocked = userStatus.toLowerCase() == 'blocked';
    if (isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account is blocked. Contact support.')),
      );
      return;
    }
    if (!_hasDrivingDocument) {
      // Encourage user to complete onboarding
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Please complete onboarding (add learner or license) to book a slot.'),
          action: SnackBarAction(
            label: 'Complete',
            onPressed: _navigateToCompleteOnboarding,
          ),
        ),
      );
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const UserSlotBooking()));
  }

  void _navigateToStudyMaterials() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const UserMaterialsPage()));
  }

  void _navigateToMockTests() {
    // kept for backward compatibility
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MockTestsListPage()));
  }

  void _navigateToQuestionaries() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MockTestsListPage()));
  }

  void _navigateToTestBooking() {
    final isBlocked = userStatus.toLowerCase() == 'blocked';
    if (isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account is blocked. Contact support.')),
      );
      return;
    }
    if (!_hasDrivingDocument) {
      // same restriction as slot booking: learner or license required
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Please complete onboarding (add learner or license) to book a test.'),
          action: SnackBarAction(
            label: 'Complete',
            onPressed: _navigateToCompleteOnboarding,
          ),
        ),
      );
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const TestBookingPage()));
  }

  void _navigateToUploadDocuments() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const UploadDocumentPage()));
  }

  void _navigateToAttendance() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const UserAttendancePage()));
  }

  void _navigateToDownloadables() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DownloadablesPage()));
  }

  void _navigateToSettings() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => UserSettingsScreen()));
  }

  // CTA used by onboarding banner
  void _navigateToCompleteOnboarding() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const OnboardingForm()));
  }

  // Responsive Onboarding banner — replaces the existing _onboardingBanner()
  Widget _onboardingBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Container(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: LayoutBuilder(builder: (context, constraints) {
            // tune breakpoint as needed
            final isNarrow = constraints.maxWidth < 420;

            final iconBox = Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadii.s),
              ),
              child: Icon(Icons.info_outline, color: AppColors.warning),
            );

            final title = Text('Complete onboarding', style: AppText.tileTitle);
            final subtitle = Text(
              'Finish setting-up your account',
              style: AppText.tileSubtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );

            final completeBtn = TextButton(
              onPressed: _navigateToCompleteOnboarding,
              child: const Text('Complete onboarding',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            );

            if (isNarrow) {
              // stacked layout for small widths: icon + texts, then actions in a row
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconBox,
                      const SizedBox(width: 12),
                      // Title + subtitle in a flexible column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 4),
                            subtitle,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // action row — buttons share available space
                  Row(
                    children: [
                      Expanded(child: completeBtn),
                    ],
                  ),
                ],
              );
            } else {
              // roomy layout: single row with icon, text expanded, action and dismiss
              return Row(
                children: [
                  iconBox,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ),
                  ),
                  // action button & dismiss on the right
                  completeBtn,
                ],
              );
            }
          }),
        ),
      ),
    );
  }

  // Blocked banner (local dismiss only)
  Widget _blockedBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Container(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // icon / left
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.s),
                ),
                child: const Icon(Icons.block, color: AppColors.danger),
              ),

              const SizedBox(width: 12),

              // text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account blocked', style: AppText.tileTitle),
                    const SizedBox(height: 4),
                    Text(
                      'Your account has been blocked. Some features are restricted. Contact support for help.',
                      style: AppText.tileSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // action (contact support)
              TextButton(
                onPressed: () {
                  // Navigate to settings where support/contact details exist
                  _navigateToSettings();
                },
                child: const Text('Contact support',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),

              // dismiss
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _hideOnboardingBanner = true),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner shown when booking/test features are locked due to missing learner/license.
  /// Dismissible locally.
  Widget _licenseUnlockBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Container(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // left icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadii.s),
                ),
                child: const Icon(Icons.info_outline, color: AppColors.info),
              ),

              const SizedBox(width: 12),

              // text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update licence details', style: AppText.tileTitle),
                    const SizedBox(height: 6),
                    Text(
                      'Add your learner or license details to unlock bookings & tests.',
                      style: AppText.tileSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // CTA
              TextButton(
                onPressed: _navigateToSettings,
                child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w700)),
              ),

              // dismiss
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _hideLicenseBanner = true),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 18, color: AppColors.onSurface),
        const SizedBox(width: 8),
        Text(text, style: AppText.sectionTitle),
      ],
    );
  }
}

class _NameCard extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final String? photoUrl;

  // plan (plain string)
  final String? planIdString;

  // blocked indicator
  final bool isBlocked;

  const _NameCard({
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    required this.planIdString,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: AppGradients.nameCard,
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          boxShadow: AppShadows.elevatedDark,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GrainPainter(opacity: 0.06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  _Avatar(photoUrl: photoUrl),
                  const SizedBox(width: 16),

                  // Make the text / plan area tappable and navigate to PlansView.
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        // Navigate to PlansView (always). If you prefer to open
                        // PlanDetailsPage when planIdString is present, swap this.
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PlansView()),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Welcome back,',
                              style: TextStyle(
                                  color: AppColors.onSurfaceInverseMuted,
                                  fontSize: 13)),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.onSurfaceInverse,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$email | ${role.toLowerCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.onSurfaceInverseMuted,
                                fontSize: 12,
                                letterSpacing: 0.3),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.workspace_premium,
                                  size: 16, color: AppColors.onSurfaceInverseMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      'Plan: ${planIdString == null || planIdString!.isEmpty ? '—' : planIdString!}',
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceInverse,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(width: 8),
                                    // circular background with arrow
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.onSurfaceInverseMuted,
                                      ),
                                      child: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: AppColors.onSurfaceInverse,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isBlocked) const SizedBox(width: 8),
                              if (isBlocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: AppColors.danger.withOpacity(0.18)),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.block,
                                          size: 14, color: AppColors.danger),
                                      SizedBox(width: 6),
                                      Text(
                                        'Blocked',
                                        style: TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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
}


class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({this.photoUrl});
  @override
  Widget build(BuildContext context) {
    final bg = AppColors.onSurfaceInverse.withOpacity(0.14);
    if (photoUrl == null || photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 36,
        backgroundColor: bg,
        child:
            const Icon(Icons.person, color: AppColors.onSurfaceInverse, size: 38),
      );
    }
    return CircleAvatar(
      radius: 36,
      backgroundColor: bg,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Primary big tiles (two per row)
class _PrimaryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final bool enabled;

  const _PrimaryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.enabled = true,
  });

  static const double _kTileHeight = 150;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.l),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: _kTileHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(AppRadii.m),
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tileTitle,
                    ),
                  ],
                ),
              ),
              // Disabled overlay
              if (!enabled)
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withOpacity(0.65),
                    borderRadius: BorderRadius.circular(AppRadii.l),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.lock, size: 28, color: AppColors.onSurfaceMuted),
                        SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.m),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.tileTitle),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppText.tileSubtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final String phone;
  final String email;

  const _ContactTile({required this.phone, required this.email});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.accentTeal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadii.m),
              ),
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.support_agent, color: AppColors.accentTeal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Contact Us", style: AppText.tileTitle),
                  const SizedBox(height: 4),
                  Text("Phone: $phone", style: AppText.tileSubtitle),
                  Text("Email: $email", style: AppText.tileSubtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// Notification bell (navigates to a full NotificationsPage)
/// ===============================
class NotificationBell extends StatelessWidget {
  final String uid;
  final String role; // 'student' | 'instructor'
  final String userStatus; // 'active' | 'pending' | 'blocked'

  const NotificationBell({
    super.key,
    required this.uid,
    required this.role,
    required this.userStatus,
  });

  bool _isTargeted(Map<String, dynamic> m) {
    try {
      final List segs = (m['segments'] as List?) ?? const ['all'];
      final Set<String> S =
          segs.map((e) => e.toString().toLowerCase()).toSet();

      final List targets = (m['target_uids'] as List?) ?? const [];
      final bool direct = targets.map((e) => e.toString()).contains(uid);

      DateTime? asDt(dynamic v) {
        if (v == null) return null;
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        return null;
      }

      final now = DateTime.now();
      final scheduledAt = asDt(m['scheduled_at']) ?? asDt(m['created_at']);
      final expiresAt = asDt(m['expires_at']);
      final withinTime = (scheduledAt == null || !scheduledAt.isAfter(now)) &&
          (expiresAt == null || expiresAt.isAfter(now));

      final bool segmentHit = S.contains('all') ||
          (S.contains('students') && role == 'student') ||
          (S.contains('instructors') && role == 'instructor') ||
          (S.contains('active') && userStatus == 'active') ||
          (S.contains('pending') && userStatus == 'pending') ||
          (S.contains('blocked') && userStatus == 'blocked');

      return withinTime && (direct || segmentHit);
    } catch (e, st) {
      debugPrint('NBELL: _isTargeted error: $e\n$st');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    // read receipts for current user
    final readsStream = fs
        .collection('users')
        .doc(uid)
        .collection('notif_reads')
        .snapshots();

    // Global broadcast notifications
    final notifsQuery = fs
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();

    // Per-user notifications (written by admin flows to user_notification)
    final userNotifsQuery = fs
        .collection('user_notification')
        .where('uid', isEqualTo: uid)
        .limit(100) // increase if you expect more items
        .snapshots();

    // Always show the icon immediately so UI doesn't disappear while streams resolve.
    return StreamBuilder<QuerySnapshot>(
      stream: readsStream,
      builder: (context, readsSnap) {
        // build a safe readAtMap (never throws)
        final Map<String, DateTime?> readAtMap = {};
        if (readsSnap.hasError) {
          debugPrint('NBELL: readsStream error: ${readsSnap.error}');
        } else if (readsSnap.hasData) {
          try {
            for (final d in readsSnap.data!.docs) {
              final map = (d.data() as Map<String, dynamic>?) ??
                  <String, dynamic>{};
              final v = map['readAt'] ?? map['read_at'];
              if (v is Timestamp) readAtMap[d.id] = v.toDate();
              else if (v is DateTime) readAtMap[d.id] = v;
              else readAtMap[d.id] = null;
            }
          } catch (e, st) {
            debugPrint('NBELL: readsStream parsing error: $e\n$st');
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: notifsQuery,
          builder: (context, notifSnap) {
            if (notifSnap.hasError) {
              debugPrint('NBELL: notifsQuery error: ${notifSnap.error}');
            }

            return StreamBuilder<QuerySnapshot>(
              stream: userNotifsQuery,
              builder: (context, userNotifSnap) {
                if (userNotifSnap.hasError) {
                  debugPrint(
                      'NBELL: userNotifsQuery error: ${userNotifSnap.error}');
                }

                // Merge documents safely
                final List<QueryDocumentSnapshot> combined = [];
                try {
                  if (notifSnap.hasData) combined.addAll(notifSnap.data!.docs);
                  if (userNotifSnap.hasData)
                    combined.addAll(userNotifSnap.data!.docs);
                } catch (e, st) {
                  debugPrint('NBELL: merging snapshots error: $e\n$st');
                }

                // dedupe by id
                final Map<String, QueryDocumentSnapshot> byId = {};
                for (final d in combined) {
                  byId[d.id] ??= d;
                }
                final merged = byId.values.toList();

                // sort client-side by created_at (newest first)
                merged.sort((a, b) {
                  DateTime ta = DateTime.fromMillisecondsSinceEpoch(0);
                  DateTime tb = DateTime.fromMillisecondsSinceEpoch(0);
                  try {
                    final ma = (a.data() as Map<String, dynamic>?) ?? {};
                    final mb = (b.data() as Map<String, dynamic>?) ?? {};
                    final ca = ma['created_at'];
                    final cb = mb['created_at'];
                    if (ca is Timestamp) ta = ca.toDate();
                    if (ca is DateTime) ta = ca;
                    if (cb is Timestamp) tb = cb.toDate();
                    if (cb is DateTime) tb = cb;
                  } catch (_) {}
                  return tb.compareTo(ta);
                });

                // pick targeted
                final targeted = <QueryDocumentSnapshot>[];
                for (final d in merged) {
                  final path = d.reference.path;
                  final m = (d.data() as Map<String, dynamic>?) ??
                      <String, dynamic>{};
                  final fromUserNotification = path.contains('user_notification/');
                  if (fromUserNotification) {
                    targeted.add(d);
                  } else {
                    if (_isTargeted(m)) targeted.add(d);
                  }
                }

                final now = DateTime.now();
                final sevenDays = const Duration(days: 7);

                final visible = targeted.where((d) {
                  final readAt = readAtMap[d.id];
                  if (readAt == null) return true;
                  return now.difference(readAt) <= sevenDays;
                }).toList();

                final unreadCount =
                    visible.where((d) => !readAtMap.containsKey(d.id)).length;

                // debug output to help troubleshooting
                debugPrint(
                    'NBELL: uid=$uid merged=${merged.length} targeted=${targeted.length} visible=${visible.length} unread=$unreadCount');

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsPage(
                              uid: uid,
                              role: role,
                              userStatus: userStatus,
                              initialTargeted: visible,
                              initialReadIds: readAtMap.keys.toSet(),
                            ),
                          ),
                        );
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                                color: AppColors.onSurfaceInverse, fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Full-screen notifications page (navigated to from the bell)
class NotificationsPage extends StatefulWidget {
  final String uid;
  final String role;
  final String userStatus;
  final List<QueryDocumentSnapshot> initialTargeted;
  final Set<String> initialReadIds;

  const NotificationsPage({
    super.key,
    required this.uid,
    required this.role,
    required this.userStatus,
    required this.initialTargeted,
    required this.initialReadIds,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // reuse streams like in bell but render a list here
  Stream<QuerySnapshot> get _globalNotifs => _fs
      .collection('notifications')
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots();

  Stream<QuerySnapshot> get _userNotifs => _fs
      .collection('user_notification')
      .where('uid', isEqualTo: widget.uid)
      .limit(200)
      .snapshots();

  Stream<QuerySnapshot> get _readsStream =>
      _fs.collection('users').doc(widget.uid).collection('notif_reads').snapshots();

  // local cache for merged/targeted docs
  List<QueryDocumentSnapshot> _visible = [];
  Set<String> _readIds = {};

  // UI state
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _readIds = Set<String>.from(widget.initialReadIds);
    _visible = List<QueryDocumentSnapshot>.from(widget.initialTargeted);
    // then listen for live updates
    _subscribeStreams();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text.trim().toLowerCase();
      });
    });
  }

  StreamSubscription<QuerySnapshot>? _subGlobal;
  StreamSubscription<QuerySnapshot>? _subUser;
  StreamSubscription<QuerySnapshot>? _subReads;

  void _subscribeStreams() {
    _subGlobal = _globalNotifs.listen((_) => _recompute());
    _subUser = _userNotifs.listen((_) => _recompute());
    _subReads = _readsStream.listen((snap) {
      final Map<String, DateTime?> readAtMap = {};
      for (final d in snap.docs) {
        final map = (d.data() as Map<String, dynamic>?) ?? {};
        final v = map['readAt'] ?? map['read_at'];
        if (v is Timestamp) readAtMap[d.id] = v.toDate();
        else if (v is DateTime) readAtMap[d.id] = v;
        else readAtMap[d.id] = null;
      }
      setState(() {
        _readIds = readAtMap.keys.toSet();
      });
    }, onError: (e) {
      debugPrint('NotificationsPage readsStream error: $e');
    });
  }

  Future<void> _recompute() async {
    try {
      final g = await _globalNotifs.first;
      final u = await _userNotifs.first;

      final combined = <QueryDocumentSnapshot>[];
      combined.addAll(g.docs);
      combined.addAll(u.docs);

      final Map<String, QueryDocumentSnapshot> byId = {};
      for (final d in combined) byId[d.id] ??= d;
      final merged = byId.values.toList();

      // sort newest first
      merged.sort((a, b) {
        DateTime ta = DateTime.fromMillisecondsSinceEpoch(0);
        DateTime tb = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          final ma = (a.data() as Map<String, dynamic>?) ?? {};
          final mb = (b.data() as Map<String, dynamic>?) ?? {};
          final ca = ma['created_at'];
          final cb = mb['created_at'];
          if (ca is Timestamp) ta = ca.toDate();
          if (ca is DateTime) ta = ca;
          if (cb is Timestamp) tb = cb.toDate();
          if (cb is DateTime) tb = cb;
        } catch (_) {}
        return tb.compareTo(ta);
      });

      // filtering / targeting (same logic as before)
      bool _isTargeted(Map<String, dynamic> m) {
        try {
          final List segs = (m['segments'] as List?) ?? const ['all'];
          final Set<String> S = segs.map((e) => e.toString().toLowerCase()).toSet();

          final List targets = (m['target_uids'] as List?) ?? const [];
          final bool direct = targets.map((e) => e.toString()).contains(widget.uid);

          DateTime? asDt(dynamic v) {
            if (v == null) return null;
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            return null;
          }

          final now = DateTime.now();
          final scheduledAt = asDt(m['scheduled_at']) ?? asDt(m['created_at']);
          final expiresAt = asDt(m['expires_at']);
          final withinTime = (scheduledAt == null || !scheduledAt.isAfter(now)) &&
              (expiresAt == null || expiresAt.isAfter(now));

          final bool segmentHit = S.contains('all') ||
              (S.contains('students') && widget.role == 'student') ||
              (S.contains('instructors') && widget.role == 'instructor') ||
              (S.contains('active') && widget.userStatus == 'active') ||
              (S.contains('pending') && widget.userStatus == 'pending') ||
              (S.contains('blocked') && widget.userStatus == 'blocked');

          return withinTime && (direct || segmentHit);
        } catch (e, st) {
          debugPrint('NotificationsPage: _isTargeted error: $e\n$st');
          return false;
        }
      }

      final targeted = <QueryDocumentSnapshot>[];
      for (final d in merged) {
        final path = d.reference.path;
        final m = (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        final fromUserNotification = path.contains('user_notification/');
        if (fromUserNotification) {
          targeted.add(d);
        } else {
          if (_isTargeted(m)) targeted.add(d);
        }
      }

      // only keep items visible (we show all targeted here)
      final visible = targeted.toList();

      setState(() {
        _visible = visible;
      });
    } catch (e, st) {
      debugPrint('NotificationsPage _recompute error: $e\n$st');
    }
  }

  @override
  void dispose() {
    _subGlobal?.cancel();
    _subUser?.cancel();
    _subReads?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _markRead(String notifId) async {
    try {
      final batch = _fs.batch();

      final uidLocal = widget.uid;
      if (uidLocal.isEmpty) return;

      final readRef = _fs.collection('users').doc(uidLocal).collection('notif_reads').doc(notifId);
      batch.set(readRef, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      final notifRef = _fs.collection('user_notification').doc(notifId);
      final expiresAtDate = DateTime.now().toUtc().add(const Duration(days: 5));
      final expiresAtTimestamp = Timestamp.fromDate(expiresAtDate);

      batch.set(notifRef, {
        'read': true,
        'read_at': FieldValue.serverTimestamp(),
        'expires_at': expiresAtTimestamp,
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint('NotificationsPage _markRead error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to mark read: $e')));
      }
    }
  }

  Future<void> _markAllVisibleRead() async {
    try {
      final batch = _fs.batch();
      final uidLocal = widget.uid;
      if (uidLocal.isEmpty) return;

      for (final d in _filteredVisible) {
        final id = d.id;
        final readRef = _fs.collection('users').doc(uidLocal).collection('notif_reads').doc(id);
        batch.set(readRef, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

        final notifRef = _fs.collection('user_notification').doc(id);
        final expiresAtDate = DateTime.now().toUtc().add(const Duration(days: 5));
        final expiresAtTimestamp = Timestamp.fromDate(expiresAtDate);

        batch.set(notifRef, {
          'read': true,
          'read_at': FieldValue.serverTimestamp(),
          'expires_at': expiresAtTimestamp,
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('NotificationsPage _markAllVisibleRead error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to mark all read: $e')));
      }
    }
  }

  String _formatWhen(dynamic ts) {
    DateTime? dt;
    if (ts == null) return '—';
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  List<QueryDocumentSnapshot> get _filteredVisible {
    if (_searchTerm.isEmpty) return _visible;
    return _visible.where((d) {
      final m = (d.data() as Map<String, dynamic>?) ?? {};
      final title = (m['title'] ?? '').toString().toLowerCase();
      final msg = (m['message'] ?? '').toString().toLowerCase();
      return title.contains(_searchTerm) || msg.contains(_searchTerm);
    }).toList();
  }

  Future<void> _onRefresh() async {
    setState(() => _loading = true);
    try {
      await _recompute();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openActionUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open link')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleList = _filteredVisible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_email_read_outlined),
            tooltip: 'Mark all visible read',
            onPressed: visibleList.isEmpty ? null : () async {
              await _markAllVisibleRead();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search notifications',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.m),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _onRefresh,
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: visibleList.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No notifications')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: visibleList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final d = visibleList[i];
                  final m = (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
                  final title = (m['title'] ?? '-') as String;
                  final msg = (m['message'] ?? '') as String;
                  final ts = (m['scheduled_at'] ?? m['created_at']) as dynamic;
                  final whenTxt = _formatWhen(ts);
                  final isRead = _readIds.contains(d.id);
                  final actionUrl = (m['action_url'] ?? m['actionUrl'] ?? '') as String?;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Card(
                      elevation: 0,
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        leading: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isRead ? AppColors.onSurfaceMuted.withOpacity(.08) : AppColors.danger.withOpacity(.12),
                              child: Icon(
                                isRead ? Icons.notifications_none : Icons.notifications_active,
                                color: isRead ? AppColors.onSurfaceMuted : AppColors.danger,
                                size: 18,
                              ),
                            ),
                            if (!isRead)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.surface, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isRead
                                ? Theme.of(context).colorScheme.onSurface.withOpacity(.75)
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(whenTxt, style: AppText.hintSmall),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              msg.isEmpty ? '—' : msg,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(isRead ? .6 : .8),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: isRead ? null : () async {
                                  await _markRead(d.id);
                                },
                                icon: const Icon(Icons.mark_email_read_outlined),
                                label: const Text('Mark as read'),
                              ),
                              const SizedBox(width: 8),
                              if (actionUrl != null && actionUrl.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () async {
                                    await _openActionUrl(actionUrl);
                                  },
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open link'),
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
    );
  }
}

/// ─────────────────────────────────────────────────────────────────
/// Plan details page — opened when user taps the "Plan" area in NameCard
/// Always navigated to (even when planId is empty).
/// ─────────────────────────────────────────────────────────────────
class PlanDetailsPage extends StatefulWidget {
  final String planId;
  const PlanDetailsPage({required this.planId, super.key});

  @override
  State<PlanDetailsPage> createState() => _PlanDetailsPageState();
}

class _PlanDetailsPageState extends State<PlanDetailsPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  late Future<DocumentSnapshot<Map<String, dynamic>>>? _planFuture;

  @override
  void initState() {
    super.initState();
    if (widget.planId.isNotEmpty) {
      _planFuture = _fs.collection('plans').doc(widget.planId).get();
    } else {
      _planFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.planId.isEmpty ? 'Plan' : 'Plan: ${widget.planId}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      backgroundColor: AppColors.background,
      body: widget.planId.isEmpty
          ? _buildNoPlanView(context)
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _planFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Failed to load plan: ${snap.error}'));
                }
                final doc = snap.data;
                if (doc == null || !doc.exists) {
                  return Center(child: Text('Plan "${widget.planId}" not found.'));
                }
                final data = doc.data() ?? <String, dynamic>{};
                final title = (data['title'] ?? widget.planId).toString();
                final price = data['price']?.toString() ?? '-';
                final duration = data['duration_months']?.toString() ??
                    data['duration']?.toString() ??
                    '-';
                final perks = (data['perks'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Price: ', style: AppText.tileTitle),
                          Text(price, style: AppText.tileSubtitle),
                          const Spacer(),
                          Text('Duration: ', style: AppText.tileTitle),
                          Text('$duration months', style: AppText.tileSubtitle),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Perks',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (perks.isEmpty)
                        const Text('No perks listed for this plan.',
                            style: AppText.tileSubtitle)
                      else
                        ...perks.map((p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.check, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(p, style: AppText.tileSubtitle)),
                                ],
                              ),
                            )),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onSurfaceInverse,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.m)),
                        ),
                        onPressed: () {
                          // Example CTA: navigate to purchase/upgrade flow or show more info.
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content:
                                  Text('Purchase/Upgrade flow not implemented.'))); 
                        },
                        child: const Text('Purchase / Manage Plan'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildNoPlanView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Icon(Icons.workspace_premium, size: 72, color: AppColors.onSurfaceMuted),
          const SizedBox(height: 18),
          const Text(
            'No active plan assigned',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'You currently don\'t have an active plan. Explore available plans or contact support to get started.',
            textAlign: TextAlign.center,
            style: AppText.tileSubtitle,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Directly push the PlansView page
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlansView()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onSurfaceInverse,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.m)),
                  ),
                  child: const Text('Explore Plans'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
