import 'dart:async';

import 'package:familymed/app/router.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_state.dart';
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
      unawaited(ref.read(syncCoordinatorProvider).drain());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated &&
          previous?.status != AuthStatus.authenticated) {
        unawaited(ref.read(syncCoordinatorProvider).drain());
      }
    });

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: FamilyMedTheme.light,
      locale: widget.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
