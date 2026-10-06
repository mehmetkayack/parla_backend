import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/analysis_state.dart';
import '../storage_keys.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';

// Güneş, yağmur bulutu ve araç çizimi
final String _illustrationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="342" height="270" viewBox="0 0 342 270" fill="none">
  <circle cx="120" cy="100" r="54" fill="${hex(AppColors.sun)}"/>
  <path d="M120 22v14M120 164v14M42 100h14M184 100h14M65 45l10 10M165 145l10 10M65 155l10-10M165 55l10-10" stroke="${hex(AppColors.sun)}" stroke-width="6" stroke-linecap="round"/>
  <path d="M230 96a26 26 0 0 1 50-6a20 20 0 0 1 8 39h-60a18 18 0 0 1 2-33z" fill="${hex(AppColors.rainSoft)}" stroke="${hex(AppColors.rain)}" stroke-width="3"/>
  <path d="M244 142l-5 12M262 142l-5 12M280 142l-5 12" stroke="${hex(AppColors.rain)}" stroke-width="3" stroke-linecap="round"/>
  <line x1="226" y1="80" x2="300" y2="164" stroke="${hex(AppColors.primary)}" stroke-width="5" stroke-linecap="round"/>
  <path d="M60 238 h160 a12 12 0 0 0 12 -12 v-18 a10 10 0 0 0 -8 -10 l-30 -7 l-22 -24 a14 14 0 0 0 -11 -5 h-50 a14 14 0 0 0 -12 6 l-18 26 l-14 4 a9 9 0 0 0 -7 9 v19 a12 12 0 0 0 12 12 z" fill="${hex(AppColors.ink)}"/>
  <path d="M96 190 l12 -18 h42 l17 18 z" fill="${hex(AppColors.background)}"/>
  <circle cx="92" cy="240" r="16" fill="${hex(AppColors.ink)}" stroke="${hex(AppColors.peach)}" stroke-width="4"/>
  <circle cx="194" cy="240" r="16" fill="${hex(AppColors.ink)}" stroke="${hex(AppColors.peach)}" stroke-width="4"/>
</svg>''';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final Map<String, bool> _tracking = {'car': true, 'glass': true};
  bool _busy = false;

  static const _options = [('car', 'Aracım'), ('glass', 'Camlarım')];

  Future<void> _start() async {
    setState(() => _busy = true);
    await context.read<AnalysisState>().requestLocation();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.onboarded, '1');
    await prefs.setString(StorageKeys.tracking, jsonEncode(_tracking));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  @override
  Widget build(BuildContext context) {
    final anySelected = _tracking.values.any((v) => v);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 28),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.sun, borderRadius: BorderRadius.circular(12)),
                          child: ParlaIcons.sun(size: 20, strokeWidth: 2.2),
                        ),
                        const SizedBox(width: 10),
                        Text('Parla', style: AppText.display(size: 22).copyWith(letterSpacing: -0.4)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      height: 290,
                      decoration: BoxDecoration(color: AppColors.peach, borderRadius: BorderRadius.circular(32)),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: FittedBox(child: SvgPicture.string(_illustrationSvg, width: 342, height: 270)),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Yıkadın, ertesi gün yağmur mu yağdı?',
                      style: AppText.display(size: 32, height: 35 / 32).copyWith(letterSpacing: -0.8),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Parla hava durumunu senin yerine izler; aracını yıkamak ve camlarını silmek için en doğru günü söyler.',
                      style: AppText.figtree(size: 16, color: AppColors.muted, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    Text('Neyi takip edelim?', style: AppText.figtree(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final (i, (key, label)) in _options.indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: _optionTile(key, label)),
                        ],
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      title: 'Konumuma göre başla',
                      onPressed: _start,
                      loading: _busy,
                      disabled: !anySelected,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Konumun yalnızca hava tahmini için kullanılır.',
                      style: AppText.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile(String key, String label) {
    final on = _tracking[key]!;
    return Semantics(
      checked: on,
      label: label,
      child: GestureDetector(
        onTap: () => setState(() => _tracking[key] = !on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: on ? AppColors.primary : AppColors.border, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (on) ...[ParlaIcons.check(), const SizedBox(width: 8)],
              Text(
                label,
                style: AppText.figtree(weight: FontWeight.w700, color: on ? AppColors.ink : AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
