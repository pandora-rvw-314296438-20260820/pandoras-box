import 'package:flutter/material.dart';

import '../core/design/pandora_theme.dart';
import '../core/design/pandora_tokens.dart';
import '../features/auth/plp_auth_gate.dart';
import 'pandora_dependencies.dart';
import 'pandora_runtime_bootstrap.dart';

class PlpEnterpriseApp extends StatefulWidget {
  const PlpEnterpriseApp({
    super.key,
    required this.runtime,
  });

  final PandoraRuntimeBootstrap runtime;

  @override
  State<PlpEnterpriseApp> createState() => _PlpEnterpriseAppState();
}

class _PlpEnterpriseAppState extends State<PlpEnterpriseApp> {
  @override
  void dispose() {
    widget.runtime.projectRuntime.close();
    widget.runtime.repository.dispose();
    widget.runtime.localStore.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    return PandoraDependencies(
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
      child: MaterialApp(
        title: 'PLP Pandora Enterprise',
        color: PandoraPalette.porcelain.canvas,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: PandoraTheme.porcelain,
        darkTheme: PandoraTheme.graphite,
        home: const PlpAuthGate(),
      ),
    );
  }
}
