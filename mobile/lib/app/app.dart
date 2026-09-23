import 'dart:async';

import 'package:familymed/app/router.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_state.dart';
import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FamilyMedApp extends ConsumerStatefulWidget {
  const FamilyMedApp({super.key, this.locale});

  final Locale? locale;

  @override
  ConsumerState<FamilyMedApp> createState() => _FamilyMedAppState();
}

class _FamilyMedAppState extends ConsumerState<FamilyMedApp>
    with WidgetsBindingObserver {
  bool _showSyncFailure = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncAndRefreshReminders());
    }
  }

  Future<void> _syncAndRefreshReminders() async {
    if (ref.read(authControllerProvider).status != AuthStatus.authenticated) {
      return;
    }
    await ref.read(syncCoordinatorProvider).drain();
    try {
      await ref.read(reminderCoordinatorProvider).refresh();
    } on Object {
      // Reminder refresh is best-effort. The canonical routine remains active.
    }
  }

  Future<void> _cancelSessionReminders() async {
    try {
      await ref.read(reminderCoordinatorProvider).clear();
    } on Object {
      // Session teardown should not be blocked by platform notification errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated &&
          previous?.status != AuthStatus.authenticated) {
        unawaited(_syncAndRefreshReminders());
      } else if (next.status == AuthStatus.unauthenticated &&
          previous?.status == AuthStatus.authenticated) {
        unawaited(_cancelSessionReminders());
      }
    });
    ref.listen<AsyncValue<SyncEvent>>(syncEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event.kind == SyncEventKind.terminalFailure && mounted) {
          setState(() => _showSyncFailure = true);
        }
      });
    });
    ref.listen<AsyncValue<String>>(notificationDoseTapProvider, (previous, next) {
      next.whenData((doseId) {
        ref.read(routerProvider).go('/doses/$doseId');
      });
    });

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: FamilyMedTheme.light,
      locale: widget.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        if (!_showSyncFailure) return child ?? const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.syncDoseChangeFailed)),
                        IconButton(
                          onPressed: () {
                            setState(() => _showSyncFailure = false);
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
