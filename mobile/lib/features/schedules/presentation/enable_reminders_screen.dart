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
  bool _loadingPreference = true;
  bool? _enabled;
  String? _message;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadPreference);
  }

  Future<void> _loadPreference() async {
    try {
      final preference = await ref
          .read(notificationPreferenceRepositoryProvider)
          .getPreference(widget.memberId);
      if (!mounted) return;
      setState(() {
        _enabled = preference.enabled;
        _loadingPreference = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _loadingPreference = false;
      });
    }
  }

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
      if (mounted) {
        setState(() => _enabled = true);
      }
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

  Future<void> _disable() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await ref
          .read(notificationPreferenceRepositoryProvider)
          .updatePreference(widget.memberId, enabled: false);
      try {
        await ref.read(reminderCoordinatorProvider).refresh();
      } on Object {
        // Preference is canonical even if local reconciliation fails.
      }
      ref.invalidate(todayProvider);
      if (!mounted) return;
      setState(() => _enabled = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reminderSettings)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingPreference)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: LinearProgressIndicator(),
                )
              else ...[
                Row(
                  children: [
                    Icon(
                      _enabled == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _enabled == true ? l10n.remindersOn : l10n.remindersOff,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text(
                l10n.enableRemindersBody,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.reminderPermissionNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              if (_message != null) ...[
                Text(_message!),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.go('/today'),
                  child: Text(l10n.continueToToday),
                ),
              ],
              if (_enabled != true)
                FilledButton(
                  onPressed: _loading || _loadingPreference ? null : _enable,
                  child: Text(l10n.enableReminders),
                )
              else
                OutlinedButton(
                  onPressed: _loading || _loadingPreference ? null : _disable,
                  child: Text(l10n.disableReminders),
                ),
              TextButton(
                onPressed: _loading ? null : () => context.go('/today'),
                child: Text(l10n.continueToToday),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
