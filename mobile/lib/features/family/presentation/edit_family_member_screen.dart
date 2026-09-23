import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/presentation/family_relationship_label.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EditFamilyMemberScreen extends ConsumerStatefulWidget {
  const EditFamilyMemberScreen({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  ConsumerState<EditFamilyMemberScreen> createState() =>
      _EditFamilyMemberScreenState();
}

class _EditFamilyMemberScreenState
    extends ConsumerState<EditFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();

  String _relationship = 'other';
  String _preferredLanguage = 'bn';
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final member =
          await ref.read(familyRepositoryProvider).getMember(widget.memberId);
      if (!mounted) return;
      _nameController.text = member.name;
      _relationship = _normalizedRelationship(member.relationship);
      _preferredLanguage = member.preferredLanguage;
      _dobController.text =
          member.dateOfBirth == null ? '' : _dateOnly(member.dateOfBirth!);
    } on ApiError catch (error) {
      if (!mounted) return;
      _errorMessage = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  String _normalizedRelationship(String value) {
    final normalized = value.trim().toLowerCase();
    const known = {
      'parent',
      'mother',
      'father',
      'spouse',
      'child',
      'myself',
      'other',
    };
    return known.contains(normalized) ? normalized : 'other';
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime.tryParse(_dobController.text);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current ?? DateTime(today.year - 40, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _dobController.text = _dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(familyRepositoryProvider).updateMember(
            widget.memberId,
            name: _nameController.text.trim(),
            relationship: _relationship,
            dateOfBirth: _dobController.text.isEmpty
                ? null
                : DateTime.parse(_dobController.text),
            preferredLanguage: _preferredLanguage,
          );
      ref.invalidate(familyMembersProvider);
      ref.invalidate(familyMemberProvider(widget.memberId));
      if (!mounted) return;
      context.go('/family/${widget.memberId}');
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relationshipOptions = <String>[
      'parent',
      'mother',
      'father',
      'spouse',
      'child',
      'myself',
      'other',
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editFamilyMember)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('editFamilyName'),
                        controller: _nameController,
                        decoration:
                            InputDecoration(labelText: l10n.familyMemberName),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? l10n.requiredFieldError
                                : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const Key('editFamilyRelationship'),
                        initialValue: _relationship,
                        decoration:
                            InputDecoration(labelText: l10n.relationshipLabel),
                        items: relationshipOptions
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  familyRelationshipLabel(l10n, value),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _relationship = value);
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('editFamilyDob'),
                        controller: _dobController,
                        readOnly: true,
                        onTap: _saving ? null : _pickDob,
                        decoration: InputDecoration(
                          labelText: l10n.dateOfBirth,
                          suffixIcon:
                              const Icon(Icons.calendar_today_outlined),
                        ),
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
                            onSelected: _saving
                                ? null
                                : (_) => setState(
                                      () => _preferredLanguage = 'bn',
                                    ),
                          ),
                          ChoiceChip(
                            label: Text(l10n.englishLanguage),
                            selected: _preferredLanguage == 'en',
                            onSelected: _saving
                                ? null
                                : (_) => setState(
                                      () => _preferredLanguage = 'en',
                                    ),
                          ),
                        ],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.saveChanges),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
