import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Keeps automated widget failures bounded and attributable to one test case.
///
/// Flutter's automated widget-test default is intentionally generous. That is
/// useful interactively, but a deadlocked screenshot capture can otherwise hide
/// every later CI proof stage for minutes. Pandora's tests are individually
/// small, so thirty seconds is a fail-closed ceiling rather than a performance
/// target.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 30));
  }
  await testMain();
}
