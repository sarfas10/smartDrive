// lib/messaging_setup.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FirebaseMessaging _fcm = FirebaseMessaging.instance;
final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

// Toggle this to disable/enable showing local/system notifications
// when a user_notification document is created. When false, the app will
// still listen to user_notification for the in-app bell/list, but will
// not claim delivered_at or show local notifications.
const bool kShowLocalNotifications = false;

// --- internal helpers for Firestore per-user listener (keeps initPush signature) ---
final Set<String> _seenNotifIds = <String>{};
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userNotifSub;

/// Initializes push (keeps original signature & behaviour)
/// - requests permissions
/// - initializes local notifications and channel
/// - attaches FCM onMessage handler (foreground)
Future<void> initPush() async {
  await _fcm.requestPermission(alert: true, badge: true, sound: true);

  // Use your small white glyph for Android init
  const androidInit = AndroidInitializationSettings('ic_stat_notify');
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

  // Foreground notifications (FCM)
  FirebaseMessaging.onMessage.listen((msg) async {
    final n = msg.notification;
    if (n == null) return;

    // Android branding details (use minimal fallback)
    AndroidNotificationDetails androidDetails;
    try {
      // prefer branded largeIcon if available (may throw if resource missing)
      androidDetails = AndroidNotificationDetails(
        'push',
        'Push Notifications',
        channelDescription: 'General push notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_notify',
        largeIcon: DrawableResourceAndroidBitmap('logo'),
      );
    } catch (_) {
      androidDetails = AndroidNotificationDetails(
        'push',
        'Push Notifications',
        channelDescription: 'General push notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_notify',
      );
    }

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Safely read action url (snake_case or camelCase)
    final payload = (msg.data['action_url'] ?? msg.data['actionUrl'])?.toString();

    try {
      await _fln.show(
        n.hashCode,
        n.title,
        n.body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payload,
      );
    } catch (e) {
      // If show fails, log and ignore — listener will not crash
      debugPrint('FCM onMessage show failed: $e');
    }
  });
}

/// Save the current FCM token under user_tokens/{uid}/tokens/{tokenDoc}
/// and subscribe to token refresh to keep the DB updated.
///
/// Uses the token string as the doc id for easy dedupe/cleanup.
Future<void> saveFcmTokenForUser(String uid) async {
  if (uid.isEmpty) return;
  try {
    final token = await _fcm.getToken();
    if (token == null || token.trim().isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('user_tokens')
        .doc(uid)
        .collection('tokens')
        .doc(token);

    await docRef.set({
      'token': token,
      'platform': describeEnum(defaultTargetPlatform),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Listen for token refresh and write new token (best-effort)
    _fcm.onTokenRefresh.listen((newToken) async {
      try {
        if (newToken == null || newToken.trim().isEmpty) return;
        final newRef = FirebaseFirestore.instance
            .collection('user_tokens')
            .doc(uid)
            .collection('tokens')
            .doc(newToken);
        await newRef.set({
          'token': newToken,
          'platform': describeEnum(defaultTargetPlatform),
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Failed to update refreshed FCM token: $e');
      }
    });
  } catch (e) {
    debugPrint('saveFcmTokenForUser error: $e');
  }
}

/// Best-effort removal of a token for a user (call on sign-out)
Future<void> removeFcmTokenForUser(String uid) async {
  if (uid.isEmpty) return;
  try {
    final token = await _fcm.getToken();
    if (token == null || token.trim().isEmpty) return;
    final docRef = FirebaseFirestore.instance
        .collection('user_tokens')
        .doc(uid)
        .collection('tokens')
        .doc(token);
    await docRef.delete();
  } catch (e) {
    debugPrint('removeFcmTokenForUser error: $e');
  }
}

/// Start listening for per-user notifications written to `user_notification`.
/// Call this after you know the current user's uid (for example after sign-in
/// or after restoring session from SharedPreferences).
///
/// If [showLocalNotifications] is true (default) the listener will attempt to
/// atomically claim and show a local notification. If false, the listener
/// will only keep an in-memory dedupe set — useful when you want to keep the
/// in-app bell but not show system/local notifications.
Future<void> startUserNotificationListener(String uid, {bool? showLocalNotifications}) async {
  // cancel previous if any
  await stopUserNotificationListener();

  if (uid.isEmpty) return;

  // default to global constant when parameter not provided
  final bool showLocal = showLocalNotifications ?? kShowLocalNotifications;

  final q = FirebaseFirestore.instance
      .collection('user_notification')
      .where('uid', isEqualTo: uid)
      .orderBy('created_at', descending: true)
      .limit(50);

  _userNotifSub = q.snapshots().listen((snap) async {
    // iterate document changes (only act on newly added docs)
    for (final change in snap.docChanges) {
      try {
        if (change.type != DocumentChangeType.added) continue;

        final doc = change.doc;
        final id = doc.id;

        // local in-memory dedupe
        if (_seenNotifIds.contains(id)) continue;

        final Map<String, dynamic>? m = doc.data();
        final title = (m?['title'] ?? '').toString();
        final body = (m?['message'] ?? '').toString();
        final payload = (m?['action_url'] ?? m?['actionUrl'] ?? '').toString();

        // mark seen in-memory (keeps bell from reprocessing in this session)
        _seenNotifIds.add(id);

        // If configured to NOT show local notifications, skip delivering one.
        if (!showLocal) {
          // We intentionally do not claim delivered_at nor show notifications.
          // This keeps the in-app bell/list working but avoids system notifications.
          continue;
        }

        // If already marked delivered by server, skip
        if (m != null && (m['delivered_at'] != null || m['deliveredAt'] != null)) {
          continue;
        }

        // Try to atomically claim delivery using a transaction.
        // If the document already has delivered_at set, the transaction will
        // return false and we won't show the notification.
        final docRef = doc.reference;
        bool claimed = false;
        try {
          claimed = await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
            final snap = await tx.get(docRef);
            final data = snap.data();
            if (data == null) return false;
            // consider both naming conventions
            if (data['delivered_at'] != null || data['deliveredAt'] != null) {
              return false;
            }
            // set delivered_at and optionally who delivered
            tx.update(docRef, {
              'delivered_at': FieldValue.serverTimestamp(),
              'delivered_by': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            });
            return true;
          }, maxAttempts: 3);
        } catch (e) {
          // transaction failed — treat as not claimed; do not show
          claimed = false;
        }

        if (!claimed) {
          // somebody else already claimed delivery (or tx failed) — skip
          continue;
        }

        // Build android details with safe fallback
        AndroidNotificationDetails androidDetails;
        try {
          androidDetails = AndroidNotificationDetails(
            'push',
            'Push Notifications',
            channelDescription: 'General push notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notify',
            largeIcon: DrawableResourceAndroidBitmap('logo'),
          );
        } catch (_) {
          androidDetails = AndroidNotificationDetails(
            'push',
            'Push Notifications',
            channelDescription: 'General push notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notify',
          );
        }

        final iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        final notifId = id.hashCode;

        // Show local notification (we already claimed delivery above)
        try {
          await _fln.show(
            notifId,
            title.isNotEmpty ? title : 'Notification',
            body.isNotEmpty ? body : null,
            NotificationDetails(android: androidDetails, iOS: iosDetails),
            payload: payload.isNotEmpty ? payload : null,
          );
        } catch (e) {
          // If show fails, it's non-fatal. We already updated delivered_at,
          // so we purposely do NOT roll back — admin will see delivered_at.
          debugPrint('Local notification show error: $e');
        }
      } catch (err) {
        // ignore per-item errors to keep listener resilient
        debugPrint('user_notification processing error: $err');
      }
    }
  }, onError: (e) {
    debugPrint('user_notification listener error: $e');
  });
}

/// Stop per-user listener and clear in-memory dedupe set (call on sign-out)
Future<void> stopUserNotificationListener() async {
  try {
    await _userNotifSub?.cancel();
  } catch (_) {}
  _userNotifSub = null;
  _seenNotifIds.clear();
}

/// Subscribes to topic segments (unchanged)
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

/// Unsubscribe topics (unchanged)
Future<void> unsubscribeRoleStatusTopics({bool alsoAll = false}) async {
  await _fcm.unsubscribeFromTopic('students');
  await _fcm.unsubscribeFromTopic('instructors');
  await _fcm.unsubscribeFromTopic('active');
  await _fcm.unsubscribeFromTopic('pending');
  if (alsoAll) {
    await _fcm.unsubscribeFromTopic('all');
  }
}

/// Keep original signature: attach token refresh handler
void attachTokenRefreshHandler(Future<void> Function() reapply) {
  _fcm.onTokenRefresh.listen((_) async => await reapply());
}
