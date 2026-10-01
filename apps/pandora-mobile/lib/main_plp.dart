import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_runtime_bootstrap.dart';
import 'app/plp_enterprise_app.dart';
import 'core/local/pandora_local_store.dart';
import 'core/security/mobile_auth_storage.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Remove the historical SharedPreferences token if an older PLP build left
  // one behind. The active session below is stored only in secure storage.
  await PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );

  final localStore = await openPandoraLocalStore();
  await localStore.purgeExpired(DateTime.now().toUtc());

  final secureAuthStorage = PandoraSecureSupabaseSessionStorage(
    persistSessionKey: PandoraMobileAuthStorage.secureSessionKey(
      PandoraConfig.supabaseUrl,
    ),
  );

  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: secureAuthStorage,
      autoRefreshToken: true,
      persistSession: true,
    ),
  );

  final runtime = PandoraRuntimeBootstrap.create(
    Supabase.instance.client,
    localStore: localStore,
  );

  runApp(PlpEnterpriseApp(runtime: runtime));
}
