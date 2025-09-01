// lib/main.dart
import 'package:flutter/material.dart';
import 'package:smart_drive/reusables/branding.dart';
import 'app_bootstrap.dart';

class SmartDriveApp extends StatelessWidget {
  const SmartDriveApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.appName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
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
      home: const AppBootstrap(), // <- start here
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartDriveApp());
}
