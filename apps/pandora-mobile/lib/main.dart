import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_app.dart';
import 'app/pandora_runtime_bootstrap.dart';
import 'core/local/pandora_local_store.dart';
import 'core/security/mobile_auth_storage.dart';
import 'core/security/pandora_session_storage.dart';
import 'pandora_config.dart';

final RegExp _pandoraClickIdPattern = RegExp(r'^pdc_[0-9a-f]{32}
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_captureLandingAttribution());
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Android sessions remain memory-only; web OAuth survives same-tab redirects.
  // Provider credentials stay server-side. The client gets a user session.
  await PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );

  final localStore = await openPandoraLocalStore();
  await localStore.purgeExpired(DateTime.now().toUtc());

  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: pandoraAuthClientOptions(),
  );

  final runtime = PandoraRuntimeBootstrap.create(
    Supabase.instance.client,
    localStore: localStore,
  );
  runApp(
    PandoraApp(
      auth: runtime.auth,
      repository: runtime.repository,
      activityHistory: runtime.activityHistory,
      intelligence: runtime.intelligence,
      projectRuntime: runtime.projectRuntime,
      projectExperience: runtime.projectExperience,
      projectExperienceProjection: runtime.projectExperienceProjection,
      projectExperienceRepository: runtime.projectExperienceRepository,
      domainRegistrar: runtime.domainRegistrar,
      diagnostics: runtime.diagnostics,
      localStore: runtime.localStore,
    ),
  );
}
);

Future<void> _captureLandingAttribution() async {
  final clickId = Uri.base.queryParameters['pcid'];
  if (clickId == null || !_pandoraClickIdPattern.hasMatch(clickId)) return;

  try {
    await http
        .post(
          Uri.base.resolve('/api/tracking/event'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'click_id': clickId,
            'event_name': 'landing.viewed',
            'event_type': 'event',
            'schema_version': 1,
            'consent': const {'analytics': false, 'marketing': false},
            'metadata': const <String, Object?>{},
          }),
        )
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    // Attribution must never block app startup. The redirect click remains
    // durable even when the optional landing event cannot be delivered.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Android sessions remain memory-only; web OAuth survives same-tab redirects.
  // Provider credentials stay server-side. The client gets a user session.
  await PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );

  final localStore = await openPandoraLocalStore();
  await localStore.purgeExpired(DateTime.now().toUtc());

  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: pandoraAuthClientOptions(),
  );

  final runtime = PandoraRuntimeBootstrap.create(
    Supabase.instance.client,
    localStore: localStore,
  );
  runApp(
    PandoraApp(
      auth: runtime.auth,
      repository: runtime.repository,
      activityHistory: runtime.activityHistory,
      intelligence: runtime.intelligence,
      projectRuntime: runtime.projectRuntime,
      projectExperience: runtime.projectExperience,
      projectExperienceProjection: runtime.projectExperienceProjection,
      projectExperienceRepository: runtime.projectExperienceRepository,
      domainRegistrar: runtime.domainRegistrar,
      diagnostics: runtime.diagnostics,
      localStore: runtime.localStore,
    ),
  );
}
