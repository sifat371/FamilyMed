class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.email,
    required this.preferredLanguage,
    required this.timezone,
    this.hasPassword = true,
    this.googleLinked = false,
  });

  final String id;
  final String name;
  final String email;
  final String preferredLanguage;
  final String timezone;
  final bool hasPassword;
  final bool googleLinked;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      preferredLanguage: json['preferred_language'] as String,
      timezone: json['timezone'] as String,
      hasPassword: json['has_password'] as bool? ?? true,
      googleLinked: json['google_linked'] as bool? ?? false,
    );
  }
}
