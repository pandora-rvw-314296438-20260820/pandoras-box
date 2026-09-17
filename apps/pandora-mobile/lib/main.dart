import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_app.dart';
import 'app/pandora_runtime_bootstrap.dart';
import 'core/local/pandora_local_store.dart';
import 'core/security/mobile_auth_storage.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Start independent I/O concurrently so encrypted local storage, legacy
  // session cleanup, and the memory-only Supabase client do not serialize app
  // startup. Provider master credentials remain server/Vault-only.
  final legacySessionCleanup =
      PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );
  final localStoreFuture = openPandoraLocalStore();
  final supabaseInitialization = Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
    ),
  );

  final localStore = await localStoreFuture;
  await legacySessionCleanup;
  await supabaseInitialization;

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

  // Cache reads already reject/delete expired records individually. A full
  // expiry sweep is maintenance work, so keep it off the first-frame path.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      localStore.purgeExpired(DateTime.now().toUtc()).catchError((_) => 0),
    );
  });
}
