// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Analytics
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';

import 'package:smart_drive/reusables/branding.dart';
import 'app_bootstrap.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate must initialize Firebase.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase early so background handler can be registered reliably.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background handler BEFORE runApp()
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Now start the UI
  runApp(const SmartDriveApp());
}

class SmartDriveApp extends StatelessWidget {
  const SmartDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use FirebaseAnalytics.instance directly when logging events from widgets.
    final analytics = FirebaseAnalytics.instance;

    return MaterialApp(
      title: AppBrand.appName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter',
      ),
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,

      // Use the built-in observer that references FirebaseAnalytics.instance
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: analytics),
      ],

      home: const AppBootstrap(),
    );
  }
}
