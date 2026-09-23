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
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text(l10n.familyFirst)),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.whoDoYouCareFor,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              ...choices.map(
                (choice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selection = choice.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selection == choice.$1
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(choice.$2)),
                        ],
                      ),
                    ),
                  ),
                ),
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
