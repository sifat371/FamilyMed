import 'package:drift/drift.dart';

class CachedTodayMembers extends Table {
  TextColumn get memberId => text()();
  TextColumn get name => text()();
  TextColumn get relationship => text()();
  TextColumn get localDate => text()();
  TextColumn get timezone => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{memberId};
}
