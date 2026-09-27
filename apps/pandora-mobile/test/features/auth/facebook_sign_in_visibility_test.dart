import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/auth/sign_in_screen.dart';

void main() {
  testWidgets('disabled Facebook provider hides the Android button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(checkFacebookProviderEnabled: () async => false),
      ));
      await tester.pump();
      expect(find.text('Continue with Facebook'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('enabled Facebook provider shows the Android button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(checkFacebookProviderEnabled: () async => true),
      ));
      await tester.pump();
      expect(find.text('Continue with Facebook'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('provider availability remains hidden while still loading', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final pending = Completer<bool>();
    try {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(checkFacebookProviderEnabled: () => pending.future),
      ));
      expect(find.text('Continue with Facebook'), findsNothing);
      pending.complete(true);
      await tester.pump();
      expect(find.text('Continue with Facebook'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('disabling provider after display prevents OAuth launch', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var reads = 0;
    try {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(checkFacebookProviderEnabled: () async => ++reads == 1),
      ));
      await tester.pump();
      final facebookButton = find.text('Continue with Facebook');
      expect(facebookButton, findsOneWidget);
      await tester.ensureVisible(facebookButton);
      await tester.tap(facebookButton);
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Continue with Facebook'), findsNothing);
      expect(find.text('Facebook sign-in is not available yet.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unsupported native platform stays hidden even if enabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var called = false;
    try {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(checkFacebookProviderEnabled: () async {
          called = true;
          return true;
        }),
      ));
      await tester.pump();
      expect(called, isFalse);
      expect(find.text('Continue with Facebook'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
