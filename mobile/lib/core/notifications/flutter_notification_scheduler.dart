import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FlutterNotificationScheduler implements NotificationScheduler {
  FlutterNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    void Function(String doseId)? onDoseTapped,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onDoseTapped = onDoseTapped;

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String doseId)? _onDoseTapped;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        handleNotificationPayload(response.payload);
      },
    );
    _initialized = true;
  }

  void handleNotificationPayload(String? payload) {
    if (payload == null || !payload.startsWith('dose:')) return;
    final doseId = payload.substring('dose:'.length);
    if (doseId.isEmpty) return;
    _onDoseTapped?.call(doseId);
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> reconcile(List<DoseProjection> doses) async {
    await _ensureInitialized();
    final pending = await _plugin.pendingNotificationRequests();
    final wanted = doses
        .where((dose) => !_isFinal(dose.status))
        .map((dose) => notificationIdForDose(dose.id))
        .toSet();
    for (final item in pending) {
      if (!wanted.contains(item.id)) await _plugin.cancel(item.id);
    }
    for (final dose in doses.where((dose) => !_isFinal(dose.status))) {
      await scheduleDose(dose);
    }
  }

  @override
  Future<void> scheduleDose(DoseProjection dose) async {
    await _ensureInitialized();
    if (_isFinal(dose.status)) {
      await cancelDose(dose.id);
      return;
    }
    final location = tz.getLocation(dose.timezone);
    final at = tz.TZDateTime.from(dose.effectiveReminderAt, location);
    if (at.isBefore(tz.TZDateTime.now(location))) return;
    await _plugin.zonedSchedule(
      notificationIdForDose(dose.id),
      dose.medicationName,
      '${dose.quantityText} ${dose.unit}',
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'familymed_doses',
          'Medication reminders',
          channelDescription: 'Family medication dose reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'dose:${dose.id}',
    );
  }

  @override
  Future<void> cancelDose(String doseId) async {
    await _ensureInitialized();
    await _plugin.cancel(notificationIdForDose(doseId));
  }

  @override
  Future<void> snoozeDose(DoseProjection dose) => scheduleDose(dose);

  bool _isFinal(String status) =>
      status == 'taken' || status == 'skipped' || status == 'missed';
}
