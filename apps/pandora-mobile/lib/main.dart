import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_app.dart';
import 'app/pandora_runtime_bootstrap.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
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
