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
    final status = _statusLabel(l10n, dose.status);
    final icon = _statusIcon(dose.status);

    return Card(
      child: ListTile(
        onTap: () => context.push('/doses/${dose.id}'),
        leading: Icon(icon, semanticLabel: status),
        title: Text(name),
        subtitle: Text('${formatLocalTime12h(context, dose.scheduledLocalTime)} • $status'),
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
