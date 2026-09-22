class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.relationship,
    this.dateOfBirth,
    required this.preferredLanguage,
    required this.timezone,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date_of_birth'] as String?;
    return FamilyMember(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String,
      dateOfBirth: rawDate == null ? null : DateTime.parse(rawDate),
      preferredLanguage: json['preferred_language'] as String,
      timezone: json['timezone'] as String,
    );
  }

  final String id;
  final String name;
  final String relationship;
  final DateTime? dateOfBirth;
  final String preferredLanguage;
  final String timezone;
}
