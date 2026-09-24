import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class MedicationLifecycleRepository {
  Future<MemberMedication> pause(String medicationId);

  Future<MemberMedication> resume(String medicationId);

  Future<MemberMedication> end(String medicationId);
}

class ApiMedicationLifecycleRepository implements MedicationLifecycleRepository {
  ApiMedicationLifecycleRepository(this._client);

  final ApiClient _client;

  @override
  Future<MemberMedication> pause(String medicationId) =>
      _changeState(medicationId, 'pause');

  @override
  Future<MemberMedication> resume(String medicationId) =>
      _changeState(medicationId, 'resume');

  @override
  Future<MemberMedication> end(String medicationId) =>
      _changeState(medicationId, 'end');

  Future<MemberMedication> _changeState(
    String medicationId,
    String action,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/member-medications/$medicationId/$action',
    );
    return MemberMedication.fromJson(response.data!);
  }
}

final medicationLifecycleRepositoryProvider =
    Provider<MedicationLifecycleRepository>((ref) {
  return ApiMedicationLifecycleRepository(ref.watch(apiClientProvider));
});
