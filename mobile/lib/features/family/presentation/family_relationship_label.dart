import 'package:familymed/l10n/app_localizations.dart';

String familyRelationshipLabel(
  AppLocalizations l10n,
  String relationship,
) {
  return switch (relationship.trim().toLowerCase()) {
    'mother' => l10n.motherRelationship,
    'father' => l10n.fatherRelationship,
    'parent' => l10n.parentRelationship,
    'spouse' => l10n.spouseRelationship,
    'child' => l10n.childRelationship,
    'myself' || 'self' => l10n.selfRelationship,
    'other' => l10n.otherRelationship,
    _ => relationship,
  };
}
