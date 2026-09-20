import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_workspace_home.dart';

void main() {
  testWidgets('PLP workspace header fits a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseWorkspaceHome(
          onOpen: (_) {},
          onSearchChats: () {},
          onActivity: () {},
          onMore: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('workspace-home-brand')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
