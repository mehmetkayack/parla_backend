import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart' show reportWash;
import '../services/notifications.dart';
import '../services/reminders.dart';
import '../state/analysis_state.dart';
import '../storage_keys.dart';
import '../theme.dart';
import '../widgets/ui.dart';

const _items = [
  (ReminderKey.goodDay, 'Uygun gün gelince haber ver', 'Skor 80 üstüne çıkınca sabah bildirimi'),
  (ReminderKey.rainAfterWash, 'Yıkadıktan sonra yağmur uyarısı', '48 saat içinde yağmur varsa önceden söyler'),
  (ReminderKey.weeklyPlan, 'Haftalık plan', 'Her pazar 19:00, haftanın en iyi günleri'),
  (ReminderKey.glass, 'Cam silme hatırlatması', 'Güneşin çekildiği saate göre'),
];

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  ReminderPrefs? _reminders;
  String? _lastWash;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final reminders = await loadReminderPrefs();
    if (!mounted) return;
    setState(() {
      _reminders = reminders;
      _lastWash = prefs.getString(StorageKeys.lastWash);
      _streak = int.tryParse(prefs.getString(StorageKeys.streak) ?? '') ?? 0;
    });
    // Açık push hatırlatması varsa konum/token değişikliklerini sessizce sunucuya bildir
    if (anyPushReminderOn(reminders) && await notificationsAllowed()) {
      await _sync(reminders, silent: true);
    }
  }

  Future<bool> _sync(ReminderPrefs reminders, {required bool silent}) async {
    if (!mounted) return false;
    final state = context.read<AnalysisState>();
    final result = await syncPush(reminders: reminders, coords: state.coords, locationName: state.locationName);
    if (result == PushSyncResult.ok) return true;
    if (!silent && mounted) {
      final (title, message) = switch (result) {
        PushSyncResult.noToken => (
            'Anlık bildirim kurulamadı',
            'Bildirim kaydı yapılamadı. İnternet bağlantını kontrol et; sorun sürerse uygulamayı yeniden başlat.'
          ),
        _ => ('Sunucuya ulaşılamadı', 'Hatırlatma tercihin kaydedilemedi. Biraz sonra tekrar dene.'),
      };
      await showInfoDialog(context, title, message);
    }
    return false;
  }

  Future<void> _toggle(ReminderKey key, bool value) async {
    final current = _reminders;
    if (current == null) return;
    if (value && !await ensureNotificationPermission()) {
      if (mounted) {
        await showInfoDialog(context, 'Bildirim izni kapalı',
            'Hatırlatma alabilmek için telefon ayarlarından Parla bildirimlerini aç.');
      }
      return;
    }
    final next = {...current, key: value};
    if (pushReminderKeys.contains(key) && !await _sync(next, silent: false) && value) {
      return; // sunucuya kaydedilemediyse anahtarı açık gösterme
    }
    if (!mounted) return;
    setState(() => _reminders = next);
    await saveReminderPrefs(next);
    if (key == ReminderKey.weeklyPlan) await setWeeklyPlan(value);
    // "glass" hatırlatması henüz bağlı değil: güneşin çekildiği saati backend'in hesaplaması gerekir.
  }

  int? _daysSince(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    if (date == null) return null;
    return DateTime.now().difference(date).inDays;
  }

  Future<void> _markWashed() async {
    final since = _daysSince(_lastWash);
    if (since == 0) return; // bugün zaten işaretlendi
    final nextStreak = since != null && since <= 14 ? _streak + 1 : 1;
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _lastWash = now;
      _streak = nextStreak;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.lastWash, now);
    await prefs.setString(StorageKeys.streak, '$nextStreak');
    // Yağmur uyarısı için sunucuya bildir (kayıtlı değilse sunucu yok sayar)
    if (_reminders?[ReminderKey.rainAfterWash] ?? false) {
      reportWash().catchError((Object e) => debugPrint('Yıkama bildirilemedi: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = _reminders;
    final since = _daysSince(_lastWash);
    final lastText = since == null ? 'Henüz kayıt yok' : (since == 0 ? 'Bugün' : '$since gün önce');
    final doneToday = since == 0;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Hatırlatmalar', style: AppText.display()),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Son araç yıkaman', style: AppText.caption),
                        const SizedBox(height: 2),
                        Text(lastText, style: AppText.title),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Temiz seri', style: AppText.caption),
                        const SizedBox(height: 2),
                        Text('$_streak kez', style: AppText.title.copyWith(color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  enabled: !doneToday,
                  child: GestureDetector(
                    onTap: doneToday ? null : _markWashed,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: doneToday ? AppColors.peach : AppColors.ink,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        doneToday ? 'Kaydedildi, harika iş!' : 'Bugün yıkadım',
                        style: AppText.figtree(
                          size: 16,
                          weight: FontWeight.w700,
                          color: doneToday ? AppColors.peachText : AppColors.background,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                for (final (i, (key, title, sub)) in _items.indexed)
                  Container(
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: i < _items.length - 1
                          ? const Border(bottom: BorderSide(color: AppColors.surfaceMuted))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AppText.bodyBold),
                              const SizedBox(height: 2),
                              Text(sub, style: AppText.caption),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ToggleSwitch(
                          label: title,
                          value: reminders?[key] ?? false,
                          onChanged: (v) => _toggle(key, v),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
