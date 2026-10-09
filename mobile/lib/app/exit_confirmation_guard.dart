import 'dart:async';

import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Prevents an accidental app exit when Android Back has no route to return to.
///
/// A genuine page stack is never intercepted: Android Back still pops the
/// previous screen. The guard is placed only on navigable app roots.
class ExitConfirmationGuard extends StatefulWidget {
  const ExitConfirmationGuard({super.key, required this.child});

  final Widget child;

  @override
  State<ExitConfirmationGuard> createState() => _ExitConfirmationGuardState();
}

class _ExitConfirmationGuardState extends State<ExitConfirmationGuard> {
  bool _confirming = false;

  Future<void> _confirmExit() async {
    if (_confirming || !mounted) return;
    _confirming = true;
    try {
      final l10n = AppLocalizations.of(context);
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.exitAppTitle),
          content: Text(l10n.exitAppMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.exitAppConfirm),
            ),
          ],
        ),
      );
      if (shouldExit == true && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPreviousPage = GoRouter.of(context).canPop();
    return PopScope(
      canPop: hasPreviousPage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !GoRouter.of(context).canPop()) {
          unawaited(_confirmExit());
        }
      },
      child: widget.child,
    );
  }
}
