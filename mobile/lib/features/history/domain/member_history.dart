import 'package:familymed/features/today/domain/dose_projection.dart';

class DoseHistoryEvent {
  const DoseHistoryEvent({
    required this.action,
    required this.occurredAt,
    required this.recordedAt,
    required this.metadata,
  });

  final String action;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final Map<String, dynamic> metadata;

  factory DoseHistoryEvent.fromJson(Map<String, dynamic> json) {
    return DoseHistoryEvent(
      action: json['action'].toString(),
      occurredAt: DateTime.parse(json['occurred_at'].toString()).toUtc(),
      recordedAt: DateTime.parse(json['recorded_at'].toString()).toUtc(),
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class HistoryDose {
  const HistoryDose({
    required this.dose,
    required this.events,
  });

  final DoseProjection dose;
  final List<DoseHistoryEvent> events;

  factory HistoryDose.fromJson(Map<String, dynamic> json) {
    return HistoryDose(
      dose: DoseProjection.fromJson(json),
      events: (json['events'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (event) => DoseHistoryEvent.fromJson(
              Map<String, dynamic>.from(event as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class HistoryDay {
  const HistoryDay({
    required this.localDate,
    required this.doses,
  });

  final String localDate;
  final List<HistoryDose> doses;

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    return HistoryDay(
      localDate: json['local_date'].toString(),
      doses: (json['doses'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dose) => HistoryDose.fromJson(
              Map<String, dynamic>.from(dose as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class MemberHistory {
  const MemberHistory({
    required this.memberId,
    required this.memberName,
    required this.timezone,
    required this.fromDate,
    required this.toDate,
    required this.markedAdherencePercentage,
    required this.days,
  });

  final String memberId;
  final String memberName;
  final String timezone;
  final String fromDate;
  final String toDate;
  final String? markedAdherencePercentage;
  final List<HistoryDay> days;

  factory MemberHistory.fromJson(Map<String, dynamic> json) {
    return MemberHistory(
      memberId: json['member_id'].toString(),
      memberName: json['member_name'].toString(),
      timezone: json['timezone'].toString(),
      fromDate: json['from_date'].toString(),
      toDate: json['to_date'].toString(),
      markedAdherencePercentage:
          json['marked_adherence_percentage']?.toString(),
      days: (json['days'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (day) => HistoryDay.fromJson(
              Map<String, dynamic>.from(day as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}
