import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

class EnterpriseCodeApi {
  const EnterpriseCodeApi();

  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'pandora-github-analyze-repair-20260830',
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
    return Map<String, dynamic>.from(data);
  }
}
