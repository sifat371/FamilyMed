import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/formatters/quantity_format.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/core/time/local_time_format.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/features/today/data/today_repository.dart';
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
              time: item.localTime,
              quantity: compactQuantity(item.quantityText),
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
    final clocks = _rows.map((row) => row.time).toList();
    if (clocks.toSet().length != clocks.length) {
      setState(
        () => _error = AppLocalizations.of(context).duplicateReminderTimes,
      );
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
                period: _periodForTime(row.time),
                localTime: row.time,
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
      ref.invalidate(todayProvider);
      ref.invalidate(memberMedicationsProvider(widget.memberId));
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

  String _periodForTime(String localTime) {
    final hour = int.tryParse(localTime.split(':').first) ?? 0;
    if (hour >= 5 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    return 'night';
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
                items: <String, String>{
                  'unspecified': l10n.unspecified,
                  'before_food': l10n.beforeFood,
                  'after_food': l10n.afterFood,
                  'with_food': l10n.withFood,
                  'none': l10n.noMealRelation,
                }
                    .entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _mealRelation = value);
                },
              ),
              const SizedBox(height: 20),
              for (var index = 0; index < _rows.length; index++)
                _RoutineRowFields(
                  index: index,
                  row: _rows[index],
                  canRemove: _rows.length > 1,
                  onTimeChanged: (value) {
                    setState(() => _rows[index].time = value);
                  },
                  onRemove: () {
                    setState(() {
                      final row = _rows.removeAt(index);
                      row.dispose();
                    });
                  },
                ),
              TextButton.icon(
                onPressed: _rows.length >= 8
                    ? null
                    : () => setState(() => _rows.add(_RoutineRow())),
                icon: const Icon(Icons.add),
                label: Text(l10n.addReminderTime),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.saveRoutine),
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
    this.time = '08:00',
    String quantity = '1',
    String unit = 'tablet',
  })  : quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit);

  String time;
  final TextEditingController quantity;
  final TextEditingController unit;

  void dispose() {
    quantity.dispose();
    unit.dispose();
  }
}

class _RoutineRowFields extends StatelessWidget {
  const _RoutineRowFields({
    required this.index,
    required this.row,
    required this.canRemove,
    required this.onTimeChanged,
    required this.onRemove,
  });

  final int index;
  final _RoutineRow row;
  final bool canRemove;
  final ValueChanged<String> onTimeChanged;
  final VoidCallback onRemove;

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: timeOfDayFromLocalTime(row.time),
      helpText: AppLocalizations.of(context).reminderTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      onTimeChanged(localTimeFromTimeOfDay(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 2,
            child: InkWell(
              key: Key('routineTime$index'),
              onTap: () => _pickTime(context),
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.reminderTime,
                  suffixIcon: const Icon(Icons.schedule),
                ),
                child: Text(
                  formatLocalTime12h(context, row.time),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.quantity),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                return parsed != null && parsed > 0
                    ? null
                    : l10n.requiredFieldError;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.unit,
              decoration: InputDecoration(labelText: l10n.unitLabel),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : l10n.requiredFieldError,
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 4),
            IconButton(
              key: Key('removeRoutineTime$index'),
              onPressed: onRemove,
              tooltip: l10n.removeReminderTime,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    );
  }
}
