import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddFamilyMemberScreen extends ConsumerStatefulWidget {
  const AddFamilyMemberScreen({
    super.key,
    this.initialRelationship = 'mother',
  });

  final String initialRelationship;

  @override
  ConsumerState<AddFamilyMemberScreen> createState() => _AddFamilyMemberScreenState();
}

class _AddFamilyMemberScreenState extends ConsumerState<AddFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _dobController = TextEditingController();
  String _preferredLanguage = 'bn';
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _relationshipController.text = widget.initialRelationship;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final member = await ref.read(familyRepositoryProvider).createMember(
            name: _nameController.text.trim(),
            relationship: _relationshipController.text.trim(),
            dateOfBirth: _parseDob(_dobController.text),
            preferredLanguage: _preferredLanguage,
            timezone: 'Asia/Dhaka',
          );
      ref.invalidate(familyMembersProvider);
      ref.invalidate(familyMemberProvider(member.id));
      if (!mounted) return;
      context.go('/family/${member.id}');
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  DateTime? _parseDob(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _parseDob(_dobController.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(today.year - 40, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _dobController.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  String? _validateDob(String? value) {
    final l10n = AppLocalizations.of(context);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return l10n.invalidDateError;
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return l10n.invalidDateError;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (parsed.isAfter(today)) return l10n.futureDobError;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.familyProfile)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('familyName'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.familyMemberName),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.requiredFieldError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('familyRelationship'),
                  controller: _relationshipController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.relationshipLabel),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.requiredFieldError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('familyDob'),
                  controller: _dobController,
                  readOnly: true,
                  onTap: _submitting ? null : _pickDob,
                  decoration: InputDecoration(
                    labelText: l10n.dateOfBirth,
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: _dobController.text.isEmpty
                        ? const Icon(Icons.calendar_today_outlined)
                        : IconButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(_dobController.clear),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  validator: _validateDob,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.preferredLanguage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.banglaLanguage),
                      selected: _preferredLanguage == 'bn',
                      onSelected: (_) => setState(() => _preferredLanguage = 'bn'),
                    ),
                    ChoiceChip(
                      label: Text(l10n.englishLanguage),
                      selected: _preferredLanguage == 'en',
                      onSelected: (_) => setState(() => _preferredLanguage = 'en'),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.addFamilyMember),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
