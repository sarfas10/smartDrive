import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

final _fcm = FirebaseMessaging.instance;
final _fln = FlutterLocalNotificationsPlugin();

Future<void> initPush() async {
  await _fcm.requestPermission(alert: true, badge: true, sound: true);

  // Use your small white glyph for Android init
  const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const init = InitializationSettings(android: androidInit, iOS: iosInit);

  await _fln.initialize(
    init,
    onDidReceiveNotificationResponse: (resp) {
      final url = resp.payload; // deep-link if you want
      // TODO: handle navigation using [url]
    },
  );

  // Ensure the high-importance channel exists (Android)
  const channel = AndroidNotificationChannel(
    'push',
    'Push Notifications',
    description: 'General push notifications',
    importance: Importance.high,
  );
  final androidImpl = _fln.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  // Foreground notifications
  FirebaseMessaging.onMessage.listen((msg) async {
    final n = msg.notification;
    if (n == null) return;

    // Android: brand the notification (small icon + large icon)
    const androidDetails = AndroidNotificationDetails(
      'push',
      'Push Notifications',
      channelDescription: 'General push notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_notify', // your 48x48 white glyph
      largeIcon: DrawableResourceAndroidBitmap('logo'), // full-color logo.png in res/drawable
      // styleInformation: BigTextStyleInformation(''), // or BigPictureStyleInformation(...) if you add a banner
      // color: Color(0xFF4C63D2), // optional accent color
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _fln.show(
      n.hashCode,
      n.title,
      n.body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: msg.data['action_url'],
    );
  });
}

Future<void> subscribeUserSegments({required String role, required String status}) async {
  await _fcm.subscribeToTopic('all');

  if (role == 'student') {
    await _fcm.subscribeToTopic('students');
    await _fcm.unsubscribeFromTopic('instructors');
  } else if (role == 'instructor') {
    await _fcm.subscribeToTopic('instructors');
    await _fcm.unsubscribeFromTopic('students');
  }

  if (status == 'active') {
    await _fcm.subscribeToTopic('active');
    await _fcm.unsubscribeFromTopic('pending');
  } else if (status == 'pending') {
    await _fcm.subscribeToTopic('pending');
    await _fcm.unsubscribeFromTopic('active');
  }
}

Future<void> unsubscribeRoleStatusTopics({bool alsoAll = false}) async {
  await _fcm.unsubscribeFromTopic('students');
  await _fcm.unsubscribeFromTopic('instructors');
  await _fcm.unsubscribeFromTopic('active');
  await _fcm.unsubscribeFromTopic('pending');
  if (alsoAll) {
    await _fcm.unsubscribeFromTopic('all');
  }
}

void attachTokenRefreshHandler(Future<void> Function() reapply) {
  _fcm.onTokenRefresh.listen((_) async => await reapply());
}
  