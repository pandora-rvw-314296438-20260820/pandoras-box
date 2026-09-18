import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_stack.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets(
    'Enterprise command stack survives required Android widths and text scales',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const widths = <double>[320, 360, 390, 412, 430];
      const scales = <double>[1, 1.3, 2];
      const pageContext = EnterprisePageContext(
        surface: 'enterprise_overview',
        route: '/enterprise/overview',
        capabilities: <String>['enterprise_overview.read'],
        identityScope: 'enterprise_workspace',
      );

      for (final width in widths) {
        tester.view.physicalSize = Size(width, 1600);
        for (final scale in scales) {
          await tester.pumpWidget(
            testApp(
              textScaler: TextScaler.linear(scale),
              child: PandoraDependencies(
                auth: const FakeAuth(),
                repository: FakeRepository(),
                intelligence: null,
                diagnostics: DiagnosticsStore(),
                child: const Scaffold(
                  body: EnterprisePageContextScope(
                    pageContext: pageContext,
                    child: EnterpriseCommandStack(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'PLP Boracay owner workspace with a deliberately long business status message that must remain readable.',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final commandBar =
              find.byKey(const ValueKey<String>('enterprise-command-bar'));
          final send = find.byTooltip('Send command');
          expect(commandBar, findsOneWidget);
          expect(send, findsOneWidget);
          expect(find.byType(TextField), findsWidgets);

          final rect = tester.getRect(commandBar);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width + 1));
          expect(tester.getSize(send).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(send).height, greaterThanOrEqualTo(48));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Enterprise layout failed at ${width}px and ${scale}x text',
          );
        }
      }
    },
  );
}
