import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/auth/sign_in_screen.dart';

void main() {
  testWidgets(
    'Android sign-in screen exposes Continue with Facebook',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
        expect(find.text('Continue with Facebook'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'unsupported native sign-in screen hides Continue with Facebook',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
        expect(find.text('Continue with Facebook'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
