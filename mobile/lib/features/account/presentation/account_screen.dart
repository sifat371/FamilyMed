import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/account/data/account_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            ],
          ),
        ),
      ),
    );
  }
}
