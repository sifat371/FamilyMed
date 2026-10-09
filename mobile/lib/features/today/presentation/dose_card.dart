import 'package:familymed/core/formatters/quantity_format.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/time/local_time_format.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DoseCard extends StatelessWidget {
  const DoseCard({
    super.key,
    required this.dose,
  });

  final DoseProjection dose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = dose.strength == null || dose.strength!.isEmpty
        ? dose.medicationName
        : '${dose.medicationName} ${dose.strength}';
    final snoozed = dose.status == 'pending' && dose.snoozedUntil != null;
    final status =
        snoozed ? l10n.snoozedStatus : _statusLabel(l10n, dose.status);
    final isTaken = dose.status == 'taken';
    final isProblem = dose.status == 'skipped' || dose.status == 'missed';
    final background = isTaken
        ? FamilyMedColors.successSoft
        : isProblem
            ? FamilyMedColors.warningSoft
            : FamilyMedColors.primarySoft;
    final foreground = isTaken
        ? FamilyMedColors.success
        : isProblem
            ? FamilyMedColors.warning
            : FamilyMedColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: Key('doseCard-${dose.id}'),
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.push('/doses/${dose.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isTaken) ...[
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: FamilyMedColors.success,
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      formatLocalTime12h(context, dose.scheduledLocalTime),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                    ),
                    Text(
                      ' • ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: foreground,
                          ),
                    ),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: isTaken
                          ? FamilyMedColors.success
                          : FamilyMedColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (snoozed) ...[
                  FamilyMedPill(label: status),
                  const SizedBox(height: 5),
                  Text(
                    l10n.snoozedUntil(
                      formatInstantInTimezone12h(
                        context,
                        dose.snoozedUntil!,
                        dose.timezone,
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: FamilyMedColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    l10n.scheduledTime(
                      formatLocalTime12h(
                        context,
                        dose.scheduledLocalTime,
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            '${compactQuantity(dose.quantityText)} ${dose.unit}',
                            if (dose.mealRelation != null)
                              _mealLabel(l10n, dose.mealRelation!),
                          ].join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _mealLabel(AppLocalizations l10n, String relation) {
    return switch (relation) {
      'after_food' => l10n.afterFood,
      'before_food' => l10n.beforeFood,
      'with_food' => l10n.withFood,
      'none' => l10n.noMealRelation,
      _ => l10n.unspecified,
    };
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'taken' => l10n.takenStatus,
      'skipped' => l10n.skippedStatus,
      'missed' => l10n.missedStatus,
      'pending' => l10n.pendingStatus,
      _ => l10n.upcomingStatus,
    };
  }
}
