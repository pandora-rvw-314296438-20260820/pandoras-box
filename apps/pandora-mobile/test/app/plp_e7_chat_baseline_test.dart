import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_chat_intelligence.dart';
import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('PLP chat preserves exact e7c2dc08 visible baseline',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(
      testApp(
        themeMode: ThemeMode.dark,
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          intelligence: FakeChatIntelligence(),
          diagnostics: DiagnosticsStore(),
          child: const AskPandoraScreen(
            enterpriseContext: <String, Object?>{
              'organization': <String, Object?>{
                'propertySlug': 'plp-boracay',
              },
            },
            allowCharacterContext: false,
            allowProjectContext: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('plp-e7-chat-surface')),
      findsOneWidget,
    );
    expect(find.text('What can I help with?'), findsOneWidget);
    expect(find.text('Message Pandora'), findsOneWidget);

    final cube = find.byKey(const ValueKey<String>('ask-pandora-plus'));
    final voice = find.byKey(const ValueKey<String>('ask-pandora-voice'));
    final action = find.byKey(const ValueKey<String>('ask-pandora-submit'));

    expect(cube, findsOneWidget);
    expect(
      find.descendant(
        of: cube,
        matching: find.byIcon(Icons.view_in_ar_outlined),
      ),
      findsOneWidget,
    );
    expect(voice, findsOneWidget);
    expect(
      find.descendant(
        of: voice,
        matching: find.byIcon(Icons.mic_none_rounded),
      ),
      findsOneWidget,
    );
    expect(action, findsOneWidget);
    expect(
      find.descendant(
        of: action,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.send_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
