import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/analysis_state.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/ui.dart';

/// "Neden bugün?" — skoru oluşturan etkenler
class WhyScreen extends StatelessWidget {
  const WhyScreen({super.key, required this.onSetReminder});

  /// "Hatırlatma kur" → Hatırlatmalar sekmesine geçmek için
  final VoidCallback onSetReminder;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AnalysisState>();
    final result = state.resultFor(state.mode);
    final label = state.mode == Mode.car ? 'Araç yıkama skoru' : 'Cam silme skoru';
    final factors = result?.factors;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                IconBtn(label: 'Geri', onPressed: () => Navigator.of(context).maybePop(), child: ParlaIcons.back()),
                const SizedBox(width: 12),
                Text('Neden bugün?', style: AppText.title),
              ],
            ),
            const SizedBox(height: 16),
            if (result == null)
              Text('Önce Bugün ekranından analiz yapmalısın.', style: AppText.body.copyWith(color: AppColors.muted))
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: AppText.caption),
                          Text('${result.score}',
                              style: AppText.display(size: 56, color: AppColors.primary, height: 60 / 56)
                                  .copyWith(letterSpacing: -1.5)),
                        ],
                      ),
                    ),
                    if (factors != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.peach, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          "${factors.length} etkenden ${factors.where((f) => f.good).length}'i uygun",
                          style: AppText.figtree(size: 13, weight: FontWeight.w700, color: AppColors.peachText),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (factors != null && factors.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Column(
                    children: [
                      for (final (i, f) in factors.indexed)
                        Container(
                          constraints: const BoxConstraints(minHeight: 64),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: i < factors.length - 1
                                ? const Border(bottom: BorderSide(color: AppColors.surfaceMuted))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.name, style: AppText.bodyBold),
                                    Text(f.value, style: AppText.caption),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              StatusTag(good: f.good),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hava özeti', style: AppText.caption),
                      const SizedBox(height: 6),
                      Text(result.todaySummary, style: AppText.bodyBold),
                      const SizedBox(height: 6),
                      Text(result.reason, style: AppText.body.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
              if (result.tip != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('İpucu', style: AppText.figtree(size: 13, weight: FontWeight.w700, color: AppColors.sunSoft)),
                      const SizedBox(height: 6),
                      Text(result.tip!, style: AppText.figtree(color: AppColors.background, height: 22 / 15)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                title: 'Hatırlatma kur',
                onPressed: () {
                  Navigator.of(context).pop();
                  onSetReminder();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
