// Parla tasarım token'ları — tasarımdaki renkler, yazı tipleri ve ölçüler
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const background = Color(0xFFFBF6EF); // sıcak krem zemin
  static const surface = Color(0xFFFFFFFF); // kartlar
  static const surfaceMuted = Color(0xFFF3E8DA); // segment kontrol zemini, çizgiler
  static const border = Color(0xFFEFE4D6);
  static const ink = Color(0xFF2A1F17); // ana metin, koyu kart
  static const inkSoft = Color(0xFF3A2C22); // koyu kart içi kutu
  static const muted = Color(0xFF6B5B4E); // ikincil metin
  static const primary = Color(0xFFC2501A); // butonlar (beyaz metinle erişilebilir)
  static const primaryPressed = Color(0xFF9E3F12);
  static const sun = Color(0xFFF28C38); // güneş, skor halkası
  static const sunSoft = Color(0xFFF6A15A); // koyu zemin üstü vurgu
  static const peach = Color(0xFFFCE3CC); // "İyi" etiketleri, öne çıkan kart
  static const peachText = Color(0xFF7A3410);
  static const rain = Color(0xFF2F5D7C); // "Bekle" / yağmur durumu
  static const rainSoft = Color(0xFFDCE8F0);
  static const switchOff = Color(0xFFD9CBBB);
  static const ringTrack = Color(0xFF4A3A2E);
  static const ringLow = Color(0xFF7FA3BD);
  static const onInk = Color(0xFFE9DDD0); // koyu kart üstü gövde metni
  static const onInkMuted = Color(0xFFD9CBBB);
}

abstract final class AppRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
}

const double minTouch = 44;

/// Renk → "#rrggbb" (SVG çizimleri için)
String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

// ---------- Yazı stilleri ----------
abstract final class AppText {
  // Bricolage Grotesque: başlıklar
  static TextStyle display({double size = 28, Color color = AppColors.ink, double? height}) =>
      GoogleFonts.bricolageGrotesque(
          fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color, height: height);

  static TextStyle displayBold({double size = 22, Color color = AppColors.ink, double? height}) =>
      GoogleFonts.bricolageGrotesque(fontSize: size, fontWeight: FontWeight.w700, color: color, height: height);

  // Figtree: gövde metni
  static TextStyle figtree({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double? height,
  }) =>
      GoogleFonts.figtree(fontSize: size, fontWeight: weight, color: color, height: height);

  static TextStyle get title => displayBold(size: 22, height: 26 / 22);
  static TextStyle get body => figtree(height: 22 / 15);
  static TextStyle get bodyBold => figtree(weight: FontWeight.w700);
  static TextStyle get caption => figtree(size: 13, color: AppColors.muted);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.background,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.figtreeTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
  );
}
