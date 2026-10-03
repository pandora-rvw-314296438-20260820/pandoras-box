import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_viewport.dart';

class _ViewportHarness extends StatefulWidget {
  const _ViewportHarness({super.key, required this.controller});

  final PandoraChatViewportController controller;

  @override
  State<_ViewportHarness> createState() => _ViewportHarnessState();
}

class _ViewportHarnessState extends State<_ViewportHarness> {
  double height = 500;
  double bottom = 24;
  int revision = 0;
  String thread = 'thread-a';
  bool attached = true;
  final Map<String, double> extents = {
    for (var i = 0; i < 40; i++) 'turn-$i': 72,
  };

  void change(VoidCallback update) => setState(() {
        update();
        revision += 1;
      });

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 360,
          height: height,
          child: attached
              ? PandoraChatViewport(
                  threadIdentity: thread,
                  revision: revision,
                  controller: widget.controller,
                  padding: EdgeInsets.fromLTRB(12, 24, 12, bottom),
                  items: [
                    for (final entry in extents.entries)
                      PandoraChatViewportItem(
                        id: entry.key,
                        child: SizedBox(
                          key: ValueKey('content-${entry.key}'),
                          height: entry.value,
                          child: Text('${entry.key}\nConversational content'),
                        ),
                      ),
                  ],
                )
              : const SizedBox.expand(),
        ),
      );
}

void main() {
  late PandoraChatViewportController controller;
  late GlobalKey<_ViewportHarnessState> harness;

  setUp(() {
    controller = PandoraChatViewportController();
    harness = GlobalKey<_ViewportHarnessState>();
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _ViewportHarness(key: harness, controller: controller),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<PandoraChatReadingAnchor> reviewHistory(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 380));
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    expect(controller.anchor, isNotNull);
    return controller.anchor!;
  }

  Finder content(String id) => find.byKey(ValueKey('content-$id'));

  testWidgets('token growth without another row retains the latest anchor',
      (tester) async {
    await mount(tester);
    expect(controller.followingLatest, isTrue);
    expect(tester.getRect(content('turn-39')).bottom, closeTo(476, 1));
    harness.currentState!
        .change(() => harness.currentState!.extents['turn-39'] = 260);
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isTrue);
    expect(tester.getRect(content('turn-39')).bottom, closeTo(476, 1));
    expect(find.byKey(const ValueKey('pandora-chat-latest')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history message and offset survive IME and composer resizing',
      (tester) async {
    await mount(tester);
    final anchor = await reviewHistory(tester);
    final before = tester.getRect(content(anchor.messageId)).top;
    harness.currentState!.change(() {
      harness.currentState!.height = 320;
      harness.currentState!.bottom = 80;
      harness.currentState!.extents['turn-39'] = 270;
    });
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    expect(tester.getRect(content(anchor.messageId)).top, closeTo(before, 1));
    harness.currentState!.change(() {
      harness.currentState!.height = 500;
      harness.currentState!.bottom = 24;
    });
    await tester.pumpAndSettle();
    expect(tester.getRect(content(anchor.messageId)).top, closeTo(before, 1));
    expect(controller.hasNewContent, isTrue);
    expect(find.byKey(const ValueKey('pandora-chat-latest')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a prior failure does not move an unrelated history row',
      (tester) async {
    await mount(tester);
    final anchor = await reviewHistory(tester);
    final before = tester.getRect(content(anchor.messageId)).top;
    final anchorIndex = int.parse(anchor.messageId.split('-').last);
    expect(anchorIndex, greaterThan(1));
    harness.currentState!.change(
        () => harness.currentState!.extents.remove('turn-${anchorIndex - 1}'));
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    expect(tester.getRect(content(anchor.messageId)).top, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new gesture fences a previously scheduled latest correction',
      (tester) async {
    await mount(tester);
    await reviewHistory(tester);
    final scrollable = find.byType(ListView);
    controller.returnToLatest(); // Intentionally no pump before the gesture.
    final gesture = await tester.startGesture(tester.getCenter(scrollable));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    expect(content('turn-39').hitTestable(), findsNothing);
    expect(controller.anchor, isNotNull);
  });

  testWidgets(
      'explicit Latest returns after new content arrives during history',
      (tester) async {
    await mount(tester);
    await reviewHistory(tester);
    harness.currentState!
        .change(() => harness.currentState!.extents['turn-40'] = 360);
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    await tester.tap(find.byKey(const ValueKey('pandora-chat-latest')));
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isTrue);
    expect(controller.hasNewContent, isFalse);
    expect(tester.getRect(content('turn-40')).bottom, closeTo(476, 1));
  });

  testWidgets('retained controller restores reading after temporary detachment',
      (tester) async {
    await mount(tester);
    final anchor = await reviewHistory(tester);
    final before = tester.getRect(content(anchor.messageId)).top;
    harness.currentState!.change(() => harness.currentState!.attached = false);
    await tester.pumpAndSettle();
    harness.currentState!.change(() => harness.currentState!.attached = true);
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isFalse);
    expect(tester.getRect(content(anchor.messageId)).top, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching threads fences a queued prior-thread correction',
      (tester) async {
    await mount(tester);
    controller.returnToLatest();
    harness.currentState!.change(() {
      harness.currentState!.thread = 'thread-b';
      harness.currentState!.extents
        ..clear()
        ..addAll({for (var i = 0; i < 12; i++) 'new-$i': 80});
    });
    await tester.pumpAndSettle();
    expect(controller.followingLatest, isTrue);
    expect(content('turn-39'), findsNothing);
    expect(tester.getRect(content('new-11')).bottom, closeTo(476, 1));
    expect(tester.takeException(), isNull);
  });
}
