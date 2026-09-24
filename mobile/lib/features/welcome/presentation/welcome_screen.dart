import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 44),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: FamilyMedColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: FamilyMedColors.primary,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.welcomeHeadline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.welcomeBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FamilyMedColors.textSecondary,
                    ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/register'),
                child: Text(l10n.getStarted),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(l10n.alreadyHaveAccount),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.aiConfirmationNote,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
