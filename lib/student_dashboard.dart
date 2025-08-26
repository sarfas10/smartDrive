import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:smart_drive/onboarding_forms.dart';
import 'package:smart_drive/user_settings.dart';
import 'package:smart_drive/user_slot_booking.dart';


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

class _StudentDashboardState extends State<StudentDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String userStatus = '';
  Map<String, dynamic> userData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();

        if (doc.exists) {
          setState(() {
            userData = doc.data() as Map<String, dynamic>;
            userStatus = userData['status'] ?? 'pending';
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFF89f7fe),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      if (userStatus == 'pending') _buildPendingBanner(),
                      const SizedBox(height: 20),
                      _buildQuickStats(),
                      const SizedBox(height: 24),
                      _buildMainFeatures(),
                      const SizedBox(height: 24),
                      _buildSecondaryFeatures(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // =========================
  // METAL CARD HEADER (STYLE)
  // =========================
  Widget _buildHeader() {
    final name = (userData['name'] ?? 'Student').toString();
    final role = (userData['role'] ?? 'student').toString();
    final email = (userData['email'] ?? '').toString();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-0.9, -0.9),
            end: Alignment(0.9, 0.9),
            colors: [Color(0xFF2B2B2D), Color(0xFF3A3B3E), Color(0xFF1F2022)],
            stops: [0.0, 0.55, 1.0],
          ),
          border:
              Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GrainPainter(opacity: 0.06)),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.08), width: 0.6),
              ),
            ),

            // Top-right: settings + notification
            Positioned(
              top: 6,
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white, size: 26),
                    splashRadius: 22,
                    onPressed: _navigateToSettings,
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Colors.white, size: 26),
                    splashRadius: 22,
                    onPressed: _navigateToNotifications,
                  ),
                ],
              ),
            ),

            // Left block: avatar + text
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white.withOpacity(0.14),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 38),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TOP (fixed "Welcome back")
                        const Text(
                          'Welcome back,',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),

                        // Middle block expands to center Name + Email|Role
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.4),
                                      offset: const Offset(0.6, 0.6),
                                      blurRadius: 1.2,
                                    ),
                                    Shadow(
                                      color: Colors.white.withOpacity(0.12),
                                      offset: const Offset(-0.4, -0.4),
                                      blurRadius: 1.0,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$email | ${role.toLowerCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildPendingBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.8), Colors.red.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Please complete your profile onboarding to access all features',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: _navigateToOnboarding,
            child: const Text(
              'Complete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
              'Attendance', '85%', Icons.calendar_today, Colors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('Lessons', '12/20', Icons.drive_eta, Colors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('Tests', '8/10', Icons.quiz, Colors.purple),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glassmorphismDecoration(),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style:
              TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                  'Book Slot', Icons.calendar_month, Colors.orange, _navigateToSlotBooking),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                  'Payments', Icons.payment, Colors.green, _navigateToPayments),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard('Study Materials', Icons.menu_book,
                  Colors.blue, _navigateToStudyMaterials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                  'Mock Tests', Icons.quiz, Colors.purple, _navigateToMockTests),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecondaryFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'More Features',
          style:
              TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildListFeature(
          'Profile Settings',
          Icons.person,
          'Manage your personal information and documents',
          _navigateToProfile,
        ),
        const SizedBox(height: 12),
        _buildListFeature(
          'Attendance Tracker',
          Icons.access_time,
          'View your attendance history and statistics',
          _navigateToAttendance,
        ),
        const SizedBox(height: 12),
        _buildListFeature(
          'Invoice History',
          Icons.receipt,
          'View all your payment receipts and invoices',
          _navigateToInvoices,
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _glassmorphismDecoration(),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListFeature(
      String title, IconData icon, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _glassmorphismDecoration(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  BoxDecoration _glassmorphismDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.2),
          Colors.white.withOpacity(0.1),
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // Navigation
  void _navigateToOnboarding() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => OnboardingForm()),
    );
  }

  void _navigateToSlotBooking() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserSlotBooking()),
    );
  }

  void _navigateToPayments() {
    debugPrint('Navigate to Payments');
  }

  void _navigateToStudyMaterials() {
    debugPrint('Navigate to Study Materials');
  }

  void _navigateToMockTests() {
    debugPrint('Navigate to Mock Tests');
  }

  void _navigateToProfile() {
    debugPrint('Navigate to Profile');
  }

  void _navigateToAttendance() {
    debugPrint('Navigate to Attendance');
  }

  void _navigateToInvoices() {
    debugPrint('Navigate to Invoices');
  }

  void _navigateToNotifications() {
    debugPrint('Navigate to Notifications');
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) =>  UserSettingsScreen()),
    );
  }
}
