import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/family/domain/family_member.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class FamilyRepository {
  Future<List<FamilyMember>> listMembers();

  Future<FamilyMember> createMember({
    required String name,
    required String relationship,
    DateTime? dateOfBirth,
    required String preferredLanguage,
    required String timezone,
  });

  Future<FamilyMember> getMember(String id);

  Future<FamilyMember> updateMember(
    String id, {
    String? name,
    String? relationship,
    DateTime? dateOfBirth,
    String? preferredLanguage,
    String? timezone,
  });
}

class ApiFamilyRepository implements FamilyRepository {
  ApiFamilyRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<FamilyMember>> listMembers() async {
    final response = await _client.get<List<dynamic>>('/family-members');
    return response.data!
        .map((item) => FamilyMember.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  @override
  Future<FamilyMember> createMember({
    required String name,
    required String relationship,
    DateTime? dateOfBirth,
    required String preferredLanguage,
    required String timezone,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/family-members',
      data: {
        'name': name,
        'relationship': relationship,
        'date_of_birth': dateOfBirth == null ? null : _dateOnly(dateOfBirth),
        'preferred_language': preferredLanguage,
        'timezone': timezone,
      },
    );
    return FamilyMember.fromJson(response.data!);
  }

  @override
  Future<FamilyMember> getMember(String id) async {
    final response = await _client.get<Map<String, dynamic>>('/family-members/$id');
    return FamilyMember.fromJson(response.data!);
  }

  @override
  Future<FamilyMember> updateMember(
    String id, {
    String? name,
    String? relationship,
    DateTime? dateOfBirth,
    String? preferredLanguage,
    String? timezone,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (relationship != null) payload['relationship'] = relationship;
    if (dateOfBirth != null) payload['date_of_birth'] = _dateOnly(dateOfBirth);
    if (preferredLanguage != null) {
      payload['preferred_language'] = preferredLanguage;
    }
    if (timezone != null) payload['timezone'] = timezone;

    final response = await _client.patch<Map<String, dynamic>>(
      '/family-members/$id',
      data: payload,
    );
    return FamilyMember.fromJson(response.data!);
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  return ApiFamilyRepository(ref.watch(apiClientProvider));
});

final familyMembersProvider = FutureProvider<List<FamilyMember>>((ref) {
  return ref.watch(familyRepositoryProvider).listMembers();
});

final familyMemberProvider = FutureProvider.family<FamilyMember, String>((ref, id) {
  return ref.watch(familyRepositoryProvider).getMember(id);
});
