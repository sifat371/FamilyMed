import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/core/widgets/familymed_ui.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WhoDoYouCareForScreen extends StatefulWidget {
  const WhoDoYouCareForScreen({super.key});

  @override
  State<WhoDoYouCareForScreen> createState() => _WhoDoYouCareForScreenState();
}

class _WhoDoYouCareForScreenState extends State<WhoDoYouCareForScreen> {
  String _selection = 'parent';

  String get _relationship {
    switch (_selection) {
      case 'parent':
        return 'parent';
      case 'spouse':
        return 'spouse';
      case 'child':
        return 'child';
      case 'self':
        return 'myself';
      default:
        return 'other';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choices = <(String, String)>[
      ('parent', l10n.myParent),
      ('spouse', l10n.mySpouse),
      ('child', l10n.myChild),
      ('self', l10n.myself),
      ('other', l10n.someoneElse),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FamilyMedPill(label: l10n.familyFirst),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.whoDoYouCareFor,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.careForSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FamilyMedColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              ...choices.map(
                (choice) {
                  final selected = _selection == choice.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selection = choice.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? FamilyMedColors.primarySoft
                              : FamilyMedColors.surface,
                          border: Border.all(
                            color: selected
                                ? FamilyMedColors.primary
                                : FamilyMedColors.border,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.circle
                                  : Icons.radio_button_unchecked,
                              size: selected ? 14 : 18,
                              color: selected
                                  ? FamilyMedColors.primary
                                  : FamilyMedColors.textSecondary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                choice.$2,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final relationship = Uri.encodeQueryComponent(_relationship);
                  context.go('/family/new?relationship=$relationship');
                },
                child: Text(l10n.continueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
