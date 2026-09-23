import 'package:familymed/core/formatters/quantity_format.dart';
import 'package:familymed/core/time/local_time_format.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DoseActionScreen extends ConsumerStatefulWidget {
  const DoseActionScreen({
    super.key,
    required this.doseId,
    required this.repository,
  });

  final String doseId;
  final DoseRepository repository;

  @override
  ConsumerState<DoseActionScreen> createState() => _DoseActionScreenState();
}

class _DoseActionScreenState extends ConsumerState<DoseActionScreen> {
  DoseProjection? _dose;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dose = await widget.repository.cachedDose(widget.doseId);
    if (!mounted) return;
    setState(() {
      _dose = dose;
      _loading = false;
      _error = dose == null ? AppLocalizations.of(context).doseNotAvailable : null;
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      await action();
      final dose = await widget.repository.cachedDose(widget.doseId);
      ref.invalidate(todayProvider);
      if (!mounted) return;
      setState(() => _dose = dose);
    } on Object {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context).networkError);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dose = _dose;
    if (dose == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.doseDetails)),
        body: Center(child: Text(_error ?? l10n.doseNotAvailable)),
      );
    }

    final title = dose.strength == null || dose.strength!.isEmpty
        ? dose.medicationName
        : '${dose.medicationName} ${dose.strength}';
    final meal = switch (dose.mealRelation) {
      'after_food' => l10n.afterFood,
      'before_food' => l10n.beforeFood,
      'with_food' => l10n.withFood,
      _ => l10n.unspecified,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.doseDetails)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${compactQuantity(dose.quantityText)} ${dose.unit} • $meal'),
            const SizedBox(height: 4),
            Text(l10n.scheduledTime(formatLocalTime12h(context, dose.scheduledLocalTime))),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _acting
                  ? null
                  : () => _act(
                        () => widget.repository.markTaken(
                          dose.id,
                          occurredAt: DateTime.now().toUtc(),
                        ),
                      ),
              child: Text(l10n.markAsTaken),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _acting || dose.status != 'pending'
                  ? null
                  : () async {
                      final now = DateTime.now().toUtc();
                      await _act(
                        () => widget.repository.snooze(
                          dose.id,
                          occurredAt: now,
                          snoozedUntil: now.add(const Duration(minutes: 15)),
                        ),
                      );
                    },
              child: Text(l10n.snooze15Minutes),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _acting
                  ? null
                  : () => _act(
                        () => widget.repository.skip(
                          dose.id,
                          occurredAt: DateTime.now().toUtc(),
                        ),
                      ),
              child: Text(l10n.skipThisDose),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.takenConfirmationDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
