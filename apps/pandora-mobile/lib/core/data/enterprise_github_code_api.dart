import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

/// Narrow foundation seam for Enterprise Code repository inspect/deploy.
///
/// Feature widgets must not import `supabase_flutter` directly; they call this
/// gateway instead. No service-role credential is present in the application.
abstract interface class EnterpriseGithubCodeGateway {
  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  });
}

class SupabaseEnterpriseGithubCodeGateway
    implements EnterpriseGithubCodeGateway {
  SupabaseEnterpriseGithubCodeGateway({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String functionName = 'pandora-github-analyze-repair-20260830';

  @override
  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  }) async {
    final response = await _client.functions.invoke(
      functionName,
      method: HttpMethod.post,
      headers: <String, String>{
        'x-organization-id': PandoraConfig.organizationId,
      },
      body: <String, Object?>{
        'action': action,
        if (action != 'status') 'repositoryUrl': repositoryUrl,
        if (deploymentId != null) 'deploymentId': deploymentId,
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException(
        'Pandora returned an invalid repository response.',
      );
    }
    final payload = Map<String, dynamic>.from(data);
    if (payload['ok'] != true) {
      throw StateError('${payload['code'] ?? 'UNKNOWN_ERROR'}');
    }
    return payload;
  }
}
