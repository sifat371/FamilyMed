import 'package:flutter/material.dart';

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
