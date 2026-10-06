import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/analysis_state.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'today_screen.dart' show modeOptions;

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AnalysisState>();
    final result = state.resultFor(state.mode);
    final week = result?.week;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Bu hafta', style: AppText.display()),
          const SizedBox(height: 14),
          SegmentedControl<Mode>(options: modeOptions, value: state.mode, onChanged: (m) => state.mode = m),
          const SizedBox(height: 14),
          if (result == null)
            _Card(
              children: [
                Text('Önce bugünkü analizi yap', style: AppText.title),
                Text(
                  'Haftalık planı görmek için Bugün ekranında konumuna göre analizi başlat.',
                  style: AppText.body.copyWith(color: AppColors.muted),
                ),
                PrimaryButton(title: 'Bugün ekranına git', onPressed: () => HomeShell.goTo(context, AppTab.today)),
              ],
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.peach, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.sun, borderRadius: BorderRadius.circular(16)),
                    child: ParlaIcons.sun(size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Haftanın en iyi günü',
                            style: AppText.figtree(size: 13, weight: FontWeight.w600, color: AppColors.peachText)),
                        const SizedBox(height: 2),
                        Text(result.bestDay, style: AppText.figtree(size: 17, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (week != null && week.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Column(
                  children: [
                    for (final (i, d) in week.indexed) _DayRow(day: d, last: i == week.length - 1),
                  ],
                ),
              )
            else
              _Card(children: [Text(result.todaySummary, style: AppText.body.copyWith(color: AppColors.muted))]),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.expand((w) => [w, const SizedBox(height: 12)]).toList()..removeLast(),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.last});

  final WeekDay day;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final rainy = day.condition == WeatherCondition.rain;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.day, style: AppText.bodyBold),
                if (day.temp != null) Text(day.temp!, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 28,
            child: Center(
              child: switch (day.condition) {
                WeatherCondition.rain => ParlaIcons.rain(size: 24),
                WeatherCondition.cloud => ParlaIcons.cloud(size: 24),
                WeatherCondition.sun => ParlaIcons.sun(size: 24, color: AppColors.sun),
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: rainy
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration:
                          BoxDecoration(color: AppColors.rainSoft, borderRadius: BorderRadius.circular(10)),
                      child: Text('Bekle',
                          style: AppText.figtree(size: 13, weight: FontWeight.w700, color: AppColors.rain)),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: day.score.clamp(0, 100) / 100,
                      minHeight: 8,
                      color: AppColors.sun,
                      backgroundColor: AppColors.surfaceMuted,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text(rainy ? '—' : '${day.score}', style: AppText.bodyBold, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
