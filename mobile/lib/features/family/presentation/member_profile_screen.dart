import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/presentation/family_relationship_label.dart';
import 'package:familymed/features/medications/data/medication_lifecycle_repository.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MemberProfileScreen extends ConsumerWidget {
  const MemberProfileScreen({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final member = ref.watch(familyMemberProvider(memberId));
    final medications = ref.watch(memberMedicationsProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: l10n.editFamilyMember,
            onPressed: () => context.push('/family/$memberId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: member.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.networkError),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(familyMemberProvider(memberId)),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
              ],
            ),
          ),
          data: (value) {
            final medicationItems =
                medications.asData?.value ?? const <MemberMedication>[];
            final hasMedications = medicationItems.isNotEmpty;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Text(
                  value.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 18),
                FamilyMedSoftCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: FamilyMedColors.surface,
                        child: Icon(
                          Icons.person_outline,
                          color: FamilyMedColors.primary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              familyRelationshipLabel(
                                l10n,
                                value.relationship,
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              value.preferredLanguage == 'bn'
                                  ? l10n.banglaLanguage
                                  : l10n.englishLanguage,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasMedications) ...[
                  const SizedBox(height: 16),
                  for (final item in medicationItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MedicationCard(medication: item),
                    ),
                ],
                const SizedBox(height: 18),
                FamilyMedSectionLabel(l10n.addMedicineSection),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('scanPrescriptionButton'),
                  onPressed: null,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(l10n.scanPrescriptionComingSoon),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/family/$memberId/medications/new',
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addManually),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.youStayInControl,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.aiSuggestionSafety,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: FamilyMedColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!hasMedications) ...[
                  const SizedBox(height: 18),
                  medications.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Column(
                      children: [
                        Text(l10n.networkError),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => ref.invalidate(
                            memberMedicationsProvider(memberId),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                    data: (items) =>
                        _EmptyMedicationCard(label: l10n.noMedicinesYet),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => context.push('/family/$memberId/history'),
                  icon: const Icon(Icons.history),
                  label: Text(l10n.historyTitle),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/family/$memberId/reminders'),
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(l10n.reminderSettings),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

class _EmptyMedicationCard extends StatelessWidget {
  const _EmptyMedicationCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.medication_outlined, size: 36),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _MedicationCard extends ConsumerStatefulWidget {
  const _MedicationCard({required this.medication});

  final MemberMedication medication;

  @override
  ConsumerState<_MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends ConsumerState<_MedicationCard> {
  bool _working = false;

  Future<void> _runLifecycle(
    Future<MemberMedication> Function() action,
  ) async {
    if (_working) return;
    setState(() => _working = true);
    final medication = widget.medication;
    final l10n = AppLocalizations.of(context);
    try {
      await action();
      try {
        await ref.read(reminderCoordinatorProvider).refresh();
      } on Object {
        // Medication state is already canonical; local reminders reconcile later.
      }
      ref.invalidate(memberMedicationsProvider(medication.familyMemberId));
      ref.invalidate(todayProvider);
    } on ApiError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.networkError)),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pause() {
    return _runLifecycle(
      () => ref
          .read(medicationLifecycleRepositoryProvider)
          .pause(widget.medication.id),
    );
  }

  Future<void> _resume() {
    return _runLifecycle(
      () => ref
          .read(medicationLifecycleRepositoryProvider)
          .resume(widget.medication.id),
    );
  }

  Future<void> _end() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.endMedicineTitle),
        content: Text(l10n.endMedicineBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.endMedicine),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runLifecycle(
      () => ref
          .read(medicationLifecycleRepositoryProvider)
          .end(widget.medication.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final medication = widget.medication;
    final l10n = AppLocalizations.of(context);
    final details = [
      if (medication.strength != null && medication.strength!.isNotEmpty)
        medication.strength!,
      if (medication.dosageForm != null && medication.dosageForm!.isNotEmpty)
        medication.dosageForm!,
    ].join(' • ');
    final canEditRoutine =
        medication.status == 'draft' ||
        medication.status == 'active' ||
        medication.status == 'paused';

    return Card(
      child: ListTile(
        title: Text(medication.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details),
            Text(_medicationStatusLabel(l10n, medication.status)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _working
                      ? null
                      : () => context.push(
                            '/family/${medication.familyMemberId}/medications/${medication.id}/edit',
                          ),
                  child: Text(l10n.editMedicine),
                ),
                if (canEditRoutine)
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => context.push(
                              '/family/${medication.familyMemberId}/medications/${medication.id}/routine',
                            ),
                    child: Text(
                      medication.status == 'draft'
                          ? l10n.setRoutine
                          : l10n.editRoutine,
                    ),
                  ),
                if (medication.status == 'active')
                  TextButton(
                    key: Key('pauseMedication-${medication.id}'),
                    onPressed: _working ? null : _pause,
                    child: Text(l10n.pauseMedicine),
                  ),
                if (medication.status == 'paused')
                  TextButton(
                    key: Key('resumeMedication-${medication.id}'),
                    onPressed: _working ? null : _resume,
                    child: Text(l10n.resumeMedicine),
                  ),
                if (medication.status == 'active' ||
                    medication.status == 'paused')
                  TextButton(
                    key: Key('endMedication-${medication.id}'),
                    onPressed: _working ? null : _end,
                    child: Text(
                      l10n.endMedicine,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            if (_working) ...[
              const SizedBox(height: 4),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  String _medicationStatusLabel(
    AppLocalizations l10n,
    String status,
  ) {
    return switch (status) {
      'draft' => l10n.draftStatus,
      'active' => l10n.activeStatus,
      'paused' => l10n.pausedStatus,
      'completed' => l10n.completedStatus,
      'ended' => l10n.endedStatus,
      _ => status,
    };
  }
}
