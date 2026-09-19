
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String shell;
  late String screen;
  late String repository;
  late String adapter;
  late String stub;
  late String webEmbed;
  late String androidHost;
  late String migration;
  late String chat;

  setUpAll(() {
    shell = File('lib/app/pandora_chat_shell.dart').readAsStringSync();
    screen = File(
      'lib/features/enterprise/enterprise_vision_screen.dart',
    ).readAsStringSync();
    repository = File(
      'lib/core/data/enterprise_vision_repository.dart',
    ).readAsStringSync();
    adapter = File(
      'lib/features/enterprise/enterprise_vision_embed.dart',
    ).readAsStringSync();
    stub = File(
      'lib/features/enterprise/enterprise_vision_embed_stub.dart',
    ).readAsStringSync();
    webEmbed = File(
      'lib/features/enterprise/enterprise_vision_embed_web.dart',
    ).readAsStringSync();
    androidHost = File(
      'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/MainActivity.kt',
    ).readAsStringSync();
    migration = File(
      '../../supabase/migrations/20260919071500_enterprise_vision_intelligence_v1.sql',
    ).readAsStringSync();
    chat = File(
      '../../supabase/functions/pandora-intelligence-chat/index.ts',
    ).readAsStringSync();
  });

  test('shell exposes Vision Intelligence with real Vision context', () {
    expect(shell, contains("'Vision Intelligence'"));
    expect(shell, contains("10 => 'vision_intelligence'"));
    expect(shell, contains('10 => EnterpriseVisionScreen('));
    expect(shell, contains("'surface': 'enterprise_vision'"));
    expect(shell, contains("'vision.read'"));
    expect(shell, contains("'vision.alert.manage'"));
    expect(shell, contains("'vision.clip.request'"));
    expect(shell, contains('initialPrompt: _pendingChatPrompt'));
  });

  test('provider-controlled Kabukicho feed remains stable visual source', () {
    expect(
      webEmbed,
      contains(
        'https://camstreamer.com/embed/VSnOa4OubclxMcFKpTws6Yv7U2rt0VbMfcrHomkq?rel=0',
      ),
    );
    expect(webEmbed, contains('allowfullscreen'));
    expect(webEmbed, contains('strict-origin-when-cross-origin'));
    expect(webEmbed, isNot(contains('youtube.com/embed/')));
    expect(screen, contains('LIVE KABUKICHO'));
    expect(screen, contains('Kabukicho · Shinjuku, Tokyo'));
  });

  test('Android uses native WebView platform view for live feed', () {
    expect(
      adapter,
      contains("if (dart.library.html) 'enterprise_vision_embed_web.dart'"),
    );
    expect(stub, contains('Platform.isAndroid'));
    expect(stub, contains('AndroidView'));
    expect(stub, contains('pandora/camstreamer_kabukicho'));
    expect(androidHost, contains('PandoraCamStreamerViewFactory'));
    expect(androidHost, contains('pandora/camstreamer_kabukicho'));
  });

  test('public feed is never represented as analyzed enterprise evidence', () {
    expect(screen, contains('Public third-party feeds remain display-only.'));
    expect(screen, contains('Public-feed analysis'));
    expect(screen, contains("value: 'Off'"));
    expect(screen, contains('does not analyze or retain this public source'));
    expect(screen.toLowerCase(), isNot(contains('public vision demo')));
  });

  test('Vision UI reads real cameras events alerts and exposes actions', () {
    expect(repository, contains('pandora_vision_overview_v1'));
    expect(screen, contains("'Authorized cameras'"));
    expect(screen, contains("'Recent events'"));
    expect(screen, contains("'Alerts'"));
    expect(screen, contains("'What is happening now?'"));
    expect(screen, contains("'Count people'"));
    expect(screen, contains("'Count vehicles'"));
    expect(screen, contains("'Crowding trend'"));
    expect(screen, contains("'Incident report'"));
    expect(screen, contains("'Restricted-area alert'"));
    expect(screen, contains("'Save last 10 minutes'"));
  });

  test('Vision data plane preserves machine-versus-human evidence state', () {
    for (final table in <String>[
      'enterprise_vision_cameras',
      'enterprise_vision_zones',
      'enterprise_vision_rules',
      'enterprise_vision_analysis_runs',
      'enterprise_vision_observations',
      'enterprise_vision_events',
      'enterprise_vision_alerts',
      'enterprise_vision_clip_requests',
      'enterprise_vision_incidents',
    ]) {
      expect(migration, contains(table));
    }
    expect(migration, contains("check (human_state in ('machine','verified','rejected'))"));
    expect(migration, contains('pandora_vision_search_v1'));
    expect(migration, contains('pandora_vision_request_clip_v1'));
    expect(migration, contains('pandora_vision_verify_observation_v1'));
    expect(migration, contains('pandora_vision_ack_alert_v1'));
    expect(migration, contains('biometric_identification_enabled boolean not null default false'));
  });

  test('Ask Pandora retrieves Vision evidence and owns governed actions', () {
    expect(chat, contains('"enterprise_vision"'));
    expect(chat, contains('enterpriseVisionEvidenceContext'));
    expect(chat, contains('enterpriseVisionActionDispatch'));
    expect(chat, contains('enterpriseVisionAnalyzeAttachments'));
    expect(chat, contains('PUBLIC_FEED_ANALYSIS_DISABLED'));
    expect(chat, contains('pandora_vision_request_clip_v1'));
    expect(chat, contains('pandora_vision_verify_observation_v1'));
    expect(chat, contains('pandora_vision_ack_alert_v1'));
    expect(chat, contains('fight_or_physical_altercation'));
    expect(chat, contains('restricted_zone_entry'));
    expect(chat, contains('unattended_object'));
    expect(chat, contains('ocr_text'));
    expect(chat, contains('realPersonIdentification:false'));
  });
}
