import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FamilyListScreen extends ConsumerWidget {
  const FamilyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(familyMembersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.yourFamily),
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: members.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(child: Text(l10n.networkError)),
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(child: Text(l10n.noFamilyMembersYet));
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final member = items[index];
                        return Card(
                          child: ListTile(
                            title: Text(member.name),
                            subtitle: Text(member.relationship),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/family/' + member.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/family/new'),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(l10n.addFamilyMember),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
