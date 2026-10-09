import 'package:familymed/app/app.dart';
import 'package:familymed/app/router.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/account/data/account_repository.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'medications/manual_medication_flow_test.dart' as fixtures;

class _AccountRepository implements AccountRepository {
  bool fail = false;
  int saves = 0;
  @override
  Future<CurrentUser> update({
    required String name,
    required String language,
  }) async {
    saves++;
    if (fail) throw const ApiError(code: 'NETWORK_ERROR', message: 'Offline');
    return CurrentUser(
      id: fixtures.currentUser.id,
      name: name.trim(),
      email: fixtures.currentUser.email,
      preferredLanguage: language,
      timezone: 'Asia/Dhaka',
    );
  }
}

class _HistoryRepository implements HistoryRepository {
  bool fail = false;
  final loadedIds = <String>[];
  @override
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    loadedIds.add(memberId);
    if (fail) throw const ApiError(code: 'NETWORK_ERROR', message: 'Offline');
    return MemberHistory(
      memberId: memberId,
      memberName: 'Amma',
      timezone: 'Asia/Dhaka',
      fromDate: '2026-09-08',
      toDate: '2026-10-08',
      markedAdherencePercentage: null,
      days: const [],
    );
  }
}

void main() {
  testWidgets('Android back follows history across all four tabs', (tester) async {
    final container = fixtures.makeContainer(
      fixtures.RecordingMedicationRepository(),
      overrides: [historyRepositoryProvider.overrideWithValue(_HistoryRepository())],
    );
    addTearDown(container.dispose);
    await fixtures.pumpApp(tester, container);

    expect(fixtures.currentPath(container), '/today');

    await tester.tap(find.byKey(const Key('familyTab')));
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/family');
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);

    await tester.tap(find.byKey(const Key('historyTab')));
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/history');
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);

    await tester.tap(find.byKey(const Key('meTab')));
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/me');
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/history');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/family');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/today');
  });

  testWidgets('Android back returns profile to family then Today', (tester) async {
    final container = fixtures.makeContainer(fixtures.RecordingMedicationRepository());
    addTearDown(container.dispose);
    await fixtures.pumpApp(tester, container);

    await tester.tap(find.byKey(const Key('familyTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amma'));
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/family/member-id');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/family');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixtures.currentPath(container), '/today');
  });

  testWidgets(
    'four tabs reach history and account; account saves and signs out',
    (tester) async {
      final account = _AccountRepository();
      final history = _HistoryRepository();
      final container = fixtures.makeContainer(
        fixtures.RecordingMedicationRepository(),
        overrides: [
          accountRepositoryProvider.overrideWithValue(account),
          historyRepositoryProvider.overrideWithValue(history),
        ],
      );
      addTearDown(() {
        container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FamilyMedApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await tester.tap(find.byKey(const Key('historyTab')));
      await tester.pumpAndSettle();
      expect(history.loadedIds, ['member-id']);
      expect(find.text('No dose records in this period.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('meTab')));
      await tester.pumpAndSettle();
      expect(find.text(fixtures.currentUser.email), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('accountName')),
        'Updated name',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
      await tester.pumpAndSettle();
      expect(account.saves, 1);
      expect(container.read(authControllerProvider).user!.name, 'Updated name');
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accountSignOut')));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).user, isNull);
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loginEmail')), findsOneWidget);
    },
  );

  testWidgets('failed account save retains input and does not change session', (
    tester,
  ) async {
        final account = _AccountRepository()..fail = true;
    final container = fixtures.makeContainer(
      fixtures.RecordingMedicationRepository(),
      overrides: [accountRepositoryProvider.overrideWithValue(account)],
    );
    addTearDown(() {
      container.dispose();
    });
    await fixtures.pumpApp(tester, container);
    container.read(routerProvider).go('/me');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('accountName')), 'Unsaved');
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    expect(
      container.read(authControllerProvider).user!.name,
      fixtures.currentUser.name,
    );
    account.fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).user!.name, 'Unsaved');
  });
}
