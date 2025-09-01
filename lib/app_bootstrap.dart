// lib/app_bootstrap.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'messaging_setup.dart';
import 'services/session_service.dart';
import 'onboard.dart'; // your real entry screen

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // handle message.data['action_url'] if needed
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await initPush(); // permissions, channels, foreground handler

      // Restore session and topics
      final sess = await SessionService().read();
      if (sess.role != null && sess.status != null) {
        await subscribeUserSegments(role: sess.role!, status: sess.status!);
      }

      // Reapply on token refresh
      attachTokenRefreshHandler(() async {
        final s = await SessionService().read();
        if (s.role != null && s.status != null) {
          await subscribeUserSegments(role: s.role!, status: s.status!);
        }
      });

      if (!mounted) return;
      // Navigate to your actual home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OnboardingScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Simple splash/loading UI (this renders the first frame quickly)
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 32),
                  const SizedBox(height: 8),
                  Text('Init failed:\n$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _init,
                    child: const Text('Retry'),
                  ),
                ],
              ),
      ),
    );
  }
}
