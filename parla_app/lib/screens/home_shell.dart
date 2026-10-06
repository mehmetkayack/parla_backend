import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/icons.dart';
import 'reminders_screen.dart';
import 'today_screen.dart';
import 'week_screen.dart';

enum AppTab { today, week, reminders }

/// Alt sekmeli ana iskelet: Bugün / Hafta / Hatırlatmalar
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Alt ekranlardan sekme değiştirmek için: HomeShell.goTo(context, AppTab.reminders)
  static void goTo(BuildContext context, AppTab tab) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _tab = AppTab.today;

  void _select(AppTab tab) => setState(() => _tab = tab);

  static final _items = [
    (AppTab.today, 'Bugün', ParlaIcons.sun),
    (AppTab.week, 'Hafta', ParlaIcons.calendar),
    (AppTab.reminders, 'Hatırlatmalar', ParlaIcons.bell),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: const [TodayScreen(), WeekScreen(), RemindersScreen()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (final (tab, label, icon) in _items)
                  Expanded(
                    child: Semantics(
                      selected: _tab == tab,
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () => _select(tab),
                        radius: 40,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            icon(color: _tab == tab ? AppColors.primary : AppColors.muted),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: AppText.figtree(
                                size: 12,
                                weight: FontWeight.w600,
                                color: _tab == tab ? AppColors.primary : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
