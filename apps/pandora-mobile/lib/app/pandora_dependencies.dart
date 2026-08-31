import 'package:flutter/widgets.dart';

import '../core/data/domain_registrar_api.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/data/pandora_repository.dart';
import '../core/data/project_experience_api.dart';
import '../core/data/project_experience_projection_repository.dart';
import '../core/data/project_experience_repository.dart';
import '../core/data/project_runtime_api.dart';
import '../core/diagnostics/diagnostics_store.dart';
import '../core/security/pandora_auth.dart';

class PandoraDependencies extends InheritedWidget {
  const PandoraDependencies({
    super.key,
    required this.auth,
    required this.repository,
    required this.diagnostics,
    this.intelligence,
    this.projectRuntime,
    this.projectExperience,
    this.projectExperienceProjection,
    this.projectExperienceRepository,
    this.domainRegistrar,
    required super.child,
  });

  final PandoraAuth auth;
  final PandoraRepository repository;
  final PandoraIntelligenceApi? intelligence;
  final ProjectRuntimeApi? projectRuntime;
  final ProjectExperienceApi? projectExperience;
  final ProjectExperienceProjectionRepository? projectExperienceProjection;
  final ProjectExperienceRepository? projectExperienceRepository;
  final DomainRegistrarApi? domainRegistrar;
  final DiagnosticsStore diagnostics;

  static PandoraDependencies of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<PandoraDependencies>();
    assert(result != null, 'PandoraDependencies is missing above this widget.');
    return result!;
  }

  @override
  bool updateShouldNotify(PandoraDependencies oldWidget) =>
      auth != oldWidget.auth ||
      repository != oldWidget.repository ||
      intelligence != oldWidget.intelligence ||
      projectRuntime != oldWidget.projectRuntime ||
      projectExperience != oldWidget.projectExperience ||
      projectExperienceProjection != oldWidget.projectExperienceProjection ||
      projectExperienceRepository != oldWidget.projectExperienceRepository ||
      domainRegistrar != oldWidget.domainRegistrar ||
      diagnostics != oldWidget.diagnostics;
}
