import 'package:familymed/app/app.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyTokenStore implements TokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthTokens?> read() async => null;

  @override
  Future<void> write(AuthTokens value) async {}
}

Widget _app(Locale locale) {
  return ProviderScope(
    overrides: [tokenStoreProvider.overrideWithValue(_EmptyTokenStore())],
    child: FamilyMedApp(locale: locale),
  );
}

void main() {
  testWidgets('renders English welcome copy', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('renders Bangla welcome copy', (tester) async {
    await tester.pumpWidget(_app(const Locale('bn')));
    await tester.pumpAndSettle();
    expect(find.text('আপনার প্রিয়জনের ওষুধের যত্ন।'), findsOneWidget);
    expect(find.text('শুরু করুন'), findsOneWidget);
    expect(find.text('আমার ইতিমধ্যে একটি অ্যাকাউন্ট আছে'), findsOneWidget);
  });
}
