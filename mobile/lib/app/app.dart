import 'package:familymed/app/router.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';

class FamilyMedApp extends StatelessWidget {
  const FamilyMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FamilyMed',
      theme: FamilyMedTheme.light,
      routerConfig: appRouter,
    );
  }
}
