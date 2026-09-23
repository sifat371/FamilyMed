import 'dart:async';

import 'package:familymed/core/notifications/flutter_notification_scheduler.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationTapEvents {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get doseIds => _controller.stream;

  void notifyDoseTapped(String doseId) => _controller.add(doseId);

  Future<void> dispose() => _controller.close();
}

final notificationTapEventsProvider = Provider<NotificationTapEvents>((ref) {
  final events = NotificationTapEvents();
  ref.onDispose(() => unawaited(events.dispose()));
  return events;
});

final notificationDoseTapProvider = StreamProvider<String>((ref) {
  return ref.watch(notificationTapEventsProvider).doseIds;
});

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  final tapEvents = ref.watch(notificationTapEventsProvider);
  return FlutterNotificationScheduler(
    onDoseTapped: tapEvents.notifyDoseTapped,
  );
});
