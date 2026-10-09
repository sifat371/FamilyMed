import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  int get _selectedIndex => location.startsWith('/family') ? 1 : 0;

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
                border: Border(
                  top: BorderSide(color: FamilyMedColors.border),
                ),
              ),
              child: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          final target = index == 0 ? '/today' : '/family';
          if (location != target) {
            context.go(target);
          }
        },
        destinations: [
          NavigationDestination(
            key: const Key('todayTab'),
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.todayTitle,
          ),
          NavigationDestination(
            key: const Key('familyTab'),
            icon: const Icon(Icons.group_outlined),
            selectedIcon: const Icon(Icons.group),
            label: l10n.familyTab,
          ),
        ],
              ),
            )
          : null,
    );
  }
}
