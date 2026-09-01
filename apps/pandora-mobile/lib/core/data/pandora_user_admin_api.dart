import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef PandoraJson = Map<String, dynamic>;

/// The narrow contract consumed by the Team experience.
///
/// Keeping the screen behind this interface makes every state testable while
/// the production implementation remains bound to the signed-in Supabase
/// session. No service-role credential is ever present in the application.
abstract interface class PandoraUserAdminGateway {
  Future<List<PandoraOrganizationAccess>> loadOrganizations();

  Future<List<PandoraTeamMember>> loadMembers(String organizationId);

  Future<PandoraInviteResult> inviteMember(
    String organizationId,
    PandoraInviteRequest request,
  );
}

class SupabasePandoraUserAdminGateway implements PandoraUserAdminGateway {
  SupabasePandoraUserAdminGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String functionName = 'pandora-user-admin';

  @override
  Future<List<PandoraOrganizationAccess>> loadOrganizations() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const PandoraUserAdminFailure(
        code: 'SIGN_IN_REQUIRED',
        message: 'Sign in to manage your team.',
      );
    }

    try {
      final response = await _client
          .from('memberships')
          .select(
            'organization_id, role, status, created_at, '
            'organizations(name, slug)',
          )
          .eq('user_id', user.id)
          .eq('status', 'active')
          .order('created_at');

      final organizations = <PandoraOrganizationAccess>[];
      for (final value in response) {
        final row = _map(value);
        final role = _string(row['role']);
        if (role != 'owner' && role != 'admin') continue;
        final organization = _map(row['organizations']);
        final id = _string(row['organization_id']);
        if (id == null) continue;
        organizations.add(
          PandoraOrganizationAccess(
            id: id,
            name: _string(organization['name']) ?? 'Organization',
            slug: _string(organization['slug']),
            role: role!,
          ),
        );
      }
      return organizations;
    } on PostgrestException catch (error) {
      throw PandoraUserAdminFailure(
        code: 'ORGANIZATION_LOOKUP_FAILED',
        message: _plainPostgrestMessage(
          error,
          'Pandora could not load your organization access.',
        ),
      );
    } catch (error) {
      if (error is PandoraUserAdminFailure) rethrow;
      throw const PandoraUserAdminFailure(
        code: 'ORGANIZATION_LOOKUP_FAILED',
        message: 'Pandora could not load your organization access.',
      );
    }
  }

  @override
  Future<List<PandoraTeamMember>> loadMembers(String organizationId) async {
    final payload = await _invoke(
      organizationId: organizationId,
      method: HttpMethod.get,
    );
    final rawMembers = payload['members'];
    if (rawMembers is! List) {
      throw const PandoraUserAdminFailure(
        code: 'INVALID_RESPONSE',
        message: 'Pandora received an invalid team response.',
      );
    }
    return rawMembers
        .map((value) => PandoraTeamMember.fromJson(_map(value)))
        .toList(growable: false);
  }

  @override
  Future<PandoraInviteResult> inviteMember(
    String organizationId,
    PandoraInviteRequest request,
  ) async {
    final payload = await _invoke(
      organizationId: organizationId,
      method: HttpMethod.post,
      body: request.toJson(),
    );
    return PandoraInviteResult.fromJson(payload);
  }

  Future<PandoraJson> _invoke({
    required String organizationId,
    required HttpMethod method,
    PandoraJson? body,
  }) async {
    if (_client.auth.currentSession == null) {
      throw const PandoraUserAdminFailure(
        code: 'SIGN_IN_REQUIRED',
        message: 'Sign in to manage your team.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        functionName,
        method: method,
        headers: <String, String>{'x-organization-id': organizationId},
        body: body,
      );
      final payload = _decodeMap(response.data);
      if (response.status < 200 || response.status >= 300) {
        throw PandoraUserAdminFailure.fromPayload(
          payload,
          fallbackCode: 'USER_ADMIN_FAILED',
          fallbackMessage: 'Pandora could not complete the team request.',
        );
      }
      return payload;
    } on FunctionException catch (error) {
      final details = _decodeMap(error.details);
      throw PandoraUserAdminFailure.fromPayload(
        details,
        fallbackCode: 'USER_ADMIN_UNAVAILABLE',
        fallbackMessage: _friendlyFunctionMessage(error),
      );
    } catch (error) {
      if (error is PandoraUserAdminFailure) rethrow;
      throw const PandoraUserAdminFailure(
        code: 'USER_ADMIN_UNAVAILABLE',
        message: 'Team management is temporarily unavailable.',
      );
    }
  }
}

class PandoraOrganizationAccess {
  const PandoraOrganizationAccess({
    required this.id,
    required this.name,
    required this.role,
    this.slug,
  });

  final String id;
  final String name;
  final String role;
  final String? slug;

  bool get isOwner => role == 'owner';
}

class PandoraTeamMember {
  const PandoraTeamMember({
    required this.id,
    required this.role,
    required this.status,
    this.email,
    this.displayName,
    this.invitedBy,
    this.joinedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory PandoraTeamMember.fromJson(PandoraJson json) => PandoraTeamMember(
    id: _string(json['id']) ?? '',
    email: _string(json['email']),
    displayName: _string(json['displayName'] ?? json['display_name']),
    role: _string(json['role']) ?? 'member',
    status: _string(json['status']) ?? 'invited',
    invitedBy: _string(json['invitedBy'] ?? json['invited_by']),
    joinedAt: _date(json['joinedAt'] ?? json['joined_at']),
    createdAt: _date(json['createdAt'] ?? json['created_at']),
    updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
  );

  final String id;
  final String? email;
  final String? displayName;
  final String role;
  final String status;
  final String? invitedBy;
  final DateTime? joinedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get primaryLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final address = email?.trim();
    if (address != null && address.isNotEmpty) return address;
    return 'Pandora user';
  }

  String get initials {
    final words = primaryLabel
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (words.isEmpty) return 'P';
    return words.map((word) => word[0].toUpperCase()).join();
  }

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';
}

class PandoraInviteRequest {
  const PandoraInviteRequest({
    required this.email,
    required this.role,
    this.displayName,
    this.timezone = 'UTC',
  });

  final String email;
  final String role;
  final String? displayName;
  final String timezone;

  PandoraJson toJson() => <String, dynamic>{
    'email': email.trim().toLowerCase(),
    'displayName': _nullableTrimmed(displayName),
    'timezone': timezone.trim().isEmpty ? 'UTC' : timezone.trim(),
    'role': role,
  };
}

class PandoraInviteResult {
  const PandoraInviteResult({
    required this.userId,
    required this.email,
    required this.role,
    required this.status,
    required this.inviteSent,
    required this.existingAccount,
    this.displayName,
    this.requestId,
  });

  factory PandoraInviteResult.fromJson(PandoraJson json) {
    final user = _map(json['user']);
    final membership = _map(json['membership']);
    return PandoraInviteResult(
      userId: _string(user['id']) ?? '',
      email: _string(user['email']) ?? '',
      displayName: _string(user['displayName'] ?? user['display_name']),
      role: _string(membership['role']) ?? 'member',
      status: _string(membership['status']) ?? 'invited',
      inviteSent: json['inviteSent'] == true,
      existingAccount: json['existingAccount'] == true,
      requestId: _string(json['requestId']),
    );
  }

  final String userId;
  final String email;
  final String? displayName;
  final String role;
  final String status;
  final bool inviteSent;
  final bool existingAccount;
  final String? requestId;
}

class PandoraUserAdminFailure implements Exception {
  const PandoraUserAdminFailure({
    required this.code,
    required this.message,
    this.requestId,
  });

  factory PandoraUserAdminFailure.fromPayload(
    PandoraJson payload, {
    required String fallbackCode,
    required String fallbackMessage,
  }) => PandoraUserAdminFailure(
    code: _string(payload['code']) ?? fallbackCode,
    message:
        _string(payload['plainMessage'] ?? payload['message']) ??
        fallbackMessage,
    requestId: _string(payload['requestId']),
  );

  final String code;
  final String message;
  final String? requestId;

  bool get isPermissionFailure =>
      code == 'ADMIN_ROLE_REQUIRED' ||
      code == 'OWNER_ROLE_REQUIRED' ||
      code == 'ORGANIZATION_ACCESS_REQUIRED';

  @override
  String toString() => message;
}

PandoraJson _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

PandoraJson _decodeMap(Object? value) {
  if (value is String) {
    try {
      return _map(jsonDecode(value));
    } catch (_) {
      return <String, dynamic>{};
    }
  }
  return _map(value);
}

String? _string(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

DateTime? _date(Object? value) {
  final raw = _string(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

String _friendlyFunctionMessage(FunctionException error) {
  if (error.status == 401) {
    return 'Sign in again to manage your team.';
  }
  if (error.status == 403) {
    return 'You do not have permission to manage this team.';
  }
  if (error.status == 429) {
    return 'Too many requests. Try again shortly.';
  }
  return 'Team management is temporarily unavailable.';
}

String _plainPostgrestMessage(PostgrestException error, String fallback) {
  final message = error.message.trim();
  return message.isEmpty ? fallback : fallback;
}
