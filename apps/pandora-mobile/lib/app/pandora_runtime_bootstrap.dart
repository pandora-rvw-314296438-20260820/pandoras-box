import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/domain_registrar_api.dart';
import '../core/data/pandora_activity_history_api.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/data/pandora_repository.dart';
import '../core/data/project_build_stream_cursor_store.dart';
import '../core/data/project_experience_api.dart';
import '../core/data/project_experience_projection_repository.dart';
import '../core/data/project_experience_repository.dart';
import '../core/data/project_runtime_api.dart';
import '../core/data/remote_pandora_repository.dart';
import '../core/diagnostics/diagnostic_event.dart';
import '../core/diagnostics/diagnostics_store.dart';
import '../core/local/pandora_local_store.dart';
import '../core/network/pandora_api_client.dart';
import '../core/network/session_token_provider.dart';
import '../core/security/pandora_auth.dart';
import '../core/widgets/pandora_error_boundary.dart';
import '../pandora_config.dart';

class PandoraRuntimeBootstrap {
  const PandoraRuntimeBootstrap._({
    required this.auth,
    required this.repository,
    required this.activityHistory,
    required this.intelligence,
    required this.projectRuntime,
    required this.projectExperience,
    required this.projectExperienceProjection,
    required this.projectExperienceRepository,
    required this.domainRegistrar,
    required this.diagnostics,
    required this.localStore,
  });

  final PandoraAuth auth;
  final PandoraRepository repository;
  final PandoraActivityHistorySource activityHistory;
  final PandoraIntelligenceApi intelligence;
  final ProjectRuntimeApi projectRuntime;
  final ProjectExperienceApi projectExperience;
  final ProjectExperienceProjectionRepository projectExperienceProjection;
  final ProjectExperienceRepository projectExperienceRepository;
  final DomainRegistrarApi domainRegistrar;
  final DiagnosticsStore diagnostics;
  final PandoraLocalStore localStore;

  static PandoraRuntimeBootstrap create(
    SupabaseClient supabase, {
    required PandoraLocalStore localStore,
    String? organizationId,
    bool installGlobalErrorHandling = true,
  }) {
    final resolvedOrganizationId =
        organizationId ?? PandoraConfig.organizationId;
    final diagnostics = DiagnosticsStore();
    if (installGlobalErrorHandling) {
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
    }

    final tokenProvider = SupabaseSessionTokenProvider(supabase);
    final ownerClient = PandoraApiClient(
      baseUri: Uri.parse(PandoraConfig.ownerApiBaseUrl),
      organizationId: resolvedOrganizationId,
      sessionTokenProvider: tokenProvider,
      diagnostics: diagnostics,
    );
    final runtimeClient = PandoraApiClient(
      baseUri: Uri.parse(PandoraConfig.projectRuntimeApiBaseUrl),
      organizationId: resolvedOrganizationId,
      sessionTokenProvider: tokenProvider,
      diagnostics: diagnostics,
      timeout: const Duration(seconds: 60),
    );

    final projectRuntime = ProjectRuntimeApi(client: runtimeClient);
    final projectExperience = ProjectExperienceApi(
      client: supabase,
      organizationId: resolvedOrganizationId,
      cursorStore: PandoraLocalProjectBuildStreamCursorStore(localStore),
    );
    final projectExperienceProjection =
        SupabaseProjectExperienceProjectionRepository(
      client: supabase,
      organizationId: resolvedOrganizationId,
    );
    final projectExperienceRepository = CompositeProjectExperienceRepository(
      projection: projectExperienceProjection,
      mutations: projectExperience,
      runtime: projectRuntime,
    );

    return PandoraRuntimeBootstrap._(
      auth: SupabasePandoraAuth(
        supabase,
        organizationId: resolvedOrganizationId,
      ),
      repository: RemotePandoraRepository(client: ownerClient),
      activityHistory: SupabasePandoraActivityHistorySource(
        client: supabase,
        organizationId: resolvedOrganizationId,
      ),
      intelligence: PandoraIntelligenceApi(
        client: supabase,
        organizationId: resolvedOrganizationId,
      ),
      projectRuntime: projectRuntime,
      projectExperience: projectExperience,
      projectExperienceProjection: projectExperienceProjection,
      projectExperienceRepository: projectExperienceRepository,
      domainRegistrar: DomainRegistrarApi(
        client: supabase,
        organizationId: resolvedOrganizationId,
      ),
      diagnostics: diagnostics,
      localStore: localStore,
    );
  }
}
