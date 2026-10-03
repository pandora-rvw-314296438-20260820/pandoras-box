import 'package:supabase_flutter/supabase_flutter.dart';

import 'pandora_core_api.dart';

/// Customer operating data has its own bounded projection. It never reuses
/// Pandora's privileged customer/commercial control-plane snapshot.
abstract interface class PandoraEnterpriseGateway {
  Future<PandoraCoreRecord> snapshot({
    required String organizationId,
    String section = 'overview',
    String? entryId,
  });

  Future<PandoraCoreRecord> operate({
    required String organizationId,
    required String operation,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
    String? entryId,
  });
}

abstract interface class PandoraWorkspaceAccessSource {
  Future<PandoraWorkspaceAccess> loadWorkspaceAccess();
}

class PandoraWorkspaceAccess {
  const PandoraWorkspaceAccess({
    required this.operatorMode,
    required this.workspaces,
  });
  final bool operatorMode;
  final List<PandoraEnterpriseMembership> workspaces;

  factory PandoraWorkspaceAccess.fromJson(PandoraCoreRecord value) =>
      PandoraWorkspaceAccess(
        operatorMode: value['operator_mode'] == true,
        workspaces: coreRecords(value['workspaces'])
            .map(PandoraEnterpriseMembership.fromJson)
            .toList(growable: false),
      );
}

class PandoraEnterpriseMembership {
  const PandoraEnterpriseMembership({
    required this.organizationId,
    required this.displayName,
    required this.slug,
    required this.workspaceType,
    required this.adapter,
    required this.role,
    this.propertyId,
    this.requiresOperatorEntry = false,
  });
  final String organizationId;
  final String displayName;
  final String slug;
  final String workspaceType;
  final String adapter;
  final String role;
  final String? propertyId;
  final bool requiresOperatorEntry;

  factory PandoraEnterpriseMembership.fromJson(PandoraCoreRecord row) {
    final organizationId = coreText(row['organization_id'], '');
    final adapter = coreText(row['adapter_key'] ?? row['adapter'], '');
    if (organizationId.isEmpty ||
        !const {'enterprise_core_v1', 'plp_v1'}.contains(adapter)) {
      throw const PandoraCoreFailure('INVALID_RESPONSE',
          'Pandora could not verify the available workspaces. Retry.');
    }
    return PandoraEnterpriseMembership(
      organizationId: organizationId,
      displayName: coreText(row['display_name'], 'Enterprise workspace'),
      slug: coreText(row['slug'], organizationId),
      workspaceType: coreText(row['workspace_type'], 'generic'),
      adapter: adapter,
      role: coreText(row['role'], 'viewer'),
      propertyId: row['property_id']?.toString(),
      requiresOperatorEntry: row['requires_operator_entry'] == true,
    );
  }
}

class SupabasePandoraEnterpriseGateway
    implements PandoraEnterpriseGateway, PandoraWorkspaceAccessSource {
  SupabasePandoraEnterpriseGateway({SupabaseClient? client})
      : _providedClient = client;
  final SupabaseClient? _providedClient;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;

  Future<PandoraCoreRecord> _invoke(
      String function, PandoraCoreRecord parameters) async {
    try {
      if (_client.auth.currentSession == null) {
        throw const PandoraCoreFailure(
            'SIGN_IN_REQUIRED', 'Sign in again to open your workspace.');
      }
      final value = coreRecord(await _client.rpc(function, params: parameters));
      if (value.isEmpty) {
        throw const PandoraCoreFailure('INVALID_RESPONSE',
            'Pandora could not verify the workspace response. Retry.');
      }
      return value;
    } on PandoraCoreFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw PandoraCoreFailure.fromServer(error.code, error.message);
    } catch (_) {
      throw const PandoraCoreFailure('UNAVAILABLE',
          'Pandora could not connect to this workspace. Retry when connected.');
    }
  }

  @override
  Future<PandoraWorkspaceAccess> loadWorkspaceAccess() async =>
      PandoraWorkspaceAccess.fromJson(
          await _invoke('pandora_enterprise_my_workspaces_v1', const {}));

  @override
  Future<PandoraCoreRecord> snapshot({
    required String organizationId,
    String section = 'overview',
    String? entryId,
  }) =>
      _invoke('pandora_enterprise_workspace_v1', {
        'p_organization_id': organizationId,
        'p_section': section,
        'p_entry_id': entryId,
      });

  @override
  Future<PandoraCoreRecord> operate({
    required String organizationId,
    required String operation,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
    String? entryId,
  }) =>
      _invoke('pandora_enterprise_operate_v1', {
        'p_organization_id': organizationId,
        'p_operation': operation,
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey,
        'p_entry_id': entryId,
      });
}
