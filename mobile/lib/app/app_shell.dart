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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
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
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.todayTitle,
          ),
          NavigationDestination(
            key: const Key('familyTab'),
            icon: const Icon(Icons.family_restroom_outlined),
            selectedIcon: const Icon(Icons.family_restroom),
            label: l10n.familyTab,
          ),
        ],
      ),
    );
  }
}
