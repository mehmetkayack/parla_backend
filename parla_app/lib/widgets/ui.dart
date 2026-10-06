import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

// ---------- Basılı durumu olan kutu (butonların temeli) ----------
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.builder,
    this.enabled = true,
    this.semanticsLabel,
  });

  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;
  final bool enabled;
  final String? semanticsLabel;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      label: widget.semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => _set(true) : null,
        onTapUp: active ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: active ? widget.onTap : null,
        child: widget.builder(_pressed && active),
      ),
    );
  }
}

// ---------- Butonlar ----------
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.title, required this.onPressed, this.loading = false, this.disabled = false});

  final String title;
  final VoidCallback onPressed;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final inactive = disabled || loading;
    return _Pressable(
      onTap: onPressed,
      enabled: !inactive,
      builder: (pressed) => Opacity(
        opacity: inactive ? 0.6 : 1,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressed ? AppColors.primaryPressed : AppColors.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: loading
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(title, style: AppText.figtree(size: 17, weight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onPressed,
      builder: (pressed) => Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? AppColors.surfaceMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(title, style: AppText.figtree(size: 16, weight: FontWeight.w600)),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.label, required this.onPressed, required this.child});

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onPressed,
      semanticsLabel: label,
      builder: (pressed) => Container(
        width: minTouch,
        height: minTouch,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? AppColors.surfaceMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

// ---------- Araç / Cam seçici ----------
class SegmentOption<T> {
  const SegmentOption(this.value, this.label);
  final T value;
  final String label;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({super.key, required this.options, required this.value, required this.onChanged});

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          for (final (i, o) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                selected: o.value == value,
                child: _Pressable(
                  onTap: () => onChanged(o.value),
                  builder: (_) {
                    final active = o.value == value;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: minTouch,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        o.label,
                        style: AppText.figtree(
                          weight: active ? FontWeight.w700 : FontWeight.w600,
                          color: active ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- Skor halkası ----------
String scoreTag(int score) {
  if (score >= 80) return 'Harika gün';
  if (score >= 60) return 'Uygun';
  if (score >= 40) return 'Bekleyebilirsin';
  return 'Bugün değil';
}

class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 96});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final color = clamped >= 80
        ? AppColors.sun
        : clamped >= 40
            ? AppColors.sunSoft
            : AppColors.ringLow;
    return Semantics(
      label: 'Skor $clamped / 100',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: clamped / 100, color: color),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$clamped', style: AppText.display(size: 30, color: AppColors.background, height: 1.05)),
                Text('/ 100', style: AppText.figtree(size: 11, color: AppColors.onInkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;
  static const _stroke = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(_stroke / 2, _stroke / 2, size.width - _stroke, size.height - _stroke);
    final track = Paint()
      ..color = AppColors.ringTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

// ---------- Hava bilgisi kutucuğu ----------
class WeatherChip extends StatelessWidget {
  const WeatherChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          children: [
            Text(label, style: AppText.caption),
            const SizedBox(height: 4),
            Text(value, style: AppText.figtree(size: 16, weight: FontWeight.w700), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ---------- Durum etiketi ----------
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: good ? AppColors.peach : AppColors.rainSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        good ? 'İyi' : 'Dikkat',
        style: AppText.figtree(size: 12, weight: FontWeight.w700, color: good ? AppColors.peachText : AppColors.rain),
      ),
    );
  }
}

// ---------- Aç / kapa anahtarı ----------
class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(8), // dokunma alanını büyüt
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 32,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : AppColors.switchOff,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Yardımcılar ----------
Future<void> showInfoDialog(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppText.title),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tamam')),
      ],
    ),
  );
}
