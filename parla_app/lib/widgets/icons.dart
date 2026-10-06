import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

// Tasarımdaki çizgi ikonlar (24x24). Tek renkli oldukları için renk ColorFilter ile verilir.
String _svg(String body, double strokeWidth) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
    'stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">$body</svg>';

Widget _icon(String svg, double size, Color color) => SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );

abstract final class ParlaIcons {
  static Widget sun({double size = 22, Color color = AppColors.ink, double strokeWidth = 2}) => _icon(
      _svg(
          '<circle cx="12" cy="12" r="4"/>'
          '<path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
          strokeWidth),
      size,
      color);

  static Widget cloud({double size = 22, Color color = AppColors.muted, double strokeWidth = 2}) => _icon(
      _svg('<path d="M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9.5 4.3 4.3 0 0 0 7 18z"/>', strokeWidth), size, color);

  static Widget rain({double size = 22, Color color = AppColors.rain, double strokeWidth = 2}) => _icon(
      _svg(
          '<path d="M7 15h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 6.5 4.3 4.3 0 0 0 7 15z"/>'
          '<path d="M9 18l-1 3M13 18l-1 3M17 18l-1 3"/>',
          strokeWidth),
      size,
      color);

  static Widget bell({double size = 22, Color color = AppColors.ink, double strokeWidth = 1.8}) => _icon(
      _svg('<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
          strokeWidth),
      size,
      color);

  static Widget calendar({double size = 22, Color color = AppColors.ink, double strokeWidth = 1.8}) => _icon(
      _svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>', strokeWidth),
      size,
      color);

  static Widget back({double size = 20, Color color = AppColors.ink, double strokeWidth = 2}) =>
      _icon(_svg('<path d="M15 5l-7 7 7 7"/>', strokeWidth), size, color);

  static Widget check({double size = 18, Color color = AppColors.primary, double strokeWidth = 2.4}) =>
      _icon(_svg('<path d="M5 12l5 5L20 7"/>', strokeWidth), size, color);

  static Widget wind({double size = 20, Color color = AppColors.primary, double strokeWidth = 2}) => _icon(
      _svg('<path d="M3 8h11a3 3 0 1 0-3-3M3 12h16a3 3 0 1 1-3 3M3 16h8"/>', strokeWidth), size, color);
}
