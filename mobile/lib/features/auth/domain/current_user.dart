class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.email,
    required this.preferredLanguage,
    required this.timezone,
  });

  final String id;
  final String name;
  final String email;
  final String preferredLanguage;
  final String timezone;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      preferredLanguage: json['preferred_language'] as String,
      timezone: json['timezone'] as String,
    );
  }
}
