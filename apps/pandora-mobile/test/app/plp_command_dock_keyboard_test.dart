import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';

void main() {
  testWidgets('persistent command dock stays above the keyboard while typing',
      (tester) async {
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

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-command-field')),
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

  testWidgets('another PLP field does not pull the command dock over its form',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final commandController = TextEditingController();
    final commandFocus = FocusNode();
    final otherController = TextEditingController();
    final otherFocus = FocusNode();
    addTearDown(commandController.dispose);
    addTearDown(commandFocus.dispose);
    addTearDown(otherController.dispose);
    addTearDown(otherFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            viewInsets: EdgeInsets.only(bottom: 320),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: TextField(
              key: const ValueKey<String>('other-plp-field'),
              controller: otherController,
              focusNode: otherFocus,
            ),
            bottomNavigationBar: PlpCommandDock(
              controller: commandController,
              focusNode: commandFocus,
              onSubmit: () async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('other-plp-field')));
    await tester.pumpAndSettle();

    final dock = tester.getRect(
      find.byKey(const ValueKey<String>('plp-persistent-command-bar')),
    );
    expect(commandFocus.hasFocus, isFalse);
    expect(otherFocus.hasFocus, isTrue);
    expect(dock.bottom, greaterThan(844 - 320));

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-command-field')),
    );
    await tester.pumpAndSettle();
    final liftedDock = tester.getRect(
      find.byKey(const ValueKey<String>('plp-persistent-command-bar')),
    );
    expect(commandFocus.hasFocus, isTrue);
    expect(liftedDock.bottom, lessThanOrEqualTo(844 - 320));

    await tester.tap(find.byKey(const ValueKey<String>('other-plp-field')));
    await tester.pumpAndSettle();
    final restoredDock = tester.getRect(
      find.byKey(const ValueKey<String>('plp-persistent-command-bar')),
    );
    expect(commandFocus.hasFocus, isFalse);
    expect(otherFocus.hasFocus, isTrue);
    expect(
      restoredDock.bottom,
      greaterThan(844 - 320),
      reason:
          'Switching to another PLP field must immediately release the shared dock.',
    );
  });
}
