import 'package:flutter/material.dart';

import 'pandora_app.dart';
import 'pandora_runtime_bootstrap.dart';
import 'plp_enterprise_shell.dart';

class PlpEnterpriseApp extends StatelessWidget {
  const PlpEnterpriseApp({
    super.key,
    required this.runtime,
  });

  final PandoraRuntimeBootstrap runtime;

  @override
  Widget build(BuildContext context) => PandoraApp(
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
        appTitle: 'PLP Pandora Enterprise',
        authenticatedHomeBuilder: (_) => const PlpEnterpriseShell(),
      );
}
