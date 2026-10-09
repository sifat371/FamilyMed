import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';

class FamilyMedPill extends StatelessWidget {
  const FamilyMedPill({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? FamilyMedColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foregroundColor ?? FamilyMedColors.primary,
              ),
        ),
      ),
    );
  }
}

class FamilyMedSoftCard extends StatelessWidget {
  const FamilyMedSoftCard({
    super.key,
    required this.child,
    this.color = FamilyMedColors.primarySoft,
    this.padding = const EdgeInsets.all(17),
    this.borderColor,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? FamilyMedColors.border),
      ),
      child: child,
    );
  }
}

class FamilyMedSectionLabel extends StatelessWidget {
  const FamilyMedSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: FamilyMedColors.textSecondary,
          ),
    );
  }
}
