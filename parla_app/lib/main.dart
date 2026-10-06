import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/notifications.dart';
import 'services/reminders.dart';
import 'state/analysis_state.dart';
import 'storage_keys.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();

  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getString(StorageKeys.onboarded) == '1';

  final analysis = AnalysisState();
  analysis.init(); // izin daha önce verildiyse konumu arka planda güncelle

  _restoreReminders(analysis);

  runApp(
    ChangeNotifierProvider.value(
      value: analysis,
      child: ParlaApp(onboarded: onboarded),
    ),
  );
}

/// Açılışta: haftalık planı (açıksa) yeniden kur, FCM token yenilenirse sunucuya bildir.
Future<void> _restoreReminders(AnalysisState analysis) async {
  final reminders = await loadReminderPrefs();
  if (await notificationsAllowed()) {
    await setWeeklyPlan(reminders[ReminderKey.weeklyPlan] ?? false);
  }
  onPushTokenRefresh.listen((_) async {
    final latest = await loadReminderPrefs();
    if (anyPushReminderOn(latest)) {
      await syncPush(reminders: latest, coords: analysis.coords, locationName: analysis.locationName);
    }
  });
}

class ParlaApp extends StatelessWidget {
  const ParlaApp({super.key, required this.onboarded});

  final bool onboarded;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: MaterialApp(
        title: 'Parla',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.light,
        home: onboarded ? const HomeShell() : const OnboardingScreen(),
      ),
    );
  }
}
