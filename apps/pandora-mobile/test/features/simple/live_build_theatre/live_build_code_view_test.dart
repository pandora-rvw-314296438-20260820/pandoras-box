import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_code_view.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_event.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_reducer.dart';

LiveBuildTheatreState stateWith({
  required List<LiveBuildEvent> events,
  bool historyGapDueToRetention = false,
}) {
  return const LiveBuildTheatreReducer().reduce(
    events,
    historyGapDueToRetention: historyGapDueToRetention,
  );
}

LiveBuildEvent event(
  int sequence,
  LiveBuildEventKind kind, {
  String? filePath,
  String? content,
}) {
  return LiveBuildEvent(
    streamId: 'stream-1',
    sequence: sequence,
    schemaVersion: 2,
    kind: kind,
    rawEventType: kind.name,
    safePayload: const <String, Object?>{},
    createdAt: DateTime.utc(2026, 9, 1, 6, 0, sequence),
    filePath: filePath,
    contentChunk: content,
  );
}

Widget app(LiveBuildTheatreState state) {
  return MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LiveBuildCodeView(state: state),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty code surface is impossible before real bytes arrive', (
    tester,
  ) async {
    final state = stateWith(
      events: <LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/main.dart'),
      ],
    );

    await tester.pumpWidget(app(state));

    expect(find.byKey(const Key('live-build-code-surface')), findsNothing);
    expect(find.text('lib/main.dart'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first real source bytes create readable code surface', (
    tester,
  ) async {
    final state = stateWith(
      events: <LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/main.dart'),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/main.dart',
          content: 'void main() {}',
        ),
      ],
    );

    await tester.pumpWidget(app(state));

    expect(find.byKey(const Key('live-build-code-surface')), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('DART'), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long filename and long line stay bounded without overflow', (
    tester,
  ) async {
    final file = 'lib/features/some/extremely/long/path/'
        'this_is_a_very_long_generated_file_name_for_mobile_layout.dart';
    final state = stateWith(
      events: <LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: file),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: file,
          content: List<String>.filled(400, 'x').join(),
        ),
      ],
    );

    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(state));

    expect(find.byKey(const Key('live-build-code-surface')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual vertical inspection exposes Return to live', (
    tester,
  ) async {
    final source = List<String>.generate(
      180,
      (index) => 'line $index',
    ).join('\n');
    final state = stateWith(
      events: <LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/main.dart'),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/main.dart',
          content: source,
        ),
      ],
    );

    await tester.pumpWidget(app(state));
    await tester.drag(
      find.byKey(const Key('live-build-code-scroll')),
      const Offset(0, -160),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-build-return-to-live')), findsOneWidget);

    await tester.tap(find.byKey(const Key('live-build-return-to-live')));
    await tester.pump();

    expect(find.byKey(const Key('live-build-return-to-live')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
