import 'package:drift/drift.dart';

class CachedDoses extends Table {
  TextColumn get doseId => text()();
  TextColumn get userId => text().withDefault(const Constant(''))();
  BoolColumn get reminderEligible =>
      boolean().withDefault(const Constant<bool>(false))();
  TextColumn get scheduleId => text()();
  TextColumn get memberId => text()();
  TextColumn get memberName => text().withDefault(const Constant(''))();
  TextColumn get medicationId => text()();
  TextColumn get medicationName => text()();
  TextColumn get strength => text().nullable()();
  TextColumn get quantityText => text()();
  TextColumn get unit => text()();
  TextColumn get mealRelation => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get scheduledLocalDate => text()();
  TextColumn get scheduledLocalTime => text()();
  TextColumn get timezone => text()();
  TextColumn get status => text()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get takenAt => dateTime().nullable()();
  DateTimeColumn get skippedAt => dateTime().nullable()();
  DateTimeColumn get missedAt => dateTime().nullable()();
  DateTimeColumn get effectiveReminderAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{doseId};
}
