import 'dart:async';

import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/presentation/dose_card.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.invalidate(todayProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(
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
                Center(
                  child: Column(
                    children: [
                      Text(l10n.networkError),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(todayProvider),
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            data: (result) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.todayTitle,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    FamilyMedPill(label: l10n.familyCare),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.todaysCare,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                if (result.isOffline) ...[
                  FamilyMedSoftCard(
                    color: FamilyMedColors.surface,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_off_outlined,
                          color: FamilyMedColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.offlineSavedDoses)),
                      ],
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
                          style: Theme.of(context).textTheme.bodyLarge,
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group.name,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                FamilyMedPill(
                                  label: l10n.markedTakenSummary(
                                    group.takenCount,
                                    group.totalCount,
                                  ),
                                  backgroundColor:
                                      FamilyMedColors.successSoft,
                                  foregroundColor: FamilyMedColors.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            for (final dose in group.doses)
                              DoseCard(dose: dose),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

}
