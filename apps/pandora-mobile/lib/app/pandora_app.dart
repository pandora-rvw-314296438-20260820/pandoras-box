import 'package:flutter/material.dart';

import '../core/data/domain_registrar_api.dart';
import '../core/data/pandora_repository.dart';
import '../core/data/project_experience_api.dart';
import '../core/data/project_runtime_api.dart';
import '../core/design/pandora_theme.dart';
import '../core/design/pandora_tokens.dart';
import '../core/diagnostics/diagnostics_store.dart';
import '../core/security/pandora_auth.dart';
import '../features/auth/auth_gate.dart';
import 'pandora_dependencies.dart';

class PandoraApp extends StatefulWidget {
  const PandoraApp({
    super.key,
    required this.auth,
    required this.repository,
    required this.diagnostics,
    this.projectRuntime,
    this.projectExperience,
    this.domainRegistrar,
  });

  final PandoraAuth auth;
  final PandoraRepository repository;
  final ProjectRuntimeApi? projectRuntime;
  final ProjectExperienceApi? projectExperience;
  final DomainRegistrarApi? domainRegistrar;
  final DiagnosticsStore diagnostics;

  @override
  State<PandoraApp> createState() => _PandoraAppState();
}

class _PandoraAppState extends State<PandoraApp> {
  @override
  void dispose() {
    widget.projectRuntime?.close();
    widget.repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PandoraDependencies(
    auth: widget.auth,
    repository: widget.repository,
    projectRuntime: widget.projectRuntime,
    projectExperience: widget.projectExperience,
    domainRegistrar: widget.domainRegistrar,
    diagnostics: widget.diagnostics,
    child: MaterialApp(
      title: "Pandora's Box",
      color: PandoraPalette.porcelain.canvas,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: PandoraTheme.porcelain,
      darkTheme: PandoraTheme.graphite,
      home: const AuthGate(),
    ),
  );
}
