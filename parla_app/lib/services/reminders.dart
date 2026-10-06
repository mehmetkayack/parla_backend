import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_keys.dart';
import 'api.dart';
import 'notifications.dart';

enum ReminderKey { goodDay, rainAfterWash, weeklyPlan, glass }

/// Push ile çalışanlar (sunucu gönderir)
const pushReminderKeys = {ReminderKey.goodDay, ReminderKey.rainAfterWash};

// Push ile çalışanlar kullanıcı açana kadar kapalı: sunucuya kayıt olmadan açık görünmesinler
const _defaults = {
  ReminderKey.goodDay: false,
  ReminderKey.rainAfterWash: false,
  ReminderKey.weeklyPlan: true,
  ReminderKey.glass: false,
};

typedef ReminderPrefs = Map<ReminderKey, bool>;

Future<ReminderPrefs> loadReminderPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final result = Map<ReminderKey, bool>.of(_defaults);
  final raw = prefs.getString(StorageKeys.reminders);
  if (raw != null) {
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final k in ReminderKey.values) {
        if (saved[k.name] is bool) result[k] = saved[k.name] as bool;
      }
    } catch (_) {}
  }
  return result;
}

Future<void> saveReminderPrefs(ReminderPrefs value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StorageKeys.reminders, jsonEncode({for (final e in value.entries) e.key.name: e.value}));
}

enum PushSyncResult { ok, noToken, serverError }

/// FCM token'ı, konumu ve push tercihlerini backend'e gönderir.
Future<PushSyncResult> syncPush({
  required ReminderPrefs reminders,
  required Coords coords,
  required String locationName,
}) async {
  final token = await getPushToken();
  if (token == null) return PushSyncResult.noToken;
  final prefs = await SharedPreferences.getInstance();
  try {
    await registerPush(
      pushToken: token,
      coords: coords,
      locationName: locationName,
      goodDay: reminders[ReminderKey.goodDay] ?? false,
      rainAfterWash: reminders[ReminderKey.rainAfterWash] ?? false,
      lastWashAt: prefs.getString(StorageKeys.lastWash),
    );
    return PushSyncResult.ok;
  } catch (e) {
    debugPrint('Push kaydı başarısız: $e');
    return PushSyncResult.serverError;
  }
}

bool anyPushReminderOn(ReminderPrefs r) => pushReminderKeys.any((k) => r[k] ?? false);
