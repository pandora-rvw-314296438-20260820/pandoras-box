import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/domain_registrar_api.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/data/pandora_repository.dart';
import '../core/data/project_experience_api.dart';
import '../core/data/project_runtime_api.dart';
import '../core/data/remote_pandora_repository.dart';
import '../core/diagnostics/diagnostic_event.dart';
import '../core/diagnostics/diagnostics_store.dart';
import '../core/network/pandora_api_client.dart';
import '../core/network/session_token_provider.dart';
import '../core/security/pandora_auth.dart';
import '../core/widgets/pandora_error_boundary.dart';
import '../pandora_config.dart';

class PandoraRuntimeBootstrap {
  const PandoraRuntimeBootstrap._({
    required this.auth,
    required this.repository,
    required this.intelligence,
    required this.projectRuntime,
    required this.projectExperience,
    required this.domainRegistrar,
    required this.diagnostics,
  });

  final PandoraAuth auth;
  final PandoraRepository repository;
  final PandoraIntelligenceApi intelligence;
  final ProjectRuntimeApi projectRuntime;
  final ProjectExperienceApi projectExperience;
  final DomainRegistrarApi domainRegistrar;
  final DiagnosticsStore diagnostics;

  static PandoraRuntimeBootstrap create(SupabaseClient supabase) {
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
    final ownerClient = PandoraApiClient(
      baseUri: Uri.parse(PandoraConfig.ownerApiBaseUrl),
      organizationId: PandoraConfig.organizationId,
      sessionTokenProvider: tokenProvider,
      diagnostics: diagnostics,
    );
    final runtimeClient = PandoraApiClient(
      baseUri: Uri.parse(PandoraConfig.projectRuntimeApiBaseUrl),
      organizationId: PandoraConfig.organizationId,
      sessionTokenProvider: tokenProvider,
      diagnostics: diagnostics,
      timeout: const Duration(seconds: 60),
    );

    return PandoraRuntimeBootstrap._(
      auth: SupabasePandoraAuth(supabase),
      repository: RemotePandoraRepository(client: ownerClient),
      intelligence: PandoraIntelligenceApi(
        client: supabase,
        organizationId: PandoraConfig.organizationId,
      ),
      projectRuntime: ProjectRuntimeApi(client: runtimeClient),
      projectExperience: ProjectExperienceApi(
        client: supabase,
        organizationId: PandoraConfig.organizationId,
      ),
      domainRegistrar: DomainRegistrarApi(
        client: supabase,
        organizationId: PandoraConfig.organizationId,
      ),
      diagnostics: diagnostics,
    );
  }
}
