import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_presentation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drawer waits for actual IME dismissal and supersedes pending picker',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);

    presentation.reportKeyboardInset(312);
    final picker = presentation.showPicker();
    expect(presentation.value.surface, PandoraChatSurface.none);
    expect(presentation.value.pendingSurface, PandoraChatSurface.picker);
    presentation.reportKeyboardInset(140);
    expect(presentation.value.surface, PandoraChatSurface.none);

    final drawer = presentation.showDrawer();
    expect(await picker, isFalse);
    expect(presentation.value.pendingSurface, PandoraChatSurface.drawer);
    presentation.reportKeyboardInset(1);
    expect(presentation.value.surface, PandoraChatSurface.none);
    presentation.reportKeyboardInset(0);
    expect(await drawer, isTrue);
    expect(presentation.value.surface, PandoraChatSurface.drawer);
    expect(presentation.value.pendingSurface, isNull);
    expect(presentation.value.keyboardVisible, isFalse);
  });

  test('a late keyboard frame withholds an already requested overlay',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);

    expect(await presentation.showPicker(), isTrue);
    presentation.reportKeyboardInset(240);
    expect(presentation.value.surface, PandoraChatSurface.none);
    expect(presentation.value.pendingSurface, PandoraChatSurface.picker);
    presentation.reportKeyboardInset(0);
    expect(presentation.value.surface, PandoraChatSurface.picker);
    expect(presentation.value.pendingSurface, isNull);
  });

  test('Back cancels pending presentation without later resurrecting it',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    presentation.reportKeyboardInset(280);
    final pending = presentation.showDrawer();
    expect(presentation.handleBack(), isTrue);
    expect(await pending, isFalse);
    presentation.reportKeyboardInset(0);
    expect(presentation.value.surface, PandoraChatSurface.none);
    expect(presentation.value.pendingSurface, isNull);
    expect(presentation.handleBack(), isFalse);
  });

  test('repeated open is one transition and external drawer close is coherent',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    presentation.reportKeyboardInset(240);
    final first = presentation.showDrawer();
    final repeated = presentation.showDrawer();
    expect(identical(first, repeated), isTrue);
    presentation.reportKeyboardInset(0);
    expect(await first, isTrue);
    presentation.reportDrawer(false);
    expect(presentation.value.surface, PandoraChatSurface.none);
    expect(await presentation.showPicker(), isTrue);
    presentation.reportDrawer(false);
    expect(presentation.value.surface, PandoraChatSurface.picker);
  });

  test('drawer kind supersedes pending kind and rejects its departing callback',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    presentation.reportKeyboardInset(240);
    final primary = presentation.showDrawer();
    final oldIntent = presentation.value.intentRevision;
    final recent = presentation.showDrawer(kind: PandoraChatDrawerKind.recent);
    expect(await primary, isFalse);
    presentation.reportKeyboardInset(0);
    expect(await recent, isTrue);
    expect(presentation.value.drawerKind, PandoraChatDrawerKind.recent);
    presentation.reportDrawer(false,
        kind: PandoraChatDrawerKind.primary, expectedIntent: oldIntent);
    expect(presentation.value.surface, PandoraChatSurface.drawer);
    final recentIntent = presentation.value.intentRevision;
    presentation.reportLayout(
        viewportSize: const Size(390, 844), composerExtent: 66);
    expect(presentation.value.intentRevision, recentIntent);
    presentation.reportDrawer(false,
        kind: PandoraChatDrawerKind.recent, expectedIntent: recentIntent);
    expect(presentation.value.surface, PandoraChatSurface.none);
  });

  test('each context request has its own intent and supersedes older loading',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    presentation.reportKeyboardInset(240);
    final first = presentation.showContext();
    final firstIntent = presentation.value.intentRevision;
    final second = presentation.showContext();
    expect(await first, isFalse);
    expect(presentation.value.intentRevision, greaterThan(firstIntent));
    presentation.reportKeyboardInset(0);
    expect(await second, isTrue);
    expect(presentation.value.surface, PandoraChatSurface.context);
    final secondIntent = presentation.value.intentRevision;
    expect(await presentation.showContext(), isTrue);
    expect(presentation.value.intentRevision, greaterThan(secondIntent));
    expect(presentation.handleBack(), isTrue);
    expect(presentation.value.surface, PandoraChatSurface.none);
  });

  test('an open context route may own a keyboard without losing its intent',
      () async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    expect(await presentation.showContext(), isTrue);
    final contextIntent = presentation.value.intentRevision;
    presentation.reportKeyboardInset(280);
    expect(presentation.value.surface, PandoraChatSurface.context);
    expect(presentation.value.pendingSurface, isNull);
    expect(presentation.value.intentRevision, contextIntent);
    final drawer = presentation.showDrawer();
    expect(presentation.value.pendingSurface, PandoraChatSurface.drawer);
    expect(presentation.value.surface, PandoraChatSurface.none);
    presentation.reportKeyboardInset(0);
    expect(await drawer, isTrue);
    expect(presentation.value.surface, PandoraChatSurface.drawer);
  });

  testWidgets('focus boundaries publish before IME without changing intent',
      (tester) async {
    final focus = FocusNode();
    final presentation =
        PandoraChatPresentationController(composerFocus: focus);
    addTearDown(presentation.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(focusNode: focus)),
    ));
    final initialRevision = presentation.value.revision;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(presentation.value.keyboardVisible, isFalse);
    expect(presentation.value.revision, greaterThan(initialRevision));
    expect(presentation.value.intentRevision, 0);
    final focusedRevision = presentation.value.revision;
    expect(presentation.handleBack(), isTrue);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(presentation.value.revision, greaterThan(focusedRevision));
    expect(presentation.value.intentRevision, 0);
    expect(presentation.handleBack(), isFalse);
  });
}
