import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/pandora_core_api.dart';
import '../core/local/pandora_local_store_stub.dart';
import 'pandora_dependencies.dart';
import 'pandora_runtime_bootstrap.dart';

typedef PandoraClientRuntimeFactory = PandoraClientRuntime Function(
  String organizationId,
);

/// A scope-local set of existing services, not a new execution implementation.
/// No owner cache, conversation or pending queue is shared with a client.
class PandoraClientRuntime {
  PandoraClientRuntime({
    required this.dependencies,
    required this.dispose,
  });

  final PandoraDependencies dependencies;
  final VoidCallback dispose;

  factory PandoraClientRuntime.create(String organizationId) {
    final store = MemoryPandoraLocalStore();
    final runtime = PandoraRuntimeBootstrap.create(
      Supabase.instance.client,
      localStore: store,
      organizationId: organizationId,
    );
    return PandoraClientRuntime(
      dependencies: PandoraDependencies(
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
        localStore: store,
        child: const SizedBox.shrink(),
      ),
      dispose: () {
        runtime.projectRuntime.close();
        runtime.repository.dispose();
        store.close();
      },
    );
  }

  Widget wrap(Widget child) => PandoraDependencies(
        auth: dependencies.auth,
        repository: dependencies.repository,
        activityHistory: dependencies.activityHistory,
        intelligence: dependencies.intelligence,
        projectRuntime: dependencies.projectRuntime,
        projectExperience: dependencies.projectExperience,
        projectExperienceProjection: dependencies.projectExperienceProjection,
        projectExperienceRepository: dependencies.projectExperienceRepository,
        domainRegistrar: dependencies.domainRegistrar,
        diagnostics: dependencies.diagnostics,
        localStore: dependencies.localStore,
        child: child,
      );
}

class PandoraClientEntry {
  const PandoraClientEntry({
    required this.entryId,
    required this.organizationId,
    required this.propertyId,
    required this.workspaceType,
    required this.displayName,
    required this.expiresAt,
  });

  final String entryId;
  final String organizationId;
  final String? propertyId;
  final String workspaceType;
  final String displayName;
  final DateTime expiresAt;

  factory PandoraClientEntry.verify(
    PandoraCoreRecord receipt, {
    required String requestedOrganizationId,
    DateTime? now,
  }) {
    final entryId = coreText(receipt['entry_id'], '');
    final organization = coreText(receipt['organization_id'], '');
    final type = coreText(receipt['workspace_type'], '');
    final expiry = DateTime.tryParse(coreText(receipt['expires_at'], ''));
    if (entryId.isEmpty ||
        organization.isEmpty ||
        requestedOrganizationId.trim().isEmpty ||
        organization != requestedOrganizationId ||
        type.isEmpty ||
        expiry == null ||
        !expiry.isAfter(now ?? DateTime.now())) {
      throw const PandoraCoreFailure(
        'SCOPE_MISMATCH',
        'Pandora could not verify the requested client access.',
      );
    }
    return PandoraClientEntry(
      entryId: entryId,
      organizationId: organization,
      propertyId: coreText(receipt['property_id'], '').isEmpty
          ? null
          : coreText(receipt['property_id']),
      workspaceType: type,
      displayName: coreText(receipt['display_name'], 'Client workspace'),
      expiresAt: expiry,
    );
  }
}
