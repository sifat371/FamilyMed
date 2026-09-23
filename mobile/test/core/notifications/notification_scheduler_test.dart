import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/flutter_notification_scheduler.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LaunchNotificationsPlugin extends FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async {
    return const NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'dose:dose-launch',
      ),
    );
  }
}

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

  test('notification abstraction remains fakeable when permission is denied',
      () async {
    final scheduler = FakeNotificationScheduler();
    expect(await scheduler.requestPermission(), isFalse);
    expect(scheduler.scheduled, isEmpty);
  });

  test('production scheduler forwards dose notification payload', () {
    String? tappedDoseId;
    final scheduler = FlutterNotificationScheduler(
      onDoseTapped: (doseId) => tappedDoseId = doseId,
    );

    scheduler.handleNotificationPayload('dose:dose-123');

    expect(tappedDoseId, 'dose-123');
  });

  test('production scheduler forwards notification that launched the app',
      () async {
    String? tappedDoseId;
    final scheduler = FlutterNotificationScheduler(
      plugin: _LaunchNotificationsPlugin(),
      onDoseTapped: (doseId) => tappedDoseId = doseId,
    );

    await scheduler.requestPermission();

    expect(tappedDoseId, 'dose-launch');
  });
}
