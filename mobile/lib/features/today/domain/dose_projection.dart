class DoseProjection {
  const DoseProjection({
    required this.id,
    required this.scheduleId,
    required this.familyMemberId,
    required this.memberMedicationId,
    required this.medicationName,
    this.strength,
    required this.scheduledAt,
    required this.scheduledLocalDate,
    required this.scheduledLocalTime,
    required this.timezone,
    required this.quantityText,
    required this.unit,
    this.mealRelation,
    required this.status,
    this.snoozedUntil,
    this.takenAt,
    this.skippedAt,
    this.missedAt,
    required this.effectiveReminderAt,
  });

  final String id;
  final String scheduleId;
  final String familyMemberId;
  final String memberMedicationId;
  final String medicationName;
  final String? strength;
  final DateTime scheduledAt;
  final String scheduledLocalDate;
  final String scheduledLocalTime;
  final String timezone;
  final String quantityText;
  final String unit;
  final String? mealRelation;
  final String status;
  final DateTime? snoozedUntil;
  final DateTime? takenAt;
  final DateTime? skippedAt;
  final DateTime? missedAt;
  final DateTime effectiveReminderAt;

  factory DoseProjection.fromJson(Map<String, dynamic> json) {
    final scheduledAt = DateTime.parse(json['scheduled_at'].toString()).toUtc();
    return DoseProjection(
      id: json['id'].toString(),
      scheduleId: json['schedule_id'].toString(),
      familyMemberId: json['family_member_id'].toString(),
      memberMedicationId: json['member_medication_id'].toString(),
      medicationName: _medicationName(json),
      strength: _optionalText(
        json['strength'] ??
            (json['medication'] is Map
                ? (json['medication'] as Map)['strength']
                : null),
      ),
      scheduledAt: scheduledAt,
      scheduledLocalDate: json['scheduled_local_date'].toString(),
      scheduledLocalTime: _minuteTime(json['scheduled_local_time'].toString()),
      timezone: json['timezone'].toString(),
      quantityText: json['quantity'].toString(),
      unit: json['unit'].toString(),
      mealRelation: json['meal_relation'] as String?,
      status: json['status'].toString(),
      snoozedUntil: _optionalUtc(json['snoozed_until']),
      takenAt: _optionalUtc(json['taken_at']),
      skippedAt: _optionalUtc(json['skipped_at']),
      missedAt: _optionalUtc(json['missed_at']),
      effectiveReminderAt: json['effective_reminder_at'] == null
          ? scheduledAt
          : DateTime.parse(json['effective_reminder_at'].toString()).toUtc(),
    );
  }

  DoseProjection copyWith({
    String? status,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    DateTime? takenAt,
    DateTime? skippedAt,
    DateTime? missedAt,
    DateTime? effectiveReminderAt,
  }) {
    return DoseProjection(
      id: id,
      scheduleId: scheduleId,
      familyMemberId: familyMemberId,
      memberMedicationId: memberMedicationId,
      medicationName: medicationName,
      strength: strength,
      scheduledAt: scheduledAt,
      scheduledLocalDate: scheduledLocalDate,
      scheduledLocalTime: scheduledLocalTime,
      timezone: timezone,
      quantityText: quantityText,
      unit: unit,
      mealRelation: mealRelation,
      status: status ?? this.status,
      snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
      takenAt: takenAt ?? this.takenAt,
      skippedAt: skippedAt ?? this.skippedAt,
      missedAt: missedAt ?? this.missedAt,
      effectiveReminderAt: effectiveReminderAt ?? this.effectiveReminderAt,
    );
  }
}


String _medicationName(Map<String, dynamic> json) {
  final direct = json['medication_name'] ?? json['display_name'];
  if (direct != null && direct.toString().trim().isNotEmpty) {
    return direct.toString();
  }
  final medication = json['medication'];
  if (medication is Map) {
    final nested = medication['display_name'] ?? medication['name'];
    if (nested != null && nested.toString().trim().isNotEmpty) {
      return nested.toString();
    }
  }
  return 'Medication';
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _optionalUtc(Object? value) {
  return value == null ? null : DateTime.parse(value.toString()).toUtc();
}

String _minuteTime(String value) {
  final parts = value.split(':');
  return parts.length < 2 ? value : '${parts[0]}:${parts[1]}';
}
