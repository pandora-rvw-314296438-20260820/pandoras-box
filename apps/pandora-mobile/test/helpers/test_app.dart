import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_theme.dart';

Widget testApp({
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: PandoraTheme.porcelain,
  darkTheme: PandoraTheme.graphite,
  themeMode: themeMode,
  themeAnimationDuration: Duration.zero,
  builder: (context, builtChild) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: textScaler, disableAnimations: true),
    child: builtChild!,
  ),
  home: child,
);

Future<void> setTestSurface(
  WidgetTester tester, {
  required Size logicalSize,
  double devicePixelRatio = 1,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = logicalSize * devicePixelRatio;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
