import 'package:familymed/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders English welcome copy', (tester) async {
    await tester.pumpWidget(const FamilyMedApp(locale: Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('renders Bangla welcome copy', (tester) async {
    await tester.pumpWidget(const FamilyMedApp(locale: Locale('bn')));
    await tester.pumpAndSettle();
    expect(find.text('আপনার প্রিয়জনের ওষুধের যত্ন।'), findsOneWidget);
    expect(find.text('শুরু করুন'), findsOneWidget);
  });
}
