import 'package:familymed/core/time/local_time_format.dart';
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
    final status = snoozed
        ? l10n.snoozedStatus
        : _statusLabel(l10n, dose.status);
    final icon = _statusIcon(dose.status);

    final subtitle = snoozed
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.snoozedUntil(
                  formatInstantInTimezone12h(
                    context,
                    dose.snoozedUntil!,
                    dose.timezone,
                  ),
                ),
              ),
              Text(
                l10n.scheduledTime(
                  formatLocalTime12h(context, dose.scheduledLocalTime),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          )
        : Text(
            '${formatLocalTime12h(context, dose.scheduledLocalTime)} • $status',
          );

    return Card(
      child: ListTile(
        onTap: () => context.push('/doses/${dose.id}'),
        leading: Icon(icon, semanticLabel: status),
        title: Text(name),
        subtitle: subtitle,
        trailing: Text(status),
      ),
    );
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

  IconData _statusIcon(String status) {
    return switch (status) {
      'taken' => Icons.check_circle_outline,
      'skipped' => Icons.remove_circle_outline,
      'missed' => Icons.error_outline,
      'pending' => Icons.schedule,
      _ => Icons.access_time,
    };
  }
}
