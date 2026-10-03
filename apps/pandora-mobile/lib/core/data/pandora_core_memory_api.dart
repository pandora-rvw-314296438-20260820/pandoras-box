import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';
import '../config/pandora_runtime_binding.dart';
import 'pandora_core_api.dart';

const _ownerOrganization = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const _ownerProject = 'ee282126-3f61-4058-8c92-2fedbfcecf1f';
const _memoryProject = '7c686cbd-d968-49d5-86cc-918f5e777bd2';

class PandoraCoreMemoryContext {
  const PandoraCoreMemoryContext({
    required this.records,
    required this.retrievedAt,
    required this.digest,
    required this.degraded,
  });

  final List<PandoraCoreRecord> records;
  final DateTime retrievedAt;
  final String digest;
  final bool degraded;

  factory PandoraCoreMemoryContext.fromResponse(PandoraCoreRecord response) {
    final data = coreRecord(response['data']);
    final context = coreRecord(data['context']);
    final authority = coreRecord(context['authorization']);
    final policy = context['policyMemory'];
    final advisory = context['advisoryMemory'];
    final retrievedAt = DateTime.tryParse(coreText(context['asOf'], ''));
    if (response['ok'] != true ||
        response['operation'] != 'context' ||
        response['organizationId'] != _ownerOrganization ||
        response['projectId'] != _ownerProject ||
        response['authorizationGranted'] != false ||
        data['authorizationGranted'] != false ||
        !const ['available', 'degraded'].contains(data['state']) ||
        context['status'] != 'available' ||
        context['schemaVersion'] != 'm5.task-aware-retrieval.v1' ||
        coreRecord(context['project'])['id'] != _memoryProject ||
        context['namespace'] != 'real_life' ||
        authority['principalKey'] != 'pandora-mcpmaster-production' ||
        authority['environment'] != 'production' ||
        authority['canRead'] != true ||
        authority['retrievalDoesNotGrantExecutionAuthority'] != true ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(coreText(context['contextSha256'], '')) ||
        policy is! List ||
        advisory is! List ||
        policy.length > 4 ||
        advisory.length > 12 ||
        retrievedAt == null) {
      throw _invalidMemory();
    }
    final records = <PandoraCoreRecord>[];
    for (final raw in [...policy, ...advisory]) {
      final row = coreRecord(raw);
      final isPolicy = policy.contains(raw);
      if (row.isEmpty ||
          row['knowledgeSchemaVersion'] != 'm5.v1' ||
          !const ['hard_canon', 'soft_canon'].contains(row['canonStatus']) ||
          (isPolicy &&
              (row['recordType'] != 'policy' ||
                  row['canonStatus'] != 'hard_canon' ||
                  row['requiresRuntimeAuthorizationValidation'] != true ||
                  row['authorizationEffect'] !=
                      'requires_exact_runtime_scope_validity_revocation_validation')) ||
          (!isPolicy &&
              (row['recordType'] == 'policy' ||
                  row['authorizationEffect'] != 'none'))) {
        throw _invalidMemory();
      }
      records.add(Map<String, dynamic>.unmodifiable(row));
    }
    return PandoraCoreMemoryContext(
      records: List.unmodifiable(records),
      retrievedAt: retrievedAt,
      digest: context['contextSha256'] as String,
      degraded: data['state'] == 'degraded',
    );
  }
}

PandoraCoreFailure _invalidMemory() => const PandoraCoreFailure(
    'INVALID_MEMORY',
    'Pandora could not verify this Memory response. Try again.');

abstract interface class PandoraCoreMemoryGateway {
  Future<PandoraCoreMemoryContext> load();
}

/// Reuses the existing owner-authorized Vercel workload bridge. The client
/// cannot supply a Memory tenant, principal, provider destination or write.
class HttpPandoraCoreMemoryGateway implements PandoraCoreMemoryGateway {
  HttpPandoraCoreMemoryGateway({
    http.Client? client,
    String? Function()? accessToken,
    PandoraRuntimeBinding? runtimeBinding,
  })  : _runtimeBinding = runtimeBinding ?? PandoraConfig.runtimeBinding,
        _providedClient = client,
        _accessToken = accessToken ??
            (() => Supabase.instance.client.auth.currentSession?.accessToken);

  final PandoraRuntimeBinding _runtimeBinding;
  final http.Client? _providedClient;
  final String? Function() _accessToken;

  @override
  Future<PandoraCoreMemoryContext> load() async {
    if (_runtimeBinding.isAcceptance) {
      throw const PandoraCoreFailure(
          'MEMORY_UNAVAILABLE', 'Memory is unavailable in this environment.');
    }
    http.Client? ownedClient;
    try {
      final token = _accessToken();
      if (token == null || token.isEmpty) {
        throw const PandoraCoreFailure(
            'SIGN_IN_REQUIRED', 'Sign in to view approved Memory.');
      }
      final client = _providedClient ?? (ownedClient = http.Client());
      final request = http.Request(
          'POST', Uri.https('mcpmaster.vercel.app', '/api/operations-memory'))
        ..followRedirects = false
        ..headers.addAll({
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        })
        ..body = jsonEncode({
          'operation': 'context',
          'request': {
            'intent': 'general_assistance',
            'actionMode': 'read_only',
            'consequential': false,
            'terms': [
              'owner',
              'tenant',
              'security',
              'deployment',
              'provider',
              'mobile'
            ],
            'requiredCapabilities': <String>[],
            'maxBytes': 12288,
          },
        });
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PandoraCoreFailure('ACCESS_DENIED',
            'Approved Memory is available to authorized Pandora operators.');
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '')
              .contains('application/json') ||
          (response.contentLength ?? 0) > 48000) {
        throw _invalidMemory();
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > 48000) throw _invalidMemory();
        bytes.addAll(chunk);
      }
      if (_accessToken() != token) {
        throw const PandoraCoreFailure('SESSION_CHANGED',
            'Your session changed. Refresh Memory to continue.');
      }
      return PandoraCoreMemoryContext.fromResponse(
          coreRecord(jsonDecode(utf8.decode(bytes))));
    } on PandoraCoreFailure {
      rethrow;
    } catch (_) {
      throw const PandoraCoreFailure('MEMORY_UNAVAILABLE',
          'Memory is unavailable right now. Try again when connected.');
    } finally {
      ownedClient?.close();
    }
  }
}
