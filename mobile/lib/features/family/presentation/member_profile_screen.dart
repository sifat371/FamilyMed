import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
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
      appBar: AppBar(title: Text(l10n.familyProfile)),
      body: SafeArea(
        child: member.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.networkError)),
          data: (value) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                value.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(value.relationship),
              const SizedBox(height: 4),
              Text(
                value.preferredLanguage == 'bn'
                    ? l10n.banglaLanguage
                    : l10n.englishLanguage,
              ),
              const SizedBox(height: 28),
              medications.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Text(l10n.networkError),
                data: (items) => items.isEmpty
                    ? _EmptyMedicationCard(label: l10n.noMedicinesYet)
                    : Column(
                        children: items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MedicationCard(medication: item),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.push('/family/$memberId/history'),
                icon: const Icon(Icons.history),
                label: Text(l10n.historyTitle),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => context.push(
                  '/family/$memberId/medications/new',
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.addManually),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('scanPrescriptionButton'),
                onPressed: null,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(l10n.scanPrescriptionComingSoon),
              ),
            ],
          ),
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

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.medication});

  final MemberMedication medication;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = [
      if (medication.strength != null && medication.strength!.isNotEmpty)
        medication.strength!,
      if (medication.dosageForm != null && medication.dosageForm!.isNotEmpty)
        medication.dosageForm!,
    ].join(' • ');

    return Card(
      child: ListTile(
        title: Text(medication.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details),
            Text(_medicationStatusLabel(l10n, medication.status)),
            TextButton(
              onPressed: () => context.push(
                '/family/${medication.familyMemberId}/medications/${medication.id}/routine',
              ),
              child: Text(
                medication.status == 'draft' ? l10n.setRoutine : l10n.editRoutine,
              ),
            ),
          ],
        ),
      ),
    );
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
}
