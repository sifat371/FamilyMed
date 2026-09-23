import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/presentation/dose_card.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todayTitle),
        actions: [
          IconButton(
            key: const Key('signOutButton'),
            tooltip: l10n.signOut,
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(todayProvider);
            await ref.read(todayProvider.future);
          },
          child: today.when(
            loading: () => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 280),
                Center(child: CircularProgressIndicator()),
              ],
            ),
            error: (_, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 120),
                Center(child: Text(l10n.networkError)),
              ],
            ),
            data: (result) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (result.isOffline) ...[
                  Semantics(
                    label: l10n.offlineSavedDoses,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined),
                            const SizedBox(width: 8),
                            Expanded(child: Text(l10n.offlineSavedDoses)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (result.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      children: [
                        Text(
                          l10n.noDosesToday,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('openFamilyButton'),
                          onPressed: () => context.go('/family'),
                          icon: const Icon(Icons.family_restroom),
                          label: Text(l10n.familyTab),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('addFamilyMemberFromTodayButton'),
                          onPressed: () => context.push('/family/new'),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: Text(l10n.addFamilyMember),
                        ),
                      ],
                    ),
                  )
                else
                  for (final group in result.groups) ...[
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.markedTakenSummary(
                        group.takenCount,
                        group.totalCount,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final dose in group.doses) DoseCard(dose: dose),
                    const SizedBox(height: 24),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
