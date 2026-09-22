import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.medication_outlined, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        l10n.noMedicinesYet,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
