import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MemberHistoryScreen extends StatefulWidget {
  const MemberHistoryScreen({
    super.key,
    required this.memberId,
    required this.repository,
  });

  final String memberId;
  final HistoryRepository repository;

  @override
  State<MemberHistoryScreen> createState() => _MemberHistoryScreenState();
}

class _MemberHistoryScreenState extends State<MemberHistoryScreen> {
  MemberHistory? _history;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await widget.repository.load(widget.memberId);
      if (!mounted) return;
      setState(() => _history = history);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = _history;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(l10n.networkError))
            : history == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        history.memberName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.markedAdherence,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        history.markedAdherencePercentage == null
                            ? l10n.notAvailable
                            : '${history.markedAdherencePercentage}%',
                      ),
                      const SizedBox(height: 24),
                      for (final day in history.days) ...[
                        Text(
                          day.localDate,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final item in day.doses)
                          _HistoryDoseCard(item: item),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _HistoryDoseCard extends StatelessWidget {
  const _HistoryDoseCard({required this.item});

  final HistoryDose item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dose = item.dose;
    final title = dose.strength == null || dose.strength!.isEmpty
        ? dose.medicationName
        : '${dose.medicationName} ${dose.strength}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_statusLabel(l10n, dose.status)),
            if (item.events.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final event in item.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_eventLabel(l10n, event.action)),
                ),
            ],
            if (_isFinal(dose.status)) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push(
                  '/doses/${dose.id}/correct?status=${dose.status}',
                ),
                child: Text(l10n.correctRecord),
              ),
            ],
          ],
        ),
      ),
    );
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

  String _eventLabel(AppLocalizations l10n, String action) {
    return switch (action) {
      'marked_taken' => l10n.takenStatus,
      'skipped' => l10n.skippedStatus,
      'missed' => l10n.missedStatus,
      'corrected' => l10n.correctedEvent,
      'snoozed' => l10n.snoozedEvent,
      'became_pending' => l10n.pendingStatus,
      _ => action,
    };
  }
}
