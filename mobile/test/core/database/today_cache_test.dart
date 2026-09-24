import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema version 5 scopes cached medication data to an account', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 5);
    for (final table in <String>[
      'cached_today_members',
      'cached_doses',
      'sync_operations',
    ]) {
      final columns = await database.customSelect('PRAGMA table_info($table)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('user_id'), reason: '$table must be account-scoped');
      if (table == 'cached_doses') {
        expect(
          names,
          contains('reminder_eligible'),
          reason: 'cached reminder eligibility must survive offline refresh',
        );
        expect(
          names,
          contains('member_name'),
          reason: 'cached reminders must retain family-member identity',
        );
      }
    }
  });
}
