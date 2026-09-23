import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/schedules/data/notification_preference_repository.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EnableRemindersScreen extends ConsumerStatefulWidget {
  const EnableRemindersScreen({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  ConsumerState<EnableRemindersScreen> createState() =>
      _EnableRemindersScreenState();
}

class _EnableRemindersScreenState extends ConsumerState<EnableRemindersScreen> {
  bool _loading = false;
  String? _message;

  Future<void> _enable() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      final allowed = await scheduler.requestPermission();
      if (!allowed) {
        if (mounted) {
          setState(() => _message = l10n.notificationPermissionDenied);
        }
        return;
      }
      await ref
          .read(notificationPreferenceRepositoryProvider)
          .updatePreference(widget.memberId, enabled: true);
      try {
        await ref.read(reminderCoordinatorProvider).refresh();
      } on Object {
        if (mounted) {
          setState(() => _message = l10n.notificationSchedulingFailed);
        }
        return;
      }
      ref.invalidate(todayProvider);
      if (mounted) context.go('/today');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.enableReminders)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_message != null) ...[
                Text(_message!),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.go('/today'),
                  child: Text(l10n.continueToToday),
                ),
              ],
              FilledButton(
                onPressed: _loading ? null : _enable,
                child: Text(l10n.enableReminders),
              ),
              TextButton(
                onPressed: _loading ? null : () => context.go('/today'),
                child: Text(l10n.notNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
