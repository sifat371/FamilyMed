import 'package:familymed/features/today/domain/dose_projection.dart';

class TodayMemberGroup {
  const TodayMemberGroup({
    required this.memberId,
    required this.name,
    required this.relationship,
    required this.localDate,
    required this.timezone,
    required this.takenCount,
    required this.totalCount,
    required this.doses,
  });

  final String memberId;
  final String name;
  final String relationship;
  final String localDate;
  final String timezone;
  final int takenCount;
  final int totalCount;
  final List<DoseProjection> doses;

  factory TodayMemberGroup.fromJson(Map<String, dynamic> json) {
    return TodayMemberGroup(
      memberId: json['member_id'].toString(),
      name: json['member_name'].toString(),
      relationship: json['relationship'].toString(),
      localDate: json['local_date'].toString(),
      timezone: json['timezone'].toString(),
      takenCount: json['taken_count'] as int,
      totalCount: json['total_count'] as int,
      doses: (json['doses'] as List<dynamic>)
          .map(
            (item) => DoseProjection.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class TodayLoadResult {
  const TodayLoadResult({
    required this.groups,
    required this.isOffline,
  });

  final List<TodayMemberGroup> groups;
  final bool isOffline;
}
