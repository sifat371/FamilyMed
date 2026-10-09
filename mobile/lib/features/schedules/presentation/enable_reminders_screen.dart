import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/schedules/data/notification_preference_repository.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EnableRemindersScreen extends ConsumerStatefulWidget {
  const EnableRemindersScreen({super.key, required this.memberId});

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
  bool _schedulingFailed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadPreference);
  }

  Future<void> _loadPreference() async {
    setState(() {
      _loadingPreference = true;
      _message = null;
    });
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
        _message = AppLocalizations.of(context).networkError;
        _loadingPreference = false;
      });
    }
  }

  Future<void> _enable() async {
    if (_loading) return;
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
      if (!await _refreshReminders()) return;
      ref.invalidate(todayProvider);
      if (mounted) context.pushReplacement('/today');
    } on Object {
      if (mounted) setState(() => _message = l10n.networkError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _refreshReminders() async {
    try {
      await ref.read(reminderCoordinatorProvider).refresh();
      if (mounted) setState(() => _schedulingFailed = false);
      return true;
    } on Object {
      if (mounted) {
        setState(() {
          _schedulingFailed = true;
          _message = AppLocalizations.of(context).notificationSchedulingFailed;
        });
      }
      return false;
    }
  }

  Future<void> _retryScheduling() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    await _refreshReminders();
    if (mounted) setState(() => _loading = false);
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
      await _refreshReminders();
      ref.invalidate(todayProvider);
      if (!mounted) return;
      setState(() => _enabled = false);
    } on Object {
      if (mounted) {
        setState(() => _message = AppLocalizations.of(context).networkError);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FamilyMedPill(label: l10n.enableReminders),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.reminderSettings,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              if (_loadingPreference)
                const LinearProgressIndicator()
              else
                FamilyMedSoftCard(
                  child: Row(
                    children: [
                      Icon(
                        _enabled == true
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: FamilyMedColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _enabled == null
                              ? l10n.notAvailable
                              : _enabled == true
                              ? l10n.remindersOn
                              : l10n.remindersOff,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.enableReminders,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.enableRemindersBody,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.reminderPermissionNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              if (_enabled == null && !_loadingPreference)
                OutlinedButton(
                  onPressed: _loading ? null : _loadPreference,
                  child: Text(l10n.retry),
                ),
              if (_schedulingFailed)
                OutlinedButton(
                  onPressed: _loading ? null : _retryScheduling,
                  child: Text(l10n.retry),
                ),
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
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loading ? null : () => context.pushReplacement('/today'),
                child: Text(l10n.continueToToday),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
