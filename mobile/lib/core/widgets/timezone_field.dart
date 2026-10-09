import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _timezones = (() {
  tzdata.initializeTimeZones();
  return tz.timeZoneDatabase.locations.keys.toList()..sort();
})();

/// An explicit care timezone; never infer it from medication instructions.
class TimezoneField extends StatelessWidget {
  const TimezoneField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.careTimezone),
      items: _timezones
          .map(
            (zone) => DropdownMenuItem(
              value: zone,
              child: Text(
                zone.replaceAll('_', ' '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (zone) {
              if (zone != null) onChanged!(zone);
            },
    );
  }
}
