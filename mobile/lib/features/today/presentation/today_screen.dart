import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/presentation/dose_card.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(todayProvider);
            await ref.read(todayProvider.future);
          },
          child: today.when(
            loading: () => const ListView(
              physics: AlwaysScrollableScrollPhysics(),
              children: [
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
                    child: Center(child: Text(l10n.noDosesToday)),
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
