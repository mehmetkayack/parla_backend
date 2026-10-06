import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_keys.dart';

// Telefonda test ederken bilgisayarının yerel IP'sini yaz (örn: http://192.168.1.X:3000).
// Derlerken de verilebilir: flutter run --dart-define=API_URL=http://192.168.1.X:3000
// Varsayılan 10.0.2.2, Android emülatöründen bilgisayara ulaşan adrestir.
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

const _timeout = Duration(seconds: 45); // Gemini analizi birkaç saniye sürebilir

enum Mode { glass, car }

class Coords {
  const Coords(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude};
}

enum WeatherCondition { sun, cloud, rain }

class WeekDay {
  WeekDay({required this.day, this.temp, required this.condition, required this.score});

  final String day; // "Cum", "Cmt"...
  final String? temp; // "23°"
  final WeatherCondition condition;
  final int score; // 0-100

  factory WeekDay.fromJson(Map<String, dynamic> j) => WeekDay(
        day: '${j['day'] ?? ''}',
        temp: j['temp']?.toString(),
        condition: switch (j['condition']) {
          'rain' => WeatherCondition.rain,
          'cloud' => WeatherCondition.cloud,
          _ => WeatherCondition.sun,
        },
        score: _toInt(j['score']),
      );
}

class Factor {
  Factor({required this.name, required this.value, required this.good});

  final String name; // "Yağmur"
  final String value; // "96 saat boyunca %5"
  final bool good; // status: 'good' | 'warn'

  factory Factor.fromJson(Map<String, dynamic> j) =>
      Factor(name: '${j['name'] ?? ''}', value: '${j['value'] ?? ''}', good: j['status'] == 'good');
}

class WeatherInfo {
  WeatherInfo({this.temp, this.rain, this.wind, this.uv});

  final String? temp, rain, wind, uv;

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        temp: j['temp']?.toString(),
        rain: j['rain']?.toString(),
        wind: j['wind']?.toString(),
        uv: j['uv']?.toString(),
      );
}

// Backend'in şu an döndürdüğü alanlar + ekranların kullanabileceği isteğe bağlı alanlar.
// İsteğe bağlı alanları backend'e eklediğinde ekranlar onları otomatik gösterir.
class AnalysisResult {
  AnalysisResult({
    required this.todaySummary,
    required this.bestDay,
    required this.score,
    required this.summary,
    required this.reason,
    this.bestWindow,
    this.tip,
    this.weather,
    this.week,
    this.factors,
  });

  final String todaySummary;
  final String bestDay;
  final int score;
  final String summary;
  final String reason;
  final String? bestWindow; // "10:00 – 16:00"
  final String? tip;
  final WeatherInfo? weather;
  final List<WeekDay>? week;
  final List<Factor>? factors;

  factory AnalysisResult.fromJson(Map<String, dynamic> j) => AnalysisResult(
        todaySummary: '${j['todaySummary'] ?? ''}',
        bestDay: '${j['bestDay'] ?? ''}',
        score: _toInt(j['score']),
        summary: '${j['summary'] ?? ''}',
        reason: '${j['reason'] ?? ''}',
        bestWindow: j['bestWindow']?.toString(),
        tip: j['tip']?.toString(),
        weather: j['weather'] is Map ? WeatherInfo.fromJson(Map<String, dynamic>.from(j['weather'])) : null,
        week: j['week'] is List
            ? (j['week'] as List).whereType<Map>().map((e) => WeekDay.fromJson(Map<String, dynamic>.from(e))).toList()
            : null,
        factors: j['factors'] is List
            ? (j['factors'] as List).whereType<Map>().map((e) => Factor.fromJson(Map<String, dynamic>.from(e))).toList()
            : null,
      );
}

int _toInt(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

class LimitExceededException implements Exception {
  @override
  String toString() => 'Günlük analiz hakkı doldu';
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _cachedDeviceId;

/// Günlük hak takibi için cihaz kimliği. Android ID / identifierForVendor alınamazsa
/// rastgele üretilip saklanır (tüm cihazlar aynı "default" kimliği paylaşmasın).
Future<String> getDeviceId() async {
  if (_cachedDeviceId != null) return _cachedDeviceId!;
  String? id;
  try {
    if (Platform.isAndroid) {
      id = await const AndroidId().getId();
    } else if (Platform.isIOS) {
      id = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
    }
  } catch (_) {
    id = null;
  }
  if (id == null || id.isEmpty) {
    final prefs = await SharedPreferences.getInstance();
    id = prefs.getString(StorageKeys.deviceId);
    if (id == null) {
      final rnd = Random.secure();
      id = 'gen-${List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(StorageKeys.deviceId, id);
    }
  }
  return _cachedDeviceId = id;
}

Future<Map<String, dynamic>?> _postJson(String path, Map<String, dynamic> body) async {
  final response = await http
      .post(
        Uri.parse('$apiUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(_timeout);

  Map<String, dynamic>? data;
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map) data = Map<String, dynamic>.from(decoded);
  } catch (_) {
    data = null;
  }

  if (response.statusCode == 403 && data?['limitExceeded'] == true) throw LimitExceededException();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ApiException('${data?['error'] ?? 'Sunucu hatası (${response.statusCode})'}');
  }
  return data;
}

Future<AnalysisResult> analyzeWeather(Mode mode, String locationName, Coords coords) async {
  final endpoint = mode == Mode.glass ? '/api/analyze-weather' : '/api/analyze-car-wash';
  final data = await _postJson(endpoint, {
    'locationName': locationName,
    'coords': coords.toJson(),
    'deviceIdentifier': await getDeviceId(),
  });
  if (data == null) throw ApiException('Sunucudan geçersiz yanıt geldi.');
  return AnalysisResult.fromJson(data);
}

// FCM token'ı ve hatırlatma tercihlerini backend'e kaydeder
Future<void> registerPush({
  required String pushToken,
  required Coords coords,
  required String locationName,
  required bool goodDay,
  required bool rainAfterWash,
  String? lastWashAt,
}) async {
  await _postJson('/api/push/register', {
    'deviceIdentifier': await getDeviceId(),
    'pushToken': pushToken,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'coords': coords.toJson(),
    'locationName': locationName,
    'goodDay': goodDay,
    'rainAfterWash': rainAfterWash,
    'lastWashAt': lastWashAt,
  });
}

// "Bugün yıkadım" bilgisini backend'e iletir (yağmur uyarısı için)
Future<void> reportWash() async {
  await _postJson('/api/push/wash', {'deviceIdentifier': await getDeviceId()});
}
