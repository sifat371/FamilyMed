import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_state.dart';
import 'package:familymed/features/auth/presentation/login_screen.dart';
import 'package:familymed/features/auth/presentation/register_screen.dart';
import 'package:familymed/features/welcome/presentation/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<AuthState>(authControllerProvider, (_, __) {
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
        return '/family';
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
        path: '/care-for',
        builder: (context, state) => const _RoutePlaceholder(),
      ),
      GoRoute(
        path: '/family',
        builder: (context, state) => const _RoutePlaceholder(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

bool _isProtected(String path) {
  return path == '/care-for' || path == '/family' || path.startsWith('/family/');
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

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
