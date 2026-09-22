import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema version 2 exposes today cache and sync tables', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 2);
    final tables = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, containsAll(<String>[
      'cached_today_members',
      'cached_doses',
      'sync_operations',
    ]));
  });
}
