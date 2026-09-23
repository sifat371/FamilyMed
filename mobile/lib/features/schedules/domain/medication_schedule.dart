class ScheduleTimeEntry {
  const ScheduleTimeEntry({
    required this.id,
    required this.period,
    required this.localTime,
    required this.quantityText,
    required this.unit,
    required this.sortOrder,
  });

  final String id;
  final String period;
  final String localTime;
  final String quantityText;
  final String unit;
  final int sortOrder;

  factory ScheduleTimeEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleTimeEntry(
      id: json['id'].toString(),
      period: json['period'].toString(),
      localTime: _minuteTime(json['local_time'].toString()),
      quantityText: json['quantity'].toString(),
      unit: json['unit'].toString(),
      sortOrder: json['sort_order'] as int,
    );
  }
}

class ScheduleDraftTime {
  const ScheduleDraftTime({
    required this.period,
    required this.localTime,
    required this.quantityText,
    required this.unit,
  });

  final String period;
  final String localTime;
  final String quantityText;
  final String unit;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'period': period,
        'local_time': _minuteTime(localTime),
        'quantity': quantityText,
        'unit': unit.trim(),
      };
}

class ScheduleDraft {
  const ScheduleDraft({
    this.rawInstruction,
    this.mealRelation,
    required this.timezone,
    required this.startDate,
    this.endDate,
    required this.times,
  });

  final String? rawInstruction;
  final String? mealRelation;
  final String timezone;
  final DateTime startDate;
  final DateTime? endDate;
  final List<ScheduleDraftTime> times;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'raw_instruction': _nullableText(rawInstruction),
        'meal_relation': mealRelation,
        'timezone': timezone,
        'start_date': _dateOnly(startDate),
        'end_date': endDate == null ? null : _dateOnly(endDate!),
        'times': times.map((item) => item.toJson()).toList(growable: false),
      };
}

class MedicationSchedule {
  const MedicationSchedule({
    required this.id,
    required this.memberMedicationId,
    this.rawInstruction,
    this.mealRelation,
    required this.timezone,
    required this.startDate,
    this.endDate,
    required this.status,
    required this.times,
  });

  final String id;
  final String memberMedicationId;
  final String? rawInstruction;
  final String? mealRelation;
  final String timezone;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final List<ScheduleTimeEntry> times;

  factory MedicationSchedule.fromJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      id: json['id'].toString(),
      memberMedicationId: json['member_medication_id'].toString(),
      rawInstruction: json['raw_instruction'] as String?,
      mealRelation: json['meal_relation'] as String?,
      timezone: json['timezone'].toString(),
      startDate: DateTime.parse(json['start_date'].toString()),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'].toString()),
      status: json['status'].toString(),
      times: (json['times'] as List<dynamic>)
          .map(
            (item) => ScheduleTimeEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

String _minuteTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}

String _dateOnly(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String? _nullableText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
