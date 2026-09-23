import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens a fresh local database at schema version 3', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 3);
    final row = await database.customSelect('SELECT 1 AS value').getSingle();
    expect(row.read<int>('value'), 1);
  });
}
