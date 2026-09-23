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
  final _effectiveAtController = TextEditingController();
  final _reasonController = TextEditingController();
  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
  }

  @override
  void dispose() {
    _effectiveAtController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final effectiveAt = DateTime.tryParse(_effectiveAtController.text.trim());
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
            TextField(
              key: const Key('effectiveAtField'),
              controller: _effectiveAtController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l10n.correctionEffectiveAt,
                hintText: '2026-09-23T12:12:00Z',
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
