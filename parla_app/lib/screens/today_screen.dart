import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/analysis_state.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'why_screen.dart';

const modeOptions = [SegmentOption(Mode.car, 'Araç'), SegmentOption(Mode.glass, 'Cam')];

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  Future<void> _analyze(BuildContext context) async {
    final state = context.read<AnalysisState>();
    final status = await state.runAnalysis(state.mode);
    if (status != RunStatus.limit || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Günlük analiz hakkın doldu', style: AppText.title),
        content: Text(
          'Bir reklam izleyerek yeni hak kazanabilir ya da Premium ile sınırsız analiz yapabilirsin.',
          style: AppText.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Kapat')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(), // TODO: Premium ekranına yönlendir
            child: const Text('Premium'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(), // TODO: AdMob ödüllü reklam burada tetiklenecek
            child: const Text('Reklam izle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AnalysisState>();
    final result = state.resultFor(state.mode);
    final isLoading = state.isLoading(state.mode);
    final modeWord = state.mode == Mode.car ? 'aracını yıkamak' : 'camlarını silmek';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          // Başlık
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${state.locationName} · Bugün',
                        style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(result?.weather?.temp ?? 'Hava durumu', style: AppText.display(size: 26)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconBtn(
                label: 'Hatırlatmalar',
                onPressed: () => HomeShell.goTo(context, AppTab.reminders),
                child: ParlaIcons.bell(),
              ),
            ],
          ),
          if (state.locationError != null) ...[
            const SizedBox(height: 16),
            Text(state.locationError!, style: AppText.caption.copyWith(color: AppColors.rain)),
          ],
          const SizedBox(height: 16),
          SegmentedControl<Mode>(options: modeOptions, value: state.mode, onChanged: (m) => state.mode = m),
          const SizedBox(height: 16),

          // Karar kartı
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.xl)),
            child: result != null ? _VerdictWithResult(result: result) : _VerdictEmpty(state: state, modeWord: modeWord),
          ),

          // Hava bilgileri
          if (result?.weather != null) ...[
            const SizedBox(height: 16),
            _WeatherChips(weather: result!.weather!),
          ] else if (result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hava özeti', style: AppText.caption),
                  const SizedBox(height: 4),
                  Text(result.todaySummary, style: AppText.bodyBold),
                ],
              ),
            ),
          ],

          if (state.errorMsg != null) ...[
            const SizedBox(height: 16),
            Text(state.errorMsg!, style: AppText.caption.copyWith(color: AppColors.rain)),
          ],
          const SizedBox(height: 16),

          // Eylemler
          if (result != null)
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    title: 'Neden?',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WhyScreen(onSetReminder: () => HomeShell.goTo(context, AppTab.reminders)),
                    )),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(title: 'Yeniden analiz et', onPressed: () => _analyze(context), loading: isLoading),
                ),
              ],
            )
          else
            PrimaryButton(title: 'Analiz et', onPressed: () => _analyze(context), loading: isLoading),
        ],
      ),
    );
  }
}

class _WeatherChips extends StatelessWidget {
  const _WeatherChips({required this.weather});

  final WeatherInfo weather;

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (weather.rain != null) WeatherChip(label: 'Yağmur', value: weather.rain!),
      if (weather.wind != null) WeatherChip(label: 'Rüzgar', value: weather.wind!),
      if (weather.uv != null) WeatherChip(label: 'UV', value: weather.uv!),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final (i, chip) in chips.indexed) ...[if (i > 0) const SizedBox(width: 8), chip],
      ],
    );
  }
}

final _verdictTag =AppText.figtree(size: 13, weight: FontWeight.w700, color: AppColors.sunSoft);
final _verdictTitle = AppText.displayBold(size: 22, height: 26 / 22, color: AppColors.background);
final _verdictBody = AppText.figtree(color: AppColors.onInk, height: 22 / 15);

class _VerdictWithResult extends StatelessWidget {
  const _VerdictWithResult({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ScoreRing(score: result.score),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scoreTag(result.score), style: _verdictTag),
                  const SizedBox(height: 6),
                  Text(result.summary, style: _verdictTitle),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(result.reason, style: _verdictBody),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.inkSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(
            children: [
              Text(
                result.bestWindow != null ? 'En iyi saat aralığı' : 'En ideal gün',
                style: AppText.figtree(size: 13, color: AppColors.onInkMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.bestWindow ?? result.bestDay,
                  textAlign: TextAlign.right,
                  style: AppText.figtree(size: 16, weight: FontWeight.w700, color: AppColors.background),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerdictEmpty extends StatelessWidget {
  const _VerdictEmpty({required this.state, required this.modeWord});

  final AnalysisState state;
  final String modeWord;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hava analizi', style: _verdictTag),
        const SizedBox(height: 16),
        Text('Bugün $modeWord için uygun mu?', style: _verdictTitle),
        const SizedBox(height: 16),
        Text(
          '${state.locationName} için yağmur, rüzgar, güneş ve toz tahminine bakıp sana net bir cevap verelim.',
          style: _verdictBody,
        ),
      ],
    );
  }
}
