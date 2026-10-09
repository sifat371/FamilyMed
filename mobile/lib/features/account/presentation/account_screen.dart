import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/api/api_config.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/account/data/account_deletion_repository.dart';
import 'package:familymed/features/account/data/account_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _language;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _name = TextEditingController(text: user?.name ?? '');
    _language = user?.preferredLanguage ?? 'en';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(accountRepositoryProvider)
          .update(name: _name.text, language: _language);
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).updateCurrentUser(user);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).accountSaved)),
      );
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).networkError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openLegalPage(String path) async {
    try {
      final destination = Uri.parse(apiBaseUrl).replace(path: path, query: null);
      if (!await launchUrl(destination, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open legal information');
      }
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).networkError);
      }
    }
  }

  Future<void> _deleteAccount() async {
    if (_saving || _deleting) return;
    final l10n = AppLocalizations.of(context);
    final confirmation = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountConfirmationDialog(),
    );
    if (!mounted || confirmation == null) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final userId = ref.read(authControllerProvider).user?.id;
      await ref.read(accountDeletionRepositoryProvider).deleteAccount(confirmation);
      // Clear account-scoped SQLite cache and unsent sync operations after
      // successful server-side deletion; never send them under another account.
      try {
        if (userId != null) {
          final db = ref.read(appDatabaseProvider);
          await db.transaction(() async {
            await db.customStatement(
              'DELETE FROM sync_operations WHERE user_id = ?', [userId],
            );
            await db.customStatement(
              'DELETE FROM cached_doses WHERE user_id = ?', [userId],
            );
            await db.customStatement(
              'DELETE FROM cached_today_members WHERE user_id = ?', [userId],
            );
          });
        }
        await ref.read(reminderCoordinatorProvider).clear();
      } finally {
        await ref.read(authControllerProvider.notifier).logout();
      }
    } on Object {
      if (mounted) {
        setState(() => _error = l10n.deleteAccountFailed);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.meTab)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                l10n.accountDetails,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  title: Text(l10n.emailLabel),
                  subtitle: Text(user?.email ?? ''),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('accountName'),
                controller: _name,
                enabled: !_saving,
                decoration: InputDecoration(labelText: l10n.nameLabel),
                maxLength: 120,
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.requiredFieldError
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('accountLanguage'),
                initialValue: _language,
                decoration: InputDecoration(labelText: l10n.preferredLanguage),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _language = value!),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.saveAccount),
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.familyCareSettings),
                  subtitle: Text(l10n.familyCareSettingsBody),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/family'),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('accountSignOut'),
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(authControllerProvider.notifier)
                              .logout();
                        } on Object {
                          if (mounted) {
                            setState(() => _error = l10n.networkError);
                          }
                        }
                      },
                icon: const Icon(Icons.logout),
                label: Text(l10n.signOut),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('privacyPolicyButton'),
                onPressed: _deleting ? null : () => _openLegalPage('/privacy'),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text(l10n.privacyPolicy),
              ),
              TextButton(
                key: const Key('accountDeletionHelpButton'),
                onPressed: _deleting ? null : () => _openLegalPage('/account-deletion'),
                child: Text(l10n.accountDeletionHelp),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('deleteAccountButton'),
                onPressed: _saving || _deleting ? null : _deleteAccount,
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(l10n.deleteAccountTitle),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _DeleteAccountConfirmationDialog extends StatefulWidget {
  const _DeleteAccountConfirmationDialog();

  @override
  State<_DeleteAccountConfirmationDialog> createState() =>
      _DeleteAccountConfirmationDialogState();
}

class _DeleteAccountConfirmationDialogState
    extends State<_DeleteAccountConfirmationDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.deleteAccountWarning),
          const SizedBox(height: 12),
          TextField(
            key: const Key('deleteAccountPassword'),
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.passwordLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _password.text.length < 8
              ? null
              : () => Navigator.of(context).pop(_password.text),
          child: Text(l10n.deleteAccountConfirm),
        ),
      ],
    );
  }
}
