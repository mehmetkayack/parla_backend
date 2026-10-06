import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api.dart';

enum RunStatus { ok, limit, error }

// Varsayılan konum: Ayvalık / Balıkesir
const _defaultCoords = Coords(39.319, 26.6936);
const _defaultLocationName = 'Ayvalık, Balıkesir';

class AnalysisState extends ChangeNotifier {
  Mode _mode = Mode.glass;
  String _locationName = _defaultLocationName;
  Coords _coords = _defaultCoords;
  String? _locationError;
  String? _errorMsg;
  final Map<Mode, AnalysisResult?> _results = {Mode.glass: null, Mode.car: null};
  final Map<Mode, bool> _loading = {Mode.glass: false, Mode.car: false};

  Mode get mode => _mode;
  String get locationName => _locationName;
  Coords get coords => _coords;
  String? get locationError => _locationError;
  String? get errorMsg => _errorMsg;
  AnalysisResult? resultFor(Mode m) => _results[m];
  bool isLoading(Mode m) => _loading[m] ?? false;

  set mode(Mode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  /// Açılışta: izin daha önce verildiyse konumu sessizce güncelle
  Future<void> init() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      await _readPosition();
    }
  }

  /// Onboarding'deki "Konumuma göre başla" butonu bunu çağırır
  Future<void> requestLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _setLocationError('Konum servisi kapalı. Varsayılan konum kullanılıyor.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _setLocationError('Konum izni verilmedi. Varsayılan konum kullanılıyor.');
      return;
    }
    await _readPosition();
  }

  Future<void> _readPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
      _coords = Coords(pos.latitude, pos.longitude);
      _locationError = null;
      notifyListeners();

      final places = await Geocoding().placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
        locale: const Locale('tr', 'TR'),
      );
      if (places.isNotEmpty) {
        final p = places.first;
        final city = _firstNonEmpty([p.administrativeArea, p.locality]);
        final district = _firstNonEmpty([p.subAdministrativeArea, p.subLocality, p.locality]);
        _locationName = district.isNotEmpty && city.isNotEmpty && district != city
            ? '$district, $city'
            : (city.isNotEmpty ? city : (district.isNotEmpty ? district : 'Konumum'));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Konum hatası: $e');
      _setLocationError('Konum alınamadı. Varsayılan konum kullanılıyor.');
    }
  }

  static String _firstNonEmpty(List<String?> values) =>
      values.firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => '')!.trim();

  void _setLocationError(String msg) {
    _locationError = msg;
    notifyListeners();
  }

  Future<RunStatus> runAnalysis(Mode m) async {
    _loading[m] = true;
    _errorMsg = null;
    notifyListeners();
    try {
      _results[m] = await analyzeWeather(m, _locationName, _coords);
      return RunStatus.ok;
    } on LimitExceededException {
      return RunStatus.limit;
    } catch (e) {
      debugPrint('Analiz hatası: $e');
      _errorMsg = 'Sunucuya bağlanılamadı. İnternet bağlantını kontrol edip tekrar dene.';
      return RunStatus.error;
    } finally {
      _loading[m] = false;
      notifyListeners();
    }
  }
}
