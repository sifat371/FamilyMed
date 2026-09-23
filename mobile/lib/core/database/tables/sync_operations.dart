import 'package:drift/drift.dart';

class SyncOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get userId => text().withDefault(const Constant(''))();
  TextColumn get doseId => text()();
  TextColumn get action => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant<int>(0))();
  TextColumn get lastError => text().nullable()();
  BoolColumn get terminalFailure =>
      boolean().withDefault(const Constant<bool>(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}
