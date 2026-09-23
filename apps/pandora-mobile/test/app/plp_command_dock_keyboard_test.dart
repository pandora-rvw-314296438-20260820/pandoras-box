import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';

void main() {
  testWidgets('persistent command dock stays above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            viewInsets: EdgeInsets.only(bottom: 320),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            bottomNavigationBar: PlpCommandDock(
              controller: controller,
              focusNode: focusNode,
              onSubmit: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dock = tester.getRect(
      find.byKey(const ValueKey<String>('plp-persistent-command-bar')),
    );
    expect(dock.bottom, lessThanOrEqualTo(844 - 320));
    expect(
      find.byKey(const ValueKey<String>('plp-command-keyboard-offset')),
      findsOneWidget,
    );
  });
}
