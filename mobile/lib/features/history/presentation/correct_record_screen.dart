import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class CorrectRecordScreen extends StatefulWidget {
  const CorrectRecordScreen({
    super.key,
    required this.doseId,
    required this.repository,
    required this.initialStatus,
  });

  final String doseId;
  final DoseRepository repository;
  final String initialStatus;

  @override
  State<CorrectRecordScreen> createState() => _CorrectRecordScreenState();
}

class _CorrectRecordScreenState extends State<CorrectRecordScreen> {
  final _reasonController = TextEditingController();
  late String _status;
  DateTime? _effectiveAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _effectiveAt = DateTime.now();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickEffectiveAt() async {
    final current = _effectiveAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (time == null) return;
    setState(() {
      _effectiveAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _effectiveAtLabel(BuildContext context) {
    final value = _effectiveAt;
    if (value == null) return '';
    final date = MaterialLocalizations.of(context).formatMediumDate(value);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: false,
    );
    return '$date, $time';
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final effectiveAt = _effectiveAt;
    if (effectiveAt == null) {
      setState(() => _error = l10n.invalidCorrectionTime);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final effectiveUtc = effectiveAt.toUtc();
      final occurredAt = effectiveUtc.isAfter(now) ? effectiveUtc : now;
      await widget.repository.correct(
        widget.doseId,
        occurredAt: occurredAt,
        newStatus: _status,
        effectiveAt: effectiveUtc,
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
      );
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (mounted) setState(() => _error = l10n.networkError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.correctRecord)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.takenStatus),
                  selected: _status == 'taken',
                  onSelected: _saving ? null : (_) => setState(() => _status = 'taken'),
                ),
                ChoiceChip(
                  label: Text(l10n.skippedStatus),
                  selected: _status == 'skipped',
                  onSelected: _saving ? null : (_) => setState(() => _status = 'skipped'),
                ),
                ChoiceChip(
                  label: Text(l10n.missedStatus),
                  selected: _status == 'missed',
                  onSelected: _saving ? null : (_) => setState(() => _status = 'missed'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            InkWell(
              key: const Key('effectiveAtField'),
              onTap: _saving ? null : _pickEffectiveAt,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.correctionEffectiveAt,
                  suffixIcon: const Icon(Icons.event_outlined),
                ),
                child: Text(_effectiveAtLabel(context)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              enabled: !_saving,
              decoration: InputDecoration(labelText: l10n.correctionReason),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.saveCorrection),
            ),
          ],
        ),
      ),
    );
  }
}
