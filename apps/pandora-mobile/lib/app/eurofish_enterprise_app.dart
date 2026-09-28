import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/pandora_theme.dart';
import '../core/design/pandora_tokens.dart';
import '../core/local_ai/pandora_local_ai_runtime.dart';
import '../features/auth/eurofish_auth_gate.dart';
import 'pandora_dependencies.dart';
import 'pandora_runtime_bootstrap.dart';

class EurofishEnterpriseApp extends StatefulWidget {
  const EurofishEnterpriseApp({
    super.key,
    required this.runtime,
  });

  final PandoraRuntimeBootstrap runtime;

  @override
  State<EurofishEnterpriseApp> createState() => _EurofishEnterpriseAppState();
}

class _EurofishEnterpriseAppState extends State<EurofishEnterpriseApp> {
  @override
  void initState() {
    super.initState();
    PandoraLocalAiRuntime.instance.start();
  }

  @override
  void dispose() {
    unawaited(PandoraLocalAiRuntime.instance.stop());
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
        title: 'Euro-Fish Pandora Enterprise',
        color: PandoraPalette.graphite.canvas,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: PandoraTheme.porcelain,
        darkTheme: PandoraTheme.graphite,
        home: const EurofishAuthGate(),
      ),
    );
  }
}
