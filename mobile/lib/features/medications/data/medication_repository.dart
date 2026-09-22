import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class MedicationRepository {
  Future<List<MemberMedication>> listMedications(String memberId);

  Future<MemberMedication> createMedication(
    String memberId, {
    required String displayName,
    String? strength,
    String? dosageForm,
    required DateTime startDate,
    DateTime? endDate,
  });

  Future<MemberMedication> getMedication(String id);

  Future<MemberMedication> updateMedication(
    String id, {
    String? displayName,
    String? strength,
    String? dosageForm,
    DateTime? startDate,
    DateTime? endDate,
  });
}

class ApiMedicationRepository implements MedicationRepository {
  ApiMedicationRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<MemberMedication>> listMedications(String memberId) async {
    final response = await _client.get<List<dynamic>>(
      '/family-members/$memberId/medications',
    );
    return response.data!
        .map(
          (item) => MemberMedication.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<MemberMedication> createMedication(
    String memberId, {
    required String displayName,
    String? strength,
    String? dosageForm,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/family-members/$memberId/medications',
      data: {
        'display_name': displayName,
        'strength': _nullableText(strength),
        'dosage_form': _nullableText(dosageForm),
        'start_date': _dateOnly(startDate),
        'end_date': endDate == null ? null : _dateOnly(endDate),
      },
    );
    return MemberMedication.fromJson(response.data!);
  }

  @override
  Future<MemberMedication> getMedication(String id) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/member-medications/$id',
    );
    return MemberMedication.fromJson(response.data!);
  }

  @override
  Future<MemberMedication> updateMedication(
    String id, {
    String? displayName,
    String? strength,
    String? dosageForm,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final payload = <String, dynamic>{};
    if (displayName != null) payload['display_name'] = displayName;
    if (strength != null) payload['strength'] = _nullableText(strength);
    if (dosageForm != null) payload['dosage_form'] = _nullableText(dosageForm);
    if (startDate != null) payload['start_date'] = _dateOnly(startDate);
    if (endDate != null) payload['end_date'] = _dateOnly(endDate);

    final response = await _client.patch<Map<String, dynamic>>(
      '/member-medications/$id',
      data: payload,
    );
    return MemberMedication.fromJson(response.data!);
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  return ApiMedicationRepository(ref.watch(apiClientProvider));
});

final memberMedicationsProvider =
    FutureProvider.family<List<MemberMedication>, String>((ref, memberId) {
  return ref.watch(medicationRepositoryProvider).listMedications(memberId);
});
