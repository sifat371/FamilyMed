import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses schedule response with separate source instruction and reminder times', () {
    final schedule = MedicationSchedule.fromJson(<String, dynamic>{
      'id': 'schedule-1',
      'member_medication_id': 'med-1',
      'raw_instruction': '1+0+1 PC',
      'meal_relation': 'after_food',
      'timezone': 'Asia/Dhaka',
      'start_date': '2026-09-23',
      'end_date': null,
      'status': 'active',
      'times': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'time-1',
          'period': 'morning',
          'local_time': '08:00:00',
          'quantity': '1.000',
          'unit': 'tablet',
          'sort_order': 0,
        },
      ],
    });

    expect(schedule.rawInstruction, '1+0+1 PC');
    expect(schedule.times.single.localTime, '08:00');
    expect(schedule.times.single.quantityText, '1.000');
  });
}
