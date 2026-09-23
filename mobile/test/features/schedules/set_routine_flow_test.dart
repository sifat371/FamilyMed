import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('routine screen separates reminder times from prescription text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: <Locale>[Locale('en'), Locale('bn')],
        home: SetRoutineScreen(
          memberId: 'member-1',
          medicationId: 'med-1',
        ),
      ),
    );

    expect(
      find.text('Reminder times are not part of the prescription.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('routineInstruction')), findsOneWidget);
    expect(find.byKey(const Key('routineTime0')), findsOneWidget);
  });
}
