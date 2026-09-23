import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses today member group and dose status', () {
    final group = TodayMemberGroup.fromJson(<String, dynamic>{
      'member_id': 'member-1',
      'member_name': 'Amma',
      'relationship': 'mother',
      'local_date': '2026-09-23',
      'timezone': 'Asia/Dhaka',
      'taken_count': 2,
      'total_count': 3,
      'doses': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'dose-1',
          'schedule_id': 'schedule-1',
          'family_member_id': 'member-1',
          'member_medication_id': 'med-1',
          'medication_name': 'Metformin',
          'strength': '500 mg',
          'scheduled_at': '2026-09-23T14:00:00Z',
          'scheduled_local_date': '2026-09-23',
          'scheduled_local_time': '20:00:00',
          'timezone': 'Asia/Dhaka',
          'quantity': '1.000',
          'unit': 'tablet',
          'meal_relation': 'after_food',
          'status': 'pending',
          'snoozed_until': null,
          'taken_at': null,
          'skipped_at': null,
          'missed_at': null,
          'effective_reminder_at': '2026-09-23T14:00:00Z',
        },
      ],
    });

    expect(group.name, 'Amma');
    expect(group.takenCount, 2);
    expect(group.doses.single.status, 'pending');
    expect(group.doses.single.quantityText, '1.000');
  });
}
