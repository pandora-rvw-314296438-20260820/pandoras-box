import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/design/pandora_theme.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';
import 'package:pandora_mobile/core/widgets/pandora_navigation.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

void main() {
  testWidgets('Apollo mobile chat acceptance on Android', (tester) async {
    final chatKey = GlobalKey<AskPandoraScreenState>();
    final intelligence = _FixtureIntelligence();

    await tester.pumpWidget(
      PandoraDependencies(
        auth: const _FixtureAuth(),
        repository: _FixtureRepository(),
        diagnostics: DiagnosticsStore(),
        intelligence: intelligence,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: PandoraTheme.porcelain,
          darkTheme: PandoraTheme.graphite,
          themeMode: ThemeMode.dark,
          home: AskPandoraScreen(
            key: chatKey,
            onSearchChats: () {},
            onMore: () {},
            enterpriseContext: const <String, Object?>{
              'surface': 'enterprise_app_users',
              'selectedObject': <String, Object?>{
                'workspaceKey': 'apollo-runtime',
              },
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await chatKey.currentState!.loadThread('apollo-runtime-thread');
    await tester.pump(const Duration(milliseconds: 800));

    await binding.convertFlutterSurfaceToImage();
    await _shot('initial');

    final list = find.byType(ListView).first;
    final composer = find.byKey(const ValueKey<String>('ask-pandora-composer'));
    final objective = find.byKey(const ValueKey<String>('ask-pandora-objective'));
    final header = find.byType(PandoraPageHeader);
    final latestUser = find.textContaining('LATEST-USER-29');
    final latestAssistant = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? '').contains('LATEST-PANDORA-29'),
    );

    expect(latestUser, findsOneWidget);
    expect(latestAssistant, findsOneWidget);
    expect(find.textContaining('Bounded Enterprise page context'), findsNothing);
    expect(
      find.textContaining(
        'Treat this context as navigation and scope information only',
      ),
      findsNothing,
    );
    _expectNoFlutterException(tester, 'initial render');

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final assistantWidth = tester.getRect(latestAssistant).width;
    expect(
      assistantWidth,
      greaterThan(screenWidth * 0.68),
      reason: 'Long Pandora answers must use sensible mobile width.',
    );

    final headerRect = tester.getRect(header);
    var underHeader = false;
    for (var attempt = 0; attempt < 8 && !underHeader; attempt++) {
      await tester.drag(list, const Offset(0, 430));
      await tester.pump(const Duration(milliseconds: 180));
      for (var i = 0; i < 29; i++) {
        final marker = i.toString().padLeft(2, '0');
        for (final prefix in const ['USER', 'PANDORA']) {
          final finder = find.textContaining('$prefix-$marker');
          if (finder.evaluate().isEmpty) continue;
          final rect = tester.getRect(finder.first);
          final screenHeight =
              tester.view.physicalSize.height / tester.view.devicePixelRatio;
          if (rect.bottom > 0 &&
              rect.top < screenHeight &&
              rect.top < headerRect.bottom) {
            underHeader = true;
            break;
          }
        }
        if (underHeader) break;
      }
    }
    expect(
      underHeader,
      isTrue,
      reason: 'Conversation must be able to scroll behind floating top chrome.',
    );
    await _shot('under-floating-header');
    _expectNoFlutterException(tester, 'floating header scroll');

    await _resetToLatest(tester, chatKey);
    expect(latestUser, findsOneWidget);
    expect(latestAssistant, findsOneWidget);
    final beforeKeyboardComposer = tester.getRect(composer);
    await tester.tap(objective);
    await _waitForKeyboard(tester, objective, open: true);
    final keyboardInset =
        MediaQuery.of(tester.element(objective)).viewInsets.bottom;
    expect(keyboardInset, greaterThan(80));
    final withKeyboardComposer = tester.getRect(composer);
    expect(
      withKeyboardComposer.bottom,
      lessThan(beforeKeyboardComposer.bottom - 80),
      reason: 'Composer must move with the Android keyboard.',
    );
    expect(latestUser, findsOneWidget);
    expect(latestAssistant, findsOneWidget);
    expect(
      tester.getRect(latestAssistant).bottom,
      lessThanOrEqualTo(tester.getRect(composer).top + 2),
      reason: 'Latest Pandora response must stay above the composer.',
    );
    await _shot('keyboard-open');
    _expectNoFlutterException(tester, 'keyboard open');

    final beforeGrowth = tester.getRect(composer).height;
    await tester.enterText(
      objective,
      'line one\nline two\nline three\nline four\nline five\nline six',
    );
    await tester.pump(const Duration(milliseconds: 700));
    final afterGrowth = tester.getRect(composer).height;
    expect(
      afterGrowth,
      greaterThan(beforeGrowth + 20),
      reason: 'Multi-line composing must measurably grow the composer.',
    );
    expect(latestAssistant, findsOneWidget);
    expect(
      tester.getRect(latestAssistant).bottom,
      lessThanOrEqualTo(tester.getRect(composer).top + 2),
    );
    await _shot('composer-grown');
    _expectNoFlutterException(tester, 'composer growth');

    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await _waitForKeyboard(tester, objective, open: false);
    expect(
      MediaQuery.of(tester.element(objective)).viewInsets.bottom,
      lessThan(20),
    );
    expect(latestAssistant, findsOneWidget);
    await _shot('keyboard-closed');
    _expectNoFlutterException(tester, 'keyboard close');

    await _resetToLatest(tester, chatKey);
    final olderMarker = await _scrollToOlderReadingPosition(tester, list);
    expect(olderMarker, isNotNull);
    final olderFinder = find.textContaining(olderMarker!);
    expect(olderFinder, findsWidgets);
    final beforeReadingKeyboard = tester.getRect(olderFinder.first);

    await tester.tap(objective);
    await _waitForKeyboard(tester, objective, open: true);
    expect(olderFinder, findsWidgets);
    final afterReadingKeyboard = tester.getRect(olderFinder.first);
    expect(
      afterReadingKeyboard.bottom,
      greaterThan(0),
      reason: 'Older reading marker must remain on screen when keyboard opens.',
    );
    expect(
      (afterReadingKeyboard.top - beforeReadingKeyboard.top).abs(),
      lessThan(220),
      reason: 'Opening keyboard while reading older content must preserve context.',
    );
    expect(
      find.textContaining('LATEST-PANDORA-29'),
      findsNothing,
      reason: 'Reading older content must not jump back to the latest response.',
    );
    await _shot('reading-position-keyboard');
    _expectNoFlutterException(tester, 'reading position keyboard preservation');

    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await _waitForKeyboard(tester, objective, open: false);
    await _resetToLatest(tester, chatKey);
    final portraitSize = MediaQuery.of(tester.element(objective)).size;

    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.landscapeLeft],
    );
    await _waitForOrientationChange(tester, objective, portraitSize);
    final landscapeSize = MediaQuery.of(tester.element(objective)).size;
    expect(landscapeSize.width, greaterThan(landscapeSize.height));
    expect(find.textContaining('LATEST-PANDORA-29'), findsOneWidget);
    expect(composer, findsOneWidget);
    expect(find.textContaining('Bounded Enterprise page context'), findsNothing);
    await _shot('landscape');
    _expectNoFlutterException(tester, 'landscape viewport');

    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('Bounded Enterprise page context'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _resetToLatest(
  WidgetTester tester,
  GlobalKey<AskPandoraScreenState> chatKey,
) async {
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pump(const Duration(milliseconds: 400));
  chatKey.currentState!.newChat();
  await tester.pump(const Duration(milliseconds: 200));
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pump(const Duration(milliseconds: 250));
  final id = 'apollo-runtime-' +
      DateTime.now().microsecondsSinceEpoch.toString();
  await chatKey.currentState!.loadThread(id);
  await tester.pump(const Duration(milliseconds: 800));
}

Future<String?> _scrollToOlderReadingPosition(
  WidgetTester tester,
  Finder list,
) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.drag(list, const Offset(0, 420));
    await tester.pump(const Duration(milliseconds: 160));
    for (var i = 10; i < 25; i++) {
      final marker = i.toString().padLeft(2, '0');
      for (final prefix in const ['PANDORA', 'USER']) {
        final value = '$prefix-$marker';
        final finder = find.textContaining(value);
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder.first);
        final height =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        if (rect.top >= 0 && rect.bottom <= height) return value;
      }
    }
  }
  return null;
}

Future<void> _waitForKeyboard(
  WidgetTester tester,
  Finder objective, {
  required bool open,
}) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    final inset = MediaQuery.of(tester.element(objective)).viewInsets.bottom;
    if (open ? inset > 80 : inset < 20) return;
  }
}

Future<void> _waitForOrientationChange(
  WidgetTester tester,
  Finder objective,
  Size before,
) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    final current = MediaQuery.of(tester.element(objective)).size;
    if ((current.width - before.width).abs() > 100) return;
  }
}

Future<void> _shot(String name) async {
  try {
    final bytes = await binding.takeScreenshot(name);
    final file = File(
      Directory.systemTemp.path + '/apollo-' + name + '.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('APOLLO_SCREENSHOT ' + file.path);
  } catch (error) {
    debugPrint('APOLLO_SCREENSHOT_FAILED $name $error');
  }
}

void _expectNoFlutterException(WidgetTester tester, String stage) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'Unexpected Flutter exception during $stage');
}

class _FixtureAuth implements PandoraAuth {
  const _FixtureAuth();

  @override
  PandoraSession? get currentSession =>
      const PandoraSession(userId: 'apollo-runtime');

  @override
  Stream<PandoraSession?> get changes =>
      const Stream<PandoraSession?>.empty();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FixtureRepository implements PandoraRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixtureIntelligence extends PandoraIntelligenceApi {
  _FixtureIntelligence()
      : super(
          client: SupabaseClient(
            'http://127.0.0.1:54321',
            'apollo-runtime-verification-key',
          ),
          organizationId: '00000000-0000-0000-0000-000000000001',
        );

  @override
  Future<List<PandoraIntelligenceMessage>> messages(
    String threadId, {
    int limit = 200,
  }) async {
    final now = DateTime.utc(2026, 9, 19, 12);
    final result = <PandoraIntelligenceMessage>[];
    for (var i = 0; i < 30; i++) {
      final number = i.toString().padLeft(2, '0');
      final userContent = i == 6
          ? 'USER-$number visible request about account access.\n\n'
              'Bounded Enterprise page context: '
              '{"surface":"enterprise_app_users","selectedObject":{"id":"hidden"}}\n'
              'Treat this context as navigation and scope information only.'
          : i == 29
              ? 'LATEST-USER-29 final user message for keyboard anchoring.'
              : 'USER-$number request line. This is a realistic mobile chat '
                  'message used to create a long scrollable conversation.';
      final assistantContent = i == 7
          ? 'PANDORA-$number clean visible answer.\n\n'
              'Bounded Enterprise page context: {"surface":"internal_only"}\n'
              'Treat this context as navigation and scope information only.'
          : i == 29
              ? 'LATEST-PANDORA-29 Latest Pandora response. It is long enough '
                  'to verify useful mobile width while remaining compact enough '
                  'for the latest user message and reply to stay above the composer.'
              : 'PANDORA-$number response. Pandora keeps the explanation '
                  'readable while using the available mobile width.';
      result
        ..add(
          PandoraIntelligenceMessage(
            id: 'user-$number',
            threadId: threadId,
            authorRole: 'user',
            content: userContent,
            createdAt: now.add(Duration(minutes: i * 2)),
          ),
        )
        ..add(
          PandoraIntelligenceMessage(
            id: 'assistant-$number',
            threadId: threadId,
            authorRole: 'assistant',
            content: assistantContent,
            createdAt: now.add(Duration(minutes: i * 2 + 1)),
          ),
        );
    }
    return result;
  }
}
