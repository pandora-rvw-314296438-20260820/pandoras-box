import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/widgets/pandora_mark.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/fake_chat_intelligence.dart';
import '../helpers/test_app.dart';

const _surfaceKey = ValueKey<String>('lane-h-golden-surface');
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
  for (var depth = 0; depth < 12; depth += 1) {
    roots.add(cursor.path);
    final parent = cursor.parent;
    if (parent.path == cursor.path) break;
    cursor = parent;
  }

  File? textFont;
  File? iconFont;
  for (final root in roots) {
    final materialFonts = root +
        separator +
        'bin' +
        separator +
        'cache' +
        separator +
        'artifacts' +
        separator +
        'material_fonts';
    final textCandidate =
        File(materialFonts + separator + 'Roboto-Regular.ttf');
    final iconCandidate =
        File(materialFonts + separator + 'MaterialIcons-Regular.otf');
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

  final textLoader = FontLoader(_fontFamily)
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await textFont.readAsBytes()),
      ),
    );
  final iconLoader = FontLoader(_iconFontFamily)
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await iconFont.readAsBytes()),
      ),
    );
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

List<PandoraChatModelOption> _pickerModels() {
  const names = <String>[
    'Mistral Large 3',
    'DeepSeek V3.2',
    'Kimi K2.5',
    'GLM 5',
    'Qwen3 VL 235B',
    'Nemotron 3 Super 120B',
    'MiniMax M2.5',
    'Kimi K2 Thinking',
    'Devstral 2 123B',
    'Qwen3 Next 80B',
    'Qwen3 Coder Next',
    'GLM 4.7',
    'MiniMax M2.1',
    'Magistral Small',
    'Gemma 3 27B',
    'Nemotron Nano 3 30B',
    'MiniMax M2',
    'Ministral 14B',
    'GLM 4.7 Flash',
    'Gemma 3 12B',
    'Nemotron Nano 12B VL',
    'Ministral 8B',
    'Nemotron Nano 9B',
    'Palmyra Vision 7B',
    'Gemma 3 4B',
    'Ministral 3B',
  ];
  return <PandoraChatModelOption>[
    for (var i = 0; i < names.length; i += 1)
      PandoraChatModelOption(
        routingProvider: 'bedrock',
        providerName: 'Verified',
        modelId: 'fixture.model.' + i.toString(),
        modelName: names[i],
        selectable: true,
        availability: 'available',
      ),
    for (var i = 0; i < 48; i += 1)
      PandoraChatModelOption(
        routingProvider: 'bedrock',
        providerName: 'Unavailable',
        modelId: 'fixture.locked.' + i.toString(),
        modelName: 'Unavailable ' + i.toString(),
        selectable: false,
        availability: 'unavailable',
      ),
  ];
}

PandoraChatModelPickerSnapshot _snapshot() => PandoraChatModelPickerSnapshot(
      models: _pickerModels(),
      selection: const PandoraChatModelSelection.auto(),
      reasoningMode: PandoraIntelligenceMode.auto,
    );

Future<void> _pumpVisualFrames(WidgetTester tester) async {
  for (final duration in <Duration>[
    Duration.zero,
    Duration(milliseconds: 50),
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
  ]) {
    await tester.pump(duration);
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

Future<void> _mount(
  WidgetTester tester, {
  PandoraIntelligenceApi? intelligence,
}) async {
  await setTestSurface(tester, logicalSize: _phoneSize);
  await tester.pumpWidget(
    PandoraDependencies(
      auth: const FakeAuth(),
      repository: FakeRepository(),
      intelligence: intelligence ?? FakeChatIntelligence(),
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
}

Future<({int width, int height, Uint8List pixels})> _decodePng(
  Uint8List png,
) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('PNG could not be decoded.');
      return (
        width: image.width,
        height: image.height,
        pixels: Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<void> _expectBelowFloatingChromeMatchesBaseline(
  Uint8List actualPng,
  File baseline, {
  int chromeRows = 72,
}) async {
  final actual = await _decodePng(actualPng);
  final expected = await _decodePng(baseline.readAsBytesSync());
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  final firstComparedByte =
      chromeRows.clamp(0, actual.height) * actual.width * 4;
  var mismatchedBytes = 0;
  for (var i = firstComparedByte; i < actual.pixels.length; i += 1) {
    if (actual.pixels[i] != expected.pixels[i]) mismatchedBytes += 1;
  }
  expect(
    mismatchedBytes,
    0,
    reason:
        'The approved floating top chrome may differ, but content below it must remain pixel-identical.',
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _pumpVisualFrames(tester);
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
  final output = File('build/lane-h-goldens/' + name + '.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes!);
  expect(output.lengthSync(), greaterThan(0));

  final baseline = File('test/goldens/owner_screens/' + name + '.png');
  if (baseline.existsSync() && !Platform.isWindows) {
    await _expectBelowFloatingChromeMatchesBaseline(bytes, baseline);
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('captures lane_h_landing_resting_390x844', (tester) async {
    await _mount(tester);
    await _capture(tester, 'lane_h_landing_resting_390x844');
  });

  testWidgets('captures lane_h_keyboard_open_390x844', (tester) async {
    await _mount(tester);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await _capture(tester, 'lane_h_keyboard_open_390x844');
  });

  // Keep the reviewed asset path stable. A real pending greeting has a busy
  // composer; the live routing policy deliberately omits Thinking and Activity
  // for trivial conversation, even while its scoped response is pending.
  testWidgets('captures pending greeting without fabricated Activity',
      (tester) async {
    final pending = Completer<PandoraIntelligenceTurn>();
    final activity = StreamController<Map<String, dynamic>>();
    final intelligence = FakeChatIntelligence(
        onReply: (_) => pending.future, events: activity.stream);
    await _mount(tester, intelligence: intelligence);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.tap(objective);
    await tester.enterText(objective, 'Hello');
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    await tester.pump();
    expect(intelligence.lastMessage, 'Hello');
    expect(intelligence.lastEnterpriseContext?['selectedObject'],
        containsPair('coreMode', 'owner'));
    await _capture(tester, 'lane_h_after_send_thinking_390x844');
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Ready.'), findsNothing);
    expect(find.text('Thinking through the request…'), findsNothing);
    expect(find.byKey(const ValueKey('ask-pandora-activity-theatre')),
        findsNothing);
    pending.complete(const PandoraIntelligenceTurn(
        threadId: 'lane-h-golden',
        reply: 'Ready.',
        intent: 'conversation',
        confidence: 1,
        needsClarification: false));
    await tester.pumpAndSettle();
    await activity.close();
  });

  testWidgets('captures lane_h_picker_open_390x844', (tester) async {
    await _mount(tester);
    tester
        .state<AskPandoraScreenState>(find.byType(AskPandoraScreen))
        .debugShowModelPicker(_snapshot());
    await _capture(tester, 'lane_h_picker_open_390x844');
  });

  testWidgets('captures lane_h_picker_end_390x844', (tester) async {
    await _mount(tester);
    tester
        .state<AskPandoraScreenState>(find.byType(AskPandoraScreen))
        .debugShowModelPicker(_snapshot(), startAtEnd: true);
    await _capture(tester, 'lane_h_picker_end_390x844');
  });

  testWidgets('captures lane_h_non_auto_tag_390x844', (tester) async {
    await _mount(tester);
    tester
        .state<AskPandoraScreenState>(find.byType(AskPandoraScreen))
        .debugSetModelSelection(
          const PandoraChatModelSelection.manual(
            provider: 'bedrock',
            model: 'fixture.model.24',
          ),
          'Gemma 3 4B',
        );
    await _capture(tester, 'lane_h_non_auto_tag_390x844');
  });
}
