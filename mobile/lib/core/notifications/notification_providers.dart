import 'package:familymed/core/notifications/flutter_notification_scheduler.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return FlutterNotificationScheduler();
});
