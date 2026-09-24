import 'package:familymed/core/formatters/quantity_format.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/core/time/local_time_format.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  bool _isFinal(String status) =>
      status == 'taken' || status == 'skipped' || status == 'missed';

  String _statusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'taken' => l10n.takenStatus,
      'skipped' => l10n.skippedStatus,
      'missed' => l10n.missedStatus,
      'pending' => l10n.pendingStatus,
      _ => l10n.upcomingStatus,
    };
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
      'none' => l10n.noMealRelation,
      _ => l10n.unspecified,
    };
    final memberName = dose.familyMemberName?.trim();
    final header = memberName == null || memberName.isEmpty
        ? l10n.doseDetails
        : l10n.doseForMember(memberName);
    final snoozed = dose.status == 'pending' && dose.snoozedUntil != null;

    return Scaffold(
      appBar: AppBar(title: Text(header)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FamilyMedSoftCard(
                      child: Column(
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${compactQuantity(dose.quantityText)} '
                            '${dose.unit} • $meal',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: FamilyMedColors.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.scheduledTime(
                              formatLocalTime12h(
                                context,
                                dose.scheduledLocalTime,
                              ),
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: FamilyMedColors.textSecondary,
                                ),
                          ),
                          if (snoozed) ...[
                            const SizedBox(height: 6),
                            FamilyMedPill(
                              label: l10n.snoozedUntil(
                                formatInstantInTimezone12h(
                                  context,
                                  dose.snoozedUntil!,
                                  dose.timezone,
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            FamilyMedPill(
                              label: _statusLabel(l10n, dose.status),
                              backgroundColor: _isFinal(dose.status)
                                  ? FamilyMedColors.successSoft
                                  : FamilyMedColors.primarySoft,
                              foregroundColor: _isFinal(dose.status)
                                  ? FamilyMedColors.success
                                  : FamilyMedColors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          memberName == null || memberName.isEmpty
                              ? l10n.takenConfirmationDisclaimer
                              : l10n.markDoseCareNote(memberName),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: FamilyMedColors.textSecondary,
                              ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _acting || _isFinal(dose.status)
                          ? null
                          : () => _act(
                                () => widget.repository.markTaken(
                                  dose.id,
                                  occurredAt: DateTime.now().toUtc(),
                                ),
                              ),
                      icon: const Icon(Icons.check),
                      label: Text(l10n.markAsTaken),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _acting || dose.status != 'pending'
                          ? null
                          : () async {
                              final now = DateTime.now().toUtc();
                              await _act(
                                () => widget.repository.snooze(
                                  dose.id,
                                  occurredAt: now,
                                  snoozedUntil:
                                      now.add(const Duration(minutes: 15)),
                                ),
                              );
                            },
                      child: Text(l10n.snooze15Minutes),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _acting || _isFinal(dose.status)
                          ? null
                          : () => _act(
                                () => widget.repository.skip(
                                  dose.id,
                                  occurredAt: DateTime.now().toUtc(),
                                ),
                              ),
                      child: Text(l10n.skipThisDose),
                    ),
                    if (_isFinal(dose.status)) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _acting
                            ? null
                            : () => context.push(
                                  '/doses/${dose.id}/correct'
                                  '?status=${dose.status}',
                                ),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.correctRecord),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      l10n.takenConfirmationDisclaimer,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
