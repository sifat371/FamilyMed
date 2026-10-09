import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _selectedIndex => location == '/me'
      ? 3
      : location == '/history' || location.endsWith('/history')
      ? 2
      : location.startsWith('/family')
      ? 1
      : 0;

  bool get _showBottomNavigation {
    if (location.endsWith('/edit') ||
        location.endsWith('/routine') ||
        location.endsWith('/reminders') ||
        location.endsWith('/correct') ||
        location.contains('/medications/new')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: _showBottomNavigation
          ? DecoratedBox(
              decoration: const BoxDecoration(
                color: FamilyMedColors.surface,
                border: Border(top: BorderSide(color: FamilyMedColors.border)),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  final target = [
                    '/today',
                    '/family',
                    '/history',
                    '/me',
                  ][index];
                  if (location != target) {
                    context.push(target);
                  }
                },
                destinations: [
                  NavigationDestination(
                    key: const Key('todayTab'),
                    icon: _navIcon(context, 'today', false),
                    selectedIcon: _navIcon(context, 'today', true),
                    label: l10n.todayTitle,
                  ),
                  NavigationDestination(
                    key: const Key('familyTab'),
                    icon: _navIcon(context, 'family', false),
                    selectedIcon: _navIcon(context, 'family', true),
                    label: l10n.familyTab,
                  ),
                  NavigationDestination(
                    key: const Key('historyTab'),
                    icon: _navIcon(context, 'history', false),
                    selectedIcon: _navIcon(context, 'history', true),
                    label: l10n.historyTitle,
                  ),
                  NavigationDestination(
                    key: const Key('meTab'),
                    icon: _navIcon(context, 'me', false),
                    selectedIcon: _navIcon(context, 'me', true),
                    label: l10n.meTab,
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _navIcon(BuildContext context, String name, bool selected) =>
      Image.asset(
        'assets/figma/$name.png',
        width: 20,
        height: 20,
        color: selected
            ? FamilyMedColors.primary
            : FamilyMedColors.textSecondary,
        excludeFromSemantics: true,
      );
}
