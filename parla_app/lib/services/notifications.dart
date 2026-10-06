import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Backend'deki ANDROID_CHANNEL_ID ve AndroidManifest'teki varsayılan kanal ile aynı olmalı.
const String reminderChannelId = 'reminders';
const _reminderChannelName = 'Hatırlatmalar';
const _weeklyPlanId = 1001;

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

/// Firebase başarıyla başlatıldıysa true (iOS'ta GoogleService-Info.plist yoksa false kalır)
bool firebaseReady = false;

const _androidDetails = AndroidNotificationDetails(
  reminderChannelId,
  _reminderChannelName,
  importance: Importance.defaultImportance,
  priority: Priority.defaultPriority,
);
const _details = NotificationDetails(android: _androidDetails, iOS: DarwinNotificationDetails());

/// Uygulama açılışında bir kez çağrılır.
Future<void> initNotifications() async {
  // Saat dilimi (haftalık plan "her pazar 19:00" yerel saate göre kurulur)
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
  }

  await _local.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // İzni hatırlatma açılırken isteyeceğiz, açılışta değil
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  await _local
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(reminderChannelId, _reminderChannelName));

  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase başlatılamadı (push kapalı): $e');
    return;
  }

  // Uygulama açıkken gelen push'lar: Android sistem bildirimi göstermez, biz gösteririz.
  if (Platform.isIOS) {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(alert: true, badge: false, sound: false);
  } else {
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _local.show(
        id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: n.title,
        body: n.body,
        notificationDetails: _details,
      );
    });
  }
}

bool _isAllowed(AuthorizationStatus s) =>
    s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

/// Bildirim izni zaten verilmiş mi?
Future<bool> notificationsAllowed() async {
  if (firebaseReady) {
    return _isAllowed((await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus);
  }
  final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.areNotificationsEnabled() ?? false;
}

/// Gerekirse izin ister. Android 13+ ve iOS'ta sistem penceresi açılır.
Future<bool> ensureNotificationPermission() async {
  if (await notificationsAllowed()) return true;
  if (firebaseReady) {
    final s = await FirebaseMessaging.instance.requestPermission(alert: true, badge: false, sound: true);
    return _isAllowed(s.authorizationStatus);
  }
  final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? false;
}

/// FCM token'ı (backend'e kaydedilir). Alınamazsa null.
Future<String?> getPushToken() async {
  if (!firebaseReady) return null;
  try {
    return await FirebaseMessaging.instance.getToken();
  } catch (e) {
    debugPrint('FCM token alınamadı: $e');
    return null;
  }
}

Stream<String> get onPushTokenRefresh =>
    firebaseReady ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

/// "Haftalık plan": her pazar 19:00 yerel bildirim
Future<void> setWeeklyPlan(bool on) async {
  await _local.cancel(id: _weeklyPlanId);
  if (!on) return;

  final now = tz.TZDateTime.now(tz.local);
  var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19);
  while (next.weekday != DateTime.sunday || !next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }

  await _local.zonedSchedule(
    id: _weeklyPlanId,
    title: 'Haftanın planı hazır',
    body: 'Bu hafta yıkamak ve cam silmek için en iyi günlere bak.',
    scheduledDate: next,
    notificationDetails: _details,
    // Kesin alarm izni istememek için esnek zamanlama (birkaç dakika kayabilir)
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
  );
}
