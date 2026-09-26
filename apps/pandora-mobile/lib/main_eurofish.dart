import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/eurofish_enterprise_app.dart';
import 'app/pandora_runtime_bootstrap.dart';
import 'core/local/pandora_local_store.dart';
import 'core/security/mobile_auth_storage.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await PandoraMobileAuthStorage.clearLegacyPersistedSession(
    PandoraConfig.supabaseUrl,
  );

  final localStore = await openPandoraLocalStore();
  await localStore.purgeExpired(DateTime.now().toUtc());

  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
    ),
  );

  final runtime = PandoraRuntimeBootstrap.create(
    Supabase.instance.client,
    localStore: localStore,
  );

  runApp(EurofishEnterpriseApp(runtime: runtime));
}
