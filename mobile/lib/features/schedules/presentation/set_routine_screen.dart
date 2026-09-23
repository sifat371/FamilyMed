import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SetRoutineScreen extends ConsumerStatefulWidget {
  const SetRoutineScreen({
    super.key,
    required this.memberId,
    required this.medicationId,
  });

  final String memberId;
  final String medicationId;

  @override
  ConsumerState<SetRoutineScreen> createState() => _SetRoutineScreenState();
}

class _SetRoutineScreenState extends ConsumerState<SetRoutineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _instruction = TextEditingController();
  final List<_RoutineRow> _rows = <_RoutineRow>[_RoutineRow()];
  String _mealRelation = 'unspecified';
  String? _scheduleId;
  MedicationSchedule? _existingSchedule;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadExisting);
  }

  Future<void> _loadExisting() async {
    try {
      final schedule = await ref
          .read(scheduleRepositoryProvider)
          .getCurrentSchedule(widget.medicationId);
      if (!mounted || schedule == null) return;
      _scheduleId = schedule.id;
      _existingSchedule = schedule;
      _instruction.text = schedule.rawInstruction ?? '';
      _mealRelation = schedule.mealRelation ?? 'unspecified';
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll(
          schedule.times.map(
            (item) => _RoutineRow(
              period: item.period,
              time: item.localTime,
              quantity: item.quantityText,
              unit: item.unit,
            ),
          ),
        );
      setState(() {});
    } on Object {
      // New routine path is valid when no current schedule exists.
    }
  }

  @override
  void dispose() {
    _instruction.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    final clocks = _rows.map((row) => row.time.text.trim()).toList();
    if (clocks.toSet().length != clocks.length) {
      setState(() => _error = 'Reminder times must be unique.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existing = _existingSchedule;
      final draft = ScheduleDraft(
        rawInstruction: _instruction.text,
        mealRelation: _mealRelation,
        timezone: existing?.timezone ?? 'Asia/Dhaka',
        startDate: existing?.startDate ?? DateTime.now(),
        endDate: existing?.endDate,
        times: _rows
            .map(
              (row) => ScheduleDraftTime(
                period: row.period,
                localTime: row.time.text.trim(),
                quantityText: row.quantity.text.trim(),
                unit: row.unit.text.trim(),
              ),
            )
            .toList(growable: false),
      );
      final isNewRoutine = _scheduleId == null;
      if (isNewRoutine) {
        await ref
            .read(scheduleRepositoryProvider)
            .createSchedule(widget.medicationId, draft);
      } else {
        await ref
            .read(scheduleRepositoryProvider)
            .updateSchedule(_scheduleId!, draft);
      }
      try {
        await ref.read(reminderCoordinatorProvider).refresh();
      } on Object {
        // The routine is already saved; reminder refresh is best-effort.
      }
      if (!mounted) return;
      if (isNewRoutine) {
        context.go(
          '/family/${widget.memberId}/medications/${widget.medicationId}/reminders',
        );
      } else {
        context.go('/today');
      }
    } on ApiError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setRoutine)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                l10n.reminderPrescriptionDisclaimer,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('routineInstruction'),
                controller: _instruction,
                decoration: InputDecoration(labelText: l10n.sourceInstruction),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _mealRelation,
                decoration: InputDecoration(labelText: l10n.mealRelation),
                items: <String>['unspecified', 'before_food', 'after_food', 'with_food']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _mealRelation = value);
                },
              ),
              const SizedBox(height: 20),
              for (var index = 0; index < _rows.length; index++)
                _RoutineRowFields(index: index, row: _rows[index]),
              TextButton.icon(
                onPressed: _rows.length >= 8
                    ? null
                    : () => setState(() => _rows.add(_RoutineRow())),
                icon: const Icon(Icons.add),
                label: Text(l10n.addReminderTime),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(l10n.saveRoutine),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineRow {
  _RoutineRow({
    this.period = 'morning',
    String time = '08:00',
    String quantity = '1',
    String unit = 'tablet',
  })  : time = TextEditingController(text: time),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit);

  String period;
  final TextEditingController time;
  final TextEditingController quantity;
  final TextEditingController unit;

  void dispose() {
    time.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

class _RoutineRowFields extends StatelessWidget {
  const _RoutineRowFields({required this.index, required this.row});

  final int index;
  final _RoutineRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              key: Key('routineTime$index'),
              controller: row.time,
              decoration: InputDecoration(labelText: l10n.reminderTime),
              validator: (value) {
                final text = value?.trim() ?? '';
                return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)
                    ? null
                    : l10n.requiredFieldError;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.quantity,
              decoration: InputDecoration(labelText: l10n.quantity),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                return parsed != null && parsed > 0 ? null : l10n.requiredFieldError;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.unit,
              decoration: InputDecoration(labelText: l10n.unitLabel),
              validator: (value) =>
                  (value?.trim().isNotEmpty ?? false) ? null : l10n.requiredFieldError,
            ),
          ),
        ],
      ),
    );
  }
}
