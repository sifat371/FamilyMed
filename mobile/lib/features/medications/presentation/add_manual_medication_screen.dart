import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddManualMedicationScreen extends ConsumerStatefulWidget {
  const AddManualMedicationScreen({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  ConsumerState<AddManualMedicationScreen> createState() =>
      _AddManualMedicationScreenState();
}

class _AddManualMedicationScreenState
    extends ConsumerState<AddManualMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _strengthController = TextEditingController();
  final _dosageFormController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startDateController.text = _dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _strengthController.dispose();
    _dosageFormController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final startDate = _parseDate(_startDateController.text)!;
    final endDate = _endDateController.text.trim().isEmpty
        ? null
        : _parseDate(_endDateController.text);

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(medicationRepositoryProvider).createMedication(
            widget.memberId,
            displayName: _nameController.text.trim(),
            strength: _strengthController.text,
            dosageForm: _dosageFormController.text,
            startDate: startDate,
            endDate: endDate,
          );
      ref.invalidate(memberMedicationsProvider(widget.memberId));
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/family/${widget.memberId}');
      }
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return null;
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null || _dateOnly(parsed) != trimmed) return null;
    return parsed;
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _pickStartDate() async {
    final current = _parseDate(_startDateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _startDateController.text = _dateOnly(picked);
      final end = _parseDate(_endDateController.text);
      if (end != null && end.isBefore(picked)) {
        _endDateController.clear();
      }
    });
  }

  Future<void> _pickEndDate() async {
    final start = _parseDate(_startDateController.text) ?? DateTime.now();
    final current = _parseDate(_endDateController.text) ?? start;
    final initial = current.isBefore(start) ? start : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() => _endDateController.text = _dateOnly(picked));
  }

  String? _validateStartDate(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.requiredFieldError;
    return _parseDate(value) == null ? l10n.invalidDateError : null;
  }

  String? _validateEndDate(String? value) {
    final l10n = AppLocalizations.of(context);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final end = _parseDate(trimmed);
    if (end == null) return l10n.invalidDateError;
    final start = _parseDate(_startDateController.text);
    if (start != null && end.isBefore(start)) return l10n.invalidDateRange;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addMedicationManually)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('medicationName'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.medicineName),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.requiredFieldError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('medicationStrength'),
                  controller: _strengthController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.strengthLabel,
                    hintText: l10n.strengthHint,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('medicationDosageForm'),
                  controller: _dosageFormController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.dosageForm,
                    hintText: l10n.dosageFormHint,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('medicationStartDate'),
                  controller: _startDateController,
                  readOnly: true,
                  onTap: _submitting ? null : _pickStartDate,
                  decoration: InputDecoration(
                    labelText: l10n.startDate,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                  validator: _validateStartDate,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('medicationEndDate'),
                  controller: _endDateController,
                  readOnly: true,
                  onTap: _submitting ? null : _pickEndDate,
                  decoration: InputDecoration(
                    labelText: l10n.endDate,
                    suffixIcon: _endDateController.text.isEmpty
                        ? const Icon(Icons.calendar_today_outlined)
                        : IconButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(_endDateController.clear),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  validator: _validateEndDate,
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
                      : Text(l10n.saveMedicine),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
