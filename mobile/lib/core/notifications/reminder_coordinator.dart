import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReminderCoordinator {
  ReminderCoordinator({
    required TodayRepository todayRepository,
    required NotificationScheduler scheduler,
  })  : _todayRepository = todayRepository,
        _scheduler = scheduler;

  final TodayRepository _todayRepository;
  final NotificationScheduler _scheduler;
  Future<void>? _refreshFuture;

  Future<void> refresh() {
    return _refreshFuture ??= _refresh().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<void> _refresh() async {
    final doses = await _todayRepository.loadReminderDoses(days: 30);
    await _scheduler.reconcile(doses);
  }

  Future<void> clear() => _scheduler.reconcile(const []);
}

final reminderCoordinatorProvider = Provider<ReminderCoordinator>((ref) {
  return ReminderCoordinator(
    todayRepository: ref.watch(todayRepositoryProvider),
    scheduler: ref.watch(notificationSchedulerProvider),
  );
});
