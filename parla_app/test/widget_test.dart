import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:parla/services/api.dart';
import 'package:parla/widgets/ui.dart';

void main() {
  // Testte internetten font indirilmesin
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AnalysisResult.fromJson', () {
    test('backend\'in bugünkü minimal yanıtını okur', () {
      final r = AnalysisResult.fromJson({
        'todaySummary': 'Güneşli',
        'bestDay': '26 Eylül Cuma',
        'score': 87,
        'summary': 'Tam gün!',
        'reason': 'Yağış yok, rüzgar hafif.',
      });
      expect(r.score, 87);
      expect(r.bestDay, '26 Eylül Cuma');
      expect(r.week, isNull);
      expect(r.factors, isNull);
      expect(r.weather, isNull);
    });

    test('isteğe bağlı alanları ve ondalıklı/metin skoru okur', () {
      final r = AnalysisResult.fromJson({
        'todaySummary': 'x',
        'bestDay': 'y',
        'score': '72',
        'summary': 's',
        'reason': 'r',
        'weather': {'temp': '23°', 'rain': '%5', 'wind': 12},
        'week': [
          {'day': 'Cum', 'condition': 'rain', 'score': 10.6},
          {'day': 'Cmt', 'condition': 'bilinmeyen', 'score': 90},
        ],
        'factors': [
          {'name': 'Yağmur', 'value': '%5', 'status': 'good'},
          {'name': 'Rüzgar', 'value': '30 km/s', 'status': 'warn'},
        ],
      });
      expect(r.score, 72);
      expect(r.weather!.wind, '12');
      expect(r.week!.first.condition, WeatherCondition.rain);
      expect(r.week!.first.score, 11);
      expect(r.week![1].condition, WeatherCondition.sun);
      expect(r.factors!.where((f) => f.good).length, 1);
    });
  });

  test('scoreTag eşikleri', () {
    expect(scoreTag(80), 'Harika gün');
    expect(scoreTag(60), 'Uygun');
    expect(scoreTag(40), 'Bekleyebilirsin');
    expect(scoreTag(39), 'Bugün değil');
  });

  testWidgets('ToggleSwitch dokununca ters değeri bildirir', (tester) async {
    bool? received;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ToggleSwitch(value: false, label: 'test', onChanged: (v) => received = v)),
    ));
    await tester.tap(find.byType(ToggleSwitch));
    expect(received, isTrue);
  });
}
