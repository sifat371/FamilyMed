import 'package:familymed/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the FamilyMed welcome screen', (tester) async {
    await tester.pumpWidget(const FamilyMedApp());
    await tester.pumpAndSettle();

    expect(find.text('FamilyMed'), findsOneWidget);
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
