import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/pandora_app.dart';
import 'core/data/domain_registrar_api.dart';
import 'core/data/project_experience_api.dart';
import 'core/data/project_runtime_api.dart';
import 'core/data/remote_pandora_repository.dart';
import 'core/diagnostics/diagnostic_event.dart';
import 'core/diagnostics/diagnostics_store.dart';
import 'core/network/pandora_api_client.dart';
import 'core/network/session_token_provider.dart';
import 'core/security/pandora_auth.dart';
import 'core/widgets/pandora_error_boundary.dart';
import 'pandora_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Supabase.initialize(
    url: PandoraConfig.supabaseUrl,
    publishableKey: PandoraConfig.supabasePublishableKey,
  );

  final supabase = Supabase.instance.client;
  final diagnostics = DiagnosticsStore();

  installPandoraErrorHandling(
    record: (summary) => diagnostics.record(
      DiagnosticEvent(
        occurredAt: DateTime.now().toUtc(),
        operation: 'app.uncaughtError',
        method: 'APP',
        routeTemplate: 'app',
        outcome: DiagnosticOutcome.failed,
        duration: Duration.zero,
        errorCode: summary,
      ),
    ),
  );

  final tokenProvider = SupabaseSessionTokenProvider(supabase);
  final apiClient = PandoraApiClient(
    baseUri: Uri.parse(PandoraConfig.ownerApiBaseUrl),
    organizationId: PandoraConfig.organizationId,
    sessionTokenProvider: tokenProvider,
    diagnostics: diagnostics,
  );
  final projectRuntimeClient = PandoraApiClient(
    baseUri: Uri.parse(PandoraConfig.projectRuntimeApiBaseUrl),
    organizationId: PandoraConfig.organizationId,
    sessionTokenProvider: tokenProvider,
    diagnostics: diagnostics,
    timeout: const Duration(seconds: 60),
  );
  final repository = RemotePandoraRepository(client: apiClient);
  final projectRuntime = ProjectRuntimeApi(client: projectRuntimeClient);
  final projectExperience = ProjectExperienceApi(
    client: supabase,
    organizationId: PandoraConfig.organizationId,
  );
  final domainRegistrar = DomainRegistrarApi(
    client: supabase,
    organizationId: PandoraConfig.organizationId,
  );

  runApp(
    PandoraApp(
      auth: SupabasePandoraAuth(supabase),
      repository: repository,
      projectRuntime: projectRuntime,
      projectExperience: projectExperience,
      domainRegistrar: domainRegistrar,
      diagnostics: diagnostics,
    ),
  );
}
