import 'dart:async';

import 'package:familymed/app/app_shell.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_state.dart';
import 'package:familymed/features/auth/presentation/login_screen.dart';
import 'package:familymed/features/auth/presentation/register_screen.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/doses/presentation/dose_action_screen.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/presentation/add_family_member_screen.dart';
import 'package:familymed/features/family/presentation/family_list_screen.dart';
import 'package:familymed/features/family/presentation/member_profile_screen.dart';
import 'package:familymed/features/family/presentation/who_do_you_care_for_screen.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/presentation/correct_record_screen.dart';
import 'package:familymed/features/history/presentation/member_history_screen.dart';
import 'package:familymed/features/medications/presentation/add_manual_medication_screen.dart';
import 'package:familymed/features/medications/presentation/edit_medication_screen.dart';
import 'package:familymed/features/schedules/presentation/enable_reminders_screen.dart';
import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/features/today/presentation/today_screen.dart';
import 'package:familymed/features/welcome/presentation/welcome_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<AuthState>(authControllerProvider, (_, _) {
    refreshNotifier.refresh();
  });

  final router = GoRouter(
    initialLocation: '/welcome',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;

      if (auth.status == AuthStatus.loading) {
        return path == '/splash' ? null : '/splash';
      }

      if (auth.status == AuthStatus.unauthenticated) {
        if (path == '/splash') return '/welcome';
        if (_isProtected(path)) return '/login';
        return null;
      }

      if (path == '/welcome' || path == '/splash') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const _AuthenticatedLandingScreen(),
      ),
      GoRoute(
        path: '/care-for',
        builder: (context, state) => const WhoDoYouCareForScreen(),
      ),
      GoRoute(
        path: '/family/new',
        builder: (context, state) => AddFamilyMemberScreen(
          initialRelationship: state.uri.queryParameters['relationship'] ?? 'mother',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/today',
            builder: (context, state) => const TodayScreen(),
          ),
          GoRoute(
            path: '/doses/:doseId/correct',
            builder: (context, state) => CorrectRecordScreen(
              doseId: state.pathParameters['doseId']!,
              repository: ref.read(doseRepositoryProvider),
              initialStatus: state.uri.queryParameters['status'] ?? 'missed',
            ),
          ),
          GoRoute(
            path: '/doses/:doseId',
            builder: (context, state) => DoseActionScreen(
              doseId: state.pathParameters['doseId']!,
              repository: ref.read(doseRepositoryProvider),
            ),
          ),
          GoRoute(
            path: '/family',
            builder: (context, state) => const FamilyListScreen(),
          ),
          GoRoute(
            path: '/family/:memberId/history',
            builder: (context, state) => MemberHistoryScreen(
              memberId: state.pathParameters['memberId']!,
              repository: ref.read(historyRepositoryProvider),
            ),
          ),
          GoRoute(
            path: '/family/:memberId/medications/new',
            builder: (context, state) => AddManualMedicationScreen(
              memberId: state.pathParameters['memberId']!,
            ),
          ),
          GoRoute(
            path: '/family/:memberId/medications/:medicationId/edit',
            builder: (context, state) => EditMedicationScreen(
              memberId: state.pathParameters['memberId']!,
              medicationId: state.pathParameters['medicationId']!,
            ),
          ),
          GoRoute(
            path: '/family/:memberId/medications/:medicationId/routine',
            builder: (context, state) => SetRoutineScreen(
              memberId: state.pathParameters['memberId']!,
              medicationId: state.pathParameters['medicationId']!,
            ),
          ),
          GoRoute(
            path: '/family/:memberId/medications/:medicationId/reminders',
            builder: (context, state) => EnableRemindersScreen(
              memberId: state.pathParameters['memberId']!,
            ),
          ),
          GoRoute(
            path: '/family/:memberId/reminders',
            builder: (context, state) => EnableRemindersScreen(
              memberId: state.pathParameters['memberId']!,
            ),
          ),
          GoRoute(
            path: '/family/:memberId',
            builder: (context, state) => MemberProfileScreen(
              memberId: state.pathParameters['memberId']!,
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

bool _isProtected(String path) {
  return path == '/home' ||
      path == '/care-for' ||
      path == '/today' ||
      path.startsWith('/doses/') ||
      path == '/family' ||
      path.startsWith('/family/');
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AuthenticatedLandingScreen extends ConsumerStatefulWidget {
  const _AuthenticatedLandingScreen();

  @override
  ConsumerState<_AuthenticatedLandingScreen> createState() =>
      _AuthenticatedLandingScreenState();
}

class _AuthenticatedLandingScreenState
    extends ConsumerState<_AuthenticatedLandingScreen> {
  bool _failed = false;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveDestination());
  }

  Future<void> _resolveDestination() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _failed = false;
    });

    try {
      final members = await ref.read(familyRepositoryProvider).listMembers();
      if (!mounted) return;
      context.go(members.isEmpty ? '/care-for' : '/today');
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.networkError),
                    const SizedBox(height: 12),
                    IconButton(
                      onPressed: _resolveDestination,
                      tooltip: l10n.networkError,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
