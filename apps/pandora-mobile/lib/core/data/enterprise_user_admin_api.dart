import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

class EnterpriseUserAdminApi {
  const EnterpriseUserAdminApi();

  Future<List<EnterpriseMember>> members() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw const EnterpriseUserAdminException('Please sign in again.');
    }
    try {
      final response = await client.functions.invoke(
        'pandora-user-admin',
        method: HttpMethod.get,
        headers: <String, String>{
          'x-organization-id': PandoraConfig.organizationId,
        },
      );
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status < 200 ||
          response.status >= 300 ||
          payload['ok'] != true) {
        throw EnterpriseUserAdminException(
          '${payload['plainMessage'] ?? 'Pandora could not load organization users.'}',
        );
      }
      final rows = payload['members'];
      if (rows is! List) return const <EnterpriseMember>[];
      return rows
          .whereType<Map>()
          .map(
            (row) => EnterpriseMember.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false);
    } on FunctionException catch (error) {
      final details = error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : const <String, dynamic>{};
      throw EnterpriseUserAdminException(
        '${details['plainMessage'] ?? 'Pandora could not load organization users.'}',
      );
    }
  }
}

class EnterpriseMember {
  const EnterpriseMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.status,
  });

  final String userId;
  final String email;
  final String role;
  final String status;

  factory EnterpriseMember.fromJson(Map<String, dynamic> json) =>
      EnterpriseMember(
        userId: '${json['userId'] ?? json['user_id'] ?? ''}',
        email: '${json['email'] ?? ''}',
        role: '${json['role'] ?? 'member'}',
        status: '${json['status'] ?? 'unknown'}',
      );
}

class EnterpriseUserAdminException implements Exception {
  const EnterpriseUserAdminException(this.message);
  final String message;
}
