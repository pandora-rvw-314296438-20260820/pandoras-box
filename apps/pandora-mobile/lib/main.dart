import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_app.dart';
import 'app/pandora_runtime_bootstrap.dart';
import 'core/security/mobile_auth_storage.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // supabase_flutter 2.15.4 persists sessions in SharedPreferences unless a
  // LocalStorage is supplied. Purge that legacy session before switching this
  // owner-test build to memory-only auth. Provider master credentials remain
  // server/Vault-only; the APK receives only the scoped user session.
  await PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );
  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
    ),
  );

  final runtime = PandoraRuntimeBootstrap.create(Supabase.instance.client);
  runApp(
    PandoraApp(
      auth: runtime.auth,
      repository: runtime.repository,
      intelligence: runtime.intelligence,
      projectRuntime: runtime.projectRuntime,
      projectExperience: runtime.projectExperience,
      projectExperienceProjection: runtime.projectExperienceProjection,
      projectExperienceRepository: runtime.projectExperienceRepository,
      domainRegistrar: runtime.domainRegistrar,
      diagnostics: runtime.diagnostics,
    ),
  );
}
