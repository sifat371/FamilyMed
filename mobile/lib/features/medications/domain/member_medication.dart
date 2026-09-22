class MemberMedication {
  const MemberMedication({
    required this.id,
    required this.familyMemberId,
    required this.medicineMasterId,
    required this.displayName,
    required this.strength,
    required this.dosageForm,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  factory MemberMedication.fromJson(Map<String, dynamic> json) {
    return MemberMedication(
      id: json['id'] as String,
      familyMemberId: json['family_member_id'] as String,
      medicineMasterId: json['medicine_master_id'] as String?,
      displayName: json['display_name'] as String,
      strength: json['strength'] as String?,
      dosageForm: json['dosage_form'] as String?,
      status: json['status'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
    );
  }

  final String id;
  final String familyMemberId;
  final String? medicineMasterId;
  final String displayName;
  final String? strength;
  final String? dosageForm;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
}
