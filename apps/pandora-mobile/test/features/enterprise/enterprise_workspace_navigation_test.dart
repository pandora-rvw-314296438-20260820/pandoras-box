import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/widgets/pandora_navigation.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_workspace_home.dart';

void main() {
  Future<void> mount(WidgetTester tester, {double width = 390, double height = 844, double scale = 1,
      ValueChanged<EnterpriseWorkspaceSelection>? onOpen, VoidCallback? onActivity, VoidCallback? onMore}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
        child: PandoraNavigationScope(openDrawer: () {}, child: EnterpriseWorkspaceHome(
          onOpen: onOpen ?? (_) {}, onSearchChats: () {}, onActivity: onActivity ?? () {}, onMore: onMore ?? () {},
        )),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>('workspace-expand-' + key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byKey(const ValueKey<String>('enterprise-workspace-list')));
    final header = tester.getRect(target);
    expect(header.top, greaterThanOrEqualTo(viewport.top - .5), reason: '$key header cannot be lost above the viewport');
    expect(header.bottom, lessThanOrEqualTo(viewport.bottom + .5));
  }

  for (final width in [320.0, 360.0, 390.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('Owners header and names stay readable at $width / $scale', (tester) async {
        await mount(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('Pandora'), findsOneWidget);
        for (final workspace in enterpriseWorkspaces) {
          final text = tester.renderObject<RenderParagraph>(find.text(workspace.name));
          expect(text.didExceedMaxLines, isFalse, reason: workspace.name);
          final subtitle = tester.renderObject<RenderParagraph>(find.text(workspace.subtitle));
          expect(subtitle.didExceedMaxLines, isFalse, reason: workspace.subtitle);
          expect(find.byKey(ValueKey<String>('workspace-tax-quick-' + workspace.key)), findsOneWidget);
        }
        final search = tester.widget<IconButton>(find.byKey(const ValueKey<String>('workspace-home-search')));
        expect(search.color, Colors.white);
        expect(tester.getSize(find.byKey(const ValueKey<String>('workspace-home-search'))).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('recording 6104: switching expanded workspaces preserves the selected header', (tester) async {
    await mount(tester);
    for (final key in ['plp-boracay', '1064-euro-fish-traders', 'batalla-associates', 'bok', 'plp-boracay']) {
      await expand(tester, key);
      final profile = enterpriseWorkspaces.firstWhere((workspace) => workspace.key == key);
      expect(find.byKey(ValueKey<String>('workspace-tax-quick-' + key)), findsNothing);
      expect(find.byKey(ValueKey<String>(key + '-tax-compliance')), findsOneWidget);
      expect(profile.sections[0].routeSlug, 'home');
      expect(profile.sections[2].routeSlug, 'tax-compliance');
      for (final other in enterpriseWorkspaces.where((workspace) => workspace.key != key)) {
        expect(find.byKey(ValueKey<String>(other.key + '-home')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every workspace tax route remains scoped and appears once per card', (tester) async {
    EnterpriseWorkspaceSelection? selected;
    await mount(tester, onOpen: (value) => selected = value);
    for (final workspace in enterpriseWorkspaces) {
      final quick = find.byKey(ValueKey<String>('workspace-tax-quick-' + workspace.key));
      await tester.ensureVisible(quick);
      await tester.pumpAndSettle();
      await tester.tap(quick);
      await tester.pump();
      expect(selected?.workspace.key, workspace.key);
      expect(selected?.section.surface, 'enterprise_tax');
      expect(selected?.enterpriseContext['route'], '/enterprise/workspaces/${workspace.key}/tax-compliance');
    }
    expect(find.textContaining('Calculation ready'), findsNothing);
    expect(find.textContaining('Professional review gate'), findsNothing);
  });

  testWidgets('compact toolbar still exposes Activity and Settings', (tester) async {
    var activity = 0;
    var more = 0;
    await mount(tester, width: 320, onActivity: () => activity++, onMore: () => more++);
    final menu = find.byKey(const ValueKey<String>('workspace-home-more'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(activity, 1);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings & More'));
    await tester.pumpAndSettle();
    expect(more, 1);
  });

  testWidgets('workspace can collapse without animation races or losing its header', (tester) async {
    await mount(tester, width: 360, height: 640);
    await expand(tester, 'batalla-associates');
    await expand(tester, 'batalla-associates');
    expect(find.byKey(const ValueKey<String>('batalla-associates-home')), findsNothing);
    expect(find.byKey(const ValueKey<String>('workspace-tax-quick-batalla-associates')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
