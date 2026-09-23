import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotificationScheduler implements NotificationScheduler {
  bool permission = false;
  final List<String> scheduled = <String>[];

  @override
  Future<void> cancelDose(String doseId) async {}

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> reconcile(List<DoseProjection> doses) async {
    scheduled
      ..clear()
      ..addAll(doses.map((dose) => dose.id));
  }

  @override
  Future<void> scheduleDose(DoseProjection dose) async {
    scheduled.add(dose.id);
  }

  @override
  Future<void> snoozeDose(DoseProjection dose) async {
    scheduled.add(dose.id);
  }
}

void main() {
  test('production notification provider resolves a scheduler', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(notificationSchedulerProvider),
      returnsNormally,
    );
  });

  test('notification IDs are deterministic and positive', () {
    expect(notificationIdForDose('dose-123'), notificationIdForDose('dose-123'));
    expect(notificationIdForDose('dose-123'), greaterThanOrEqualTo(0));
    expect(notificationIdForDose('dose-123'), lessThan(0x80000000));
  });

  test('notification abstraction remains fakeable when permission is denied', () async {
    final scheduler = FakeNotificationScheduler();
    expect(await scheduler.requestPermission(), isFalse);
    expect(scheduler.scheduled, isEmpty);
  });
}
