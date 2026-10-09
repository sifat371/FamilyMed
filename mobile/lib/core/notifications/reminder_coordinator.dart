import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReminderCoordinator {
  ReminderCoordinator({
    required TodayRepository Function() todayRepository,
    required NotificationScheduler scheduler,
  }) : _todayRepository = todayRepository,
       _scheduler = scheduler;

  final TodayRepository Function() _todayRepository;
  int _generation = 0;
  Future<void> _scheduling = Future<void>.value();
  final NotificationScheduler _scheduler;
  Future<void>? _refreshFuture;

  Future<void> refresh() {
    if (_refreshFuture != null) return _refreshFuture!;
    late final Future<void> pending;
    pending = _refresh(_generation).whenComplete(() {
      if (identical(_refreshFuture, pending)) _refreshFuture = null;
    });
    _refreshFuture = pending;
    return pending;
  }

  Future<void> _refresh(int generation) async {
    final doses = await _todayRepository().loadReminderDoses(days: 30);
    await _reconcile(doses, generation);
  }

  Future<void> _reconcile(List<DoseProjection> doses, int generation) {
    final operation = _scheduling.then((_) async {
      if (generation == _generation) await _scheduler.reconcile(doses);
    });
    // A platform error must not poison later cancellation or retry operations.
    _scheduling = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> clear() {
    _generation++;
    _refreshFuture = null;
    return _reconcile(const [], _generation);
  }
}

final reminderCoordinatorProvider = Provider<ReminderCoordinator>((ref) {
  return ReminderCoordinator(
    todayRepository: () => ref.read(todayRepositoryProvider),
    scheduler: ref.watch(notificationSchedulerProvider),
  );
});
