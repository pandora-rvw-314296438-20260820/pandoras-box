import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _FakeModelCatalog extends PandoraIntelligenceApi {
  _FakeModelCatalog()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: 'org-fixture',
        );

  @override
  Future<List<PandoraModelOption>> modelCatalog() async =>
      const <PandoraModelOption>[
        PandoraModelOption(
          provider: 'auto',
          model: 'auto',
          label: 'Auto',
          available: true,
          state: 'ready',
          local: false,
          isDefault: true,
        ),
        PandoraModelOption(
          provider: 'gemini',
          model: 'gemini-3.5-flash-lite',
          label: 'Gemini 3.5 Flash Lite',
          available: true,
          state: 'ready',
          local: false,
          isDefault: false,
        ),
        PandoraModelOption(
          provider: 'gemini',
          model: 'gemini-3.7-flash',
          label: 'Gemini 3.7 Flash',
          available: true,
          state: 'ready',
          local: false,
          isDefault: true,
        ),
        PandoraModelOption(
          provider: 'gemini',
          model: 'gemini-3.1-pro-preview',
          label: 'Gemini 3.1 Pro Preview',
          available: true,
          state: 'ready',
          local: false,
          isDefault: false,
        ),
        PandoraModelOption(
          provider: 'openai',
          model: 'gpt-5.6-terra',
          label: 'GPT-5.6 Terra',
          available: true,
          state: 'ready',
          local: false,
          isDefault: true,
        ),
        PandoraModelOption(
          provider: 'openai',
          model: 'gpt-5.6-luna',
          label: 'GPT-5.6 Luna',
          available: true,
          state: 'ready',
          local: false,
          isDefault: false,
        ),
        PandoraModelOption(
          provider: 'openai',
          model: 'gpt-5.6-sol',
          label: 'GPT-5.6 Sol',
          available: true,
          state: 'ready',
          local: false,
          isDefault: false,
        ),
        PandoraModelOption(
          provider: 'kimi',
          model: 'kimi-k3',
          label: 'Kimi K3',
          available: true,
          state: 'ready',
          local: false,
          isDefault: true,
        ),
        PandoraModelOption(
          provider: 'local',
          model: 'Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M',
          label: 'Qwen2.5 7B Local',
          available: true,
          state: 'ready',
          local: true,
          isDefault: true,
        ),
      ];
}

void main() {
  testWidgets('composer exposes verified Models and removes Characters',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));

    await tester.pumpWidget(
      testApp(
        themeMode: ThemeMode.dark,
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          intelligence: _FakeModelCatalog(),
          diagnostics: DiagnosticsStore(),
          child: const AskPandoraScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ask-pandora-menu-characters')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-menu-models')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-menu-models')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Models'), findsOneWidget);
    final catalogLabels = <String>[
      'Auto',
      'Gemini 3.5 Flash Lite',
      'Gemini 3.7 Flash',
      'Gemini 3.1 Pro Preview',
      'GPT-5.6 Luna',
      'GPT-5.6 Sol',
      'GPT-5.6 Terra',
      'Kimi K3',
      'Qwen2.5 7B Local',
    ];
    final modelScroll = find.byType(Scrollable).last;
    for (final label in catalogLabels) {
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: modelScroll,
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Qwen2.5 7B Local'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ask-pandora-model-context')),
      findsOneWidget,
    );
    expect(find.text('Model · Qwen2.5 7B Local'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
