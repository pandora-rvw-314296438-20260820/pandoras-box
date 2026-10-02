import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/widgets/pandora_mark.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../../test/helpers/fake_owner_api.dart';
import '../../test/helpers/test_app.dart';

const _surfaceKey = ValueKey<String>('lane-e-evidence-surface');
const _phoneSize = Size(390, 844);
const _fontFamily = 'Roboto';
const _iconFontFamily = 'MaterialIcons';

Future<void> _loadFonts() async {
  final separator = Platform.pathSeparator;
  final roots = <String>{};
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    roots.add(configuredRoot);
  }
  var cursor = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 12; depth++) {
    roots.add(cursor.path);
    final parent = cursor.parent;
    if (parent.path == cursor.path) break;
    cursor = parent;
  }

  File? textFont;
  File? iconFont;
  for (final root in roots) {
    final materialFonts =
        '$root${separator}bin${separator}cache${separator}artifacts'
        '${separator}material_fonts';
    final textCandidate = File('$materialFonts${separator}Roboto-Regular.ttf');
    final iconCandidate =
        File('$materialFonts${separator}MaterialIcons-Regular.otf');
    if (textFont == null && textCandidate.existsSync()) {
      textFont = textCandidate;
    }
    if (iconFont == null && iconCandidate.existsSync()) {
      iconFont = iconCandidate;
    }
    if (textFont != null && iconFont != null) break;
  }

  if (textFont == null || iconFont == null) {
    throw StateError('Pinned Flutter visual fonts were not found.');
  }

  final textBytes = await textFont.readAsBytes();
  final iconBytes = await iconFont.readAsBytes();
  final textLoader = FontLoader(_fontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(textBytes)));
  final iconLoader = FontLoader(_iconFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
  await Future.wait(<Future<void>>[textLoader.load(), iconLoader.load()]);
}

Widget _withFonts(Widget child) => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: _fontFamily),
            primaryTextTheme:
                theme.primaryTextTheme.apply(fontFamily: _fontFamily),
          ),
          child: child,
        );
      },
    );

class _EvidenceRepository extends FakeRepository {
  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) async =>
      const IntakeReceipt(
        reply:
            'I found six affected reservations. The conversation is still available while you move through the business.',
        needsApproval: false,
        actionId: 'lane-e-evidence-chat',
        status: IntakeStatus(
          whatChanged: 'Six affected reservations were identified.',
          whereWeAre: 'Reservations',
          whatIsDone: 'The business context was preserved.',
          whatIsHappeningNow: 'The conversation is active.',
          whatIWillDoNext: 'Continue with the next owner instruction.',
        ),
      );
}

Future<void> _pumpVisualFrames(WidgetTester tester) async {
  for (final frame in <Duration>[
    Duration.zero,
    Duration(milliseconds: 50),
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
  ]) {
    await tester.pump(frame);
  }
}

Future<void> _precacheMark(WidgetTester tester) async {
  final mark = find.byType(PandoraMark);
  if (mark.evaluate().isEmpty) return;
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage(PandoraMark.assetPath),
      tester.element(mark.first),
    );
  });
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surfaceKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } finally {
      image.dispose();
    }
  });
  expect(bytes, isNotNull);
  final output = File('build/lane-e-shell-evidence/$name.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes!);
  expect(output.lengthSync(), greaterThan(0));
}

void main() {
  testWidgets(
    'Lane E shell evidence',
    (tester) async {
      await tester.runAsync(_loadFonts);
      await setTestSurface(tester, logicalSize: _phoneSize);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('pandora/local_ai'),
        (call) async => call.method == 'status'
            ? <String, Object?>{
                'supported': false,
                'configured': false,
                'loaded': false,
              }
            : null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('pandora/local_ai'),
          null,
        ),
      );

      final repository = _EvidenceRepository();
      await tester.pumpWidget(
        PandoraDependencies(
          auth: const FakeAuth(),
          repository: repository,
          diagnostics: DiagnosticsStore(),
          child: testApp(
            themeMode: ThemeMode.dark,
            child: _withFonts(
              const RepaintBoundary(
                key: _surfaceKey,
                child: PandoraChatShell(),
              ),
            ),
          ),
        ),
      );
      await _pumpVisualFrames(tester);
      await _precacheMark(tester);

      final objective =
          find.byKey(const ValueKey<String>('ask-pandora-objective'));
      final composerDock =
          find.byKey(const ValueKey<String>('ask-pandora-composer-dock'));
      final navigation =
          find.byKey(const ValueKey<String>('workspace-home-navigation'));
      final workspaceList =
          find.byKey(const ValueKey<String>('enterprise-workspace-list'));
      final historyOffstage = find.byKey(
        const ValueKey<String>('pandora-active-chat-history-offstage'),
      );

      expect(objective, findsOneWidget);
      expect(composerDock, findsOneWidget);
      expect(navigation, findsOneWidget);
      expect(workspaceList, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('workspace-home-brand')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('workspace-home-title')),
        findsNothing,
      );
      expect(tester.widget<Offstage>(historyOffstage).offstage, isTrue);
      expect(find.text('What can I help with?'), findsNothing,
          reason: 'legacy empty-state copy is absent');
      expect(
        find.text('Ask a question, describe a change, or tell Pandora what you want to build.'),
        findsNothing,
      );
      expect(
        find.descendant(
          of: composerDock,
          matching: find.byType(FilledButton),
        ),
        findsNothing,
        reason: 'bare shell composer has no filled capsule control',
      );
      final dockWidget = tester.widget<Container>(composerDock);
      final dockDecoration = dockWidget.decoration as BoxDecoration;
      expect(
        dockDecoration.color,
        const Color(0xFF050505),
        reason: 'scrolling business content must never show through the composer',
      );
      final businessClearance = tester.widget<Padding>(
        find.byKey(
          const ValueKey<String>('pandora-business-composer-clearance'),
        ),
      );
      expect(
        (businessClearance.padding as EdgeInsets).bottom,
        greaterThanOrEqualTo(68),
      );
      expect(
        find.byType(Divider),
        findsNothing,
        reason:
            'the resting Lane E top bar must not render a horizontal divider',
      );

      final fixedNavigationTop = tester.getTopLeft(navigation).dy;
      final fixedComposerBottom = tester.getRect(composerDock).bottom;
      await _capture(tester, '01-resting-composer');

      await tester.tap(objective);
      await tester.enterText(
        objective,
        'Why did direct bookings fall?\n'
        'Show the affected reservations.\n'
        'Keep this conversation with me.',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('ask-pandora-plus')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(objective).maxLines, 5);
      await _capture(tester, '02-typing');

      await tester.enterText(objective, '');
      await tester.pump();
      final chatState = tester.state<AskPandoraScreenState>(
        find.byType(AskPandoraScreen),
      );
      final reply = await chatState.submitExternalPrompt(
        'Why did direct bookings fall?',
        requestFocus: false,
      );
      await tester.pumpAndSettle();
      await _precacheMark(tester);
      expect(reply, contains('six affected reservations'));
      expect(tester.widget<Offstage>(historyOffstage).offstage, isFalse);
      final history =
          find.byKey(const ValueKey<String>('pandora-active-chat-history'));
      expect(history, findsOneWidget);
      expect(
        tester.getRect(history).bottom,
        lessThanOrEqualTo(tester.getRect(composerDock).top + 1),
      );
      await _capture(tester, '03-history-expanded');

      chatState.minimizeHistory();
      await tester.pumpAndSettle();
      expect(tester.widget<Offstage>(historyOffstage).offstage, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('workspace-expand-plp-boracay')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: workspaceList,
        matching: find.byType(Scrollable),
      ).first;
      final scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.maxScrollExtent, greaterThan(500));
      final beforeScroll = scrollState.position.pixels;
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(beforeScroll));
      expect(
        tester.getTopLeft(navigation).dy,
        closeTo(fixedNavigationTop, 0.1),
      );
      expect(
        tester.getRect(composerDock).bottom,
        closeTo(fixedComposerBottom, 0.1),
      );
      final lastBusinessControl = find.byKey(
        const ValueKey<String>('workspace-tax-quick-bok'),
      );
      expect(lastBusinessControl, findsOneWidget);
      expect(
        tester.getRect(lastBusinessControl).bottom,
        lessThanOrEqualTo(tester.getRect(composerDock).top - 4),
        reason: 'the final business control must scroll fully clear of Pandora',
      );
      await _capture(tester, '04-long-page-scrolled-under-composer');

      final maxScroll = scrollState.position.pixels;
      scrollState.position.jumpTo((maxScroll - 360).clamp(0.0, maxScroll));
      await tester.pumpAndSettle();
      final firstScroll = scrollState.position.pixels;
      await tester.drag(workspaceList, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(firstScroll));
      expect(
        tester.getTopLeft(navigation).dy,
        closeTo(fixedNavigationTop, 0.1),
      );
      expect(
        tester.getRect(composerDock).bottom,
        closeTo(fixedComposerBottom, 0.1),
      );
      await _capture(tester, '05-hamburger-fixed');

      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
