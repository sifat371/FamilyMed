import 'package:familymed/features/today/domain/dose_projection.dart';
abstract interface class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> reconcile(List<DoseProjection> doses);
  Future<void> scheduleDose(DoseProjection dose);
  Future<void> cancelDose(String doseId);
  Future<void> snoozeDose(DoseProjection dose);
}

int notificationIdForDose(String doseId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in doseId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
