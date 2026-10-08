import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:familymed/features/history/presentation/member_history_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final familyHistoryProvider = FutureProvider.autoDispose<List<MemberHistory>>((
  ref,
) async {
  final members = await ref.watch(familyRepositoryProvider).listMembers();
  final repository = ref.watch(historyRepositoryProvider);
  return Future.wait(members.map((member) => repository.load(member.id)));
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(familyHistoryProvider);
    Future<void> refresh() async {
      ref.invalidate(familyHistoryProvider);
      await ref.read(familyHistoryProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(familyHistoryProvider),
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.networkError),
                TextButton(
                  onPressed: () => ref.invalidate(familyHistoryProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
          data: (members) => RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (members.isEmpty) Text(l10n.noFamilyMembersYet),
                for (final member in members) ...[
                  Text(
                    member.memberName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${member.fromDate} – ${member.toDate} • ${member.timezone}',
                  ),
                  const SizedBox(height: 12),
                  if (member.days.every((day) => day.doses.isEmpty))
                    Text(l10n.noHistoryYet),
                  for (final day in member.days) ...[
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(DateTime.parse(day.localDate)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final item in day.doses)
                      HistoryDoseCard(item: item, onChanged: refresh),
                    const SizedBox(height: 12),
                  ],
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
