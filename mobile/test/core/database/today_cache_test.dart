import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema version 3 scopes cached medication data to an account', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 3);
    for (final table in <String>[
      'cached_today_members',
      'cached_doses',
      'sync_operations',
    ]) {
      final columns = await database.customSelect('PRAGMA table_info($table)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('user_id'), reason: '$table must be account-scoped');
    }
  });
}
