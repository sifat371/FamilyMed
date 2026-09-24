import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _timeZonesInitialized = false;

void _ensureTimeZones() {
  if (_timeZonesInitialized) return;
  tzdata.initializeTimeZones();
  _timeZonesInitialized = true;
}

TimeOfDay timeOfDayFromLocalTime(String value) {
  final parts = value.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return TimeOfDay(
    hour: hour.clamp(0, 23).toInt(),
    minute: minute.clamp(0, 59).toInt(),
  );
}

String localTimeFromTimeOfDay(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatLocalTime12h(BuildContext context, String value) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    timeOfDayFromLocalTime(value),
    alwaysUse24HourFormat: false,
  );
}

String formatInstantInTimezone12h(
  BuildContext context,
  DateTime value,
  String timezoneName,
) {
  _ensureTimeZones();
  final location = tz.getLocation(timezoneName);
  final local = tz.TZDateTime.from(value.toUtc(), location);
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: local.hour, minute: local.minute),
    alwaysUse24HourFormat: false,
  );
}
