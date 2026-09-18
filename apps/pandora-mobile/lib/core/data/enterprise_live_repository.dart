import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

class EnterpriseLiveRepository {
  const EnterpriseLiveRepository();

  SupabaseClient get _client => Supabase.instance.client;
  String get _organizationId => PandoraConfig.organizationId;

  Future<EnterpriseLiveSnapshot> load(String surface) async {
    try {
      return await (switch (surface) {
        'enterprise_data' => _loadData(),
        'enterprise_analytics' => _loadAnalytics(),
        'enterprise_marketing' => _loadMarketing(),
        'enterprise_domains' => _loadDomains(),
        'enterprise_integrations' => _loadIntegrations(),
        'enterprise_security' => _loadSecurity(),
        'enterprise_agents' => _loadAgents(),
        'enterprise_workflows' => _loadWorkflows(),
        'enterprise_logs' => _loadLogs(),
        'enterprise_api' => _loadRegistry(surface),
        'enterprise_settings' => _loadSettings(),
        'enterprise_mcp' => _loadRegistry(surface),
        _ => EnterpriseLiveSnapshot(
            surface: surface,
            title: 'Enterprise',
            summary: 'No provider-backed surface is registered for this page.',
            items: const <EnterpriseLiveItem>[],
          ),
      });
    } on PostgrestException catch (error) {
      throw EnterpriseLiveException(
        'Provider read failed: ${error.message}',
      );
    } on FunctionException {
      throw const EnterpriseLiveException(
        'Pandora could not read the provider registry right now.',
      );
    }
  }

  Future<Map<String, dynamic>?> _property() async {
    final row = await _client
        .from('enterprise_properties')
        .select(
          'id,project_id,slug,display_name,timezone,currency,source_status,source_observed_at,source_message,updated_at',
        )
        .eq('organization_id', _organizationId)
        .eq('slug', 'plp-boracay')
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> _snapshots({int limit = 14}) async {
    final rows = await _client
        .from('enterprise_hospitality_snapshots')
        .select(
          'id,property_id,business_date,as_of,occupancy_percent,rooms_total,rooms_available,arrivals_today,departures_today,revenue_today,adr,revpar,rooms_ready,rooms_not_ready,data_quality_state,source_label',
        )
        .eq('organization_id', _organizationId)
        .order('as_of', ascending: false)
        .limit(limit);
    return (rows as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<EnterpriseLiveSnapshot> _loadData() async {
    final property = await _property();
    final rows = await _snapshots(limit: 20);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_data',
      title: 'Data',
      summary: property == null
          ? 'No Enterprise property is connected to this organization.'
          : 'Verified hospitality snapshots for ${property['display_name']}.',
      partial: rows.any((row) => row['data_quality_state'] != 'verified'),
      items: rows
          .map(
            (row) => EnterpriseLiveItem(
              id: '${row['id']}',
              title: '${row['business_date'] ?? 'Business snapshot'}',
              subtitle:
                  'Occupancy ${_percent(row['occupancy_percent'])} · ${row['rooms_available'] ?? '—'} rooms available · as of ${_time(row['as_of'])}',
              status: '${row['data_quality_state'] ?? 'unknown'}',
              selection: <String, String>{
                'kind': 'hospitality_snapshot',
                'id': '${row['id']}',
                'businessDate': '${row['business_date'] ?? ''}',
              },
            ),
          )
          .toList(growable: false),
    );
  }

  Future<EnterpriseLiveSnapshot> _loadAnalytics() async {
    final rows = await _snapshots(limit: 8);
    final latest = rows.isEmpty ? null : rows.first;
    final metrics = <String, String>{
      'Occupancy': latest == null
          ? 'Unavailable'
          : _percent(latest['occupancy_percent']),
      'Rooms available': latest == null
          ? 'Unavailable'
          : '${latest['rooms_available'] ?? 'Unavailable'}',
      'Arrivals': latest == null
          ? 'Unavailable'
          : '${latest['arrivals_today'] ?? 'Unavailable'}',
      'Revenue': latest == null || latest['revenue_today'] == null
          ? 'Unavailable from connected source'
          : 'PHP ${latest['revenue_today']}',
      'ADR': latest == null || latest['adr'] == null
          ? 'Unavailable'
          : 'PHP ${latest['adr']}',
      'RevPAR': latest == null || latest['revpar'] == null
          ? 'Unavailable'
          : 'PHP ${latest['revpar']}',
    };
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_analytics',
      title: 'Analytics',
      summary: latest == null
          ? 'No verified business snapshot is available yet.'
          : 'Latest verified/partial operating metrics. Missing revenue values are shown as unavailable, never estimated.',
      partial: latest != null && latest['data_quality_state'] != 'verified',
      metrics: metrics,
      items: rows
          .map(
            (row) => EnterpriseLiveItem(
              id: '${row['id']}',
              title: '${row['business_date'] ?? 'Snapshot'}',
              subtitle:
                  '${_percent(row['occupancy_percent'])} occupancy · ${row['arrivals_today'] ?? '—'} arrivals · revenue ${row['revenue_today'] == null ? 'unavailable' : 'PHP ${row['revenue_today']}'}',
              status: '${row['data_quality_state'] ?? 'unknown'}',
              selection: <String, String>{
                'kind': 'analytics_snapshot',
                'id': '${row['id']}',
              },
            ),
          )
          .toList(growable: false),
    );
  }

  Future<EnterpriseLiveSnapshot> _loadMarketing() async {
    final rows = await _client
        .from('meta_drafts')
        .select(
            'id,page_id,kind,target_id,content,legal_review_required,status,created_at,updated_at')
        .eq('organization_id', _organizationId)
        .order('updated_at', ascending: false)
        .limit(30);
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final content = '${row['content'] ?? ''}'.trim();
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title:
            row['kind'] == 'post' ? 'Post draft' : '${row['kind'] ?? 'Draft'}',
        subtitle: content.isEmpty ? 'Empty draft' : content,
        status: row['legal_review_required'] == true
            ? 'legal review'
            : '${row['status'] ?? 'draft'}',
        selection: <String, String>{
          'kind': 'marketing_draft',
          'id': '${row['id']}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_marketing',
      title: 'Marketing',
      summary:
          'Organization marketing drafts. Publishing remains approval-gated and is never inferred from a draft.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadDomains() async {
    final rows = await _client
        .from('pandora_project_domains')
        .select(
          'id,project_id,domain,status,verified,primary_domain,environment,ownership_verified,dns_configured,tls_ready,routing_ready,runtime_healthy,last_checked_at',
        )
        .eq('organization_id', _organizationId)
        .order('updated_at', ascending: false)
        .limit(30);
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title: '${row['domain'] ?? 'Domain'}',
        subtitle:
            'DNS ${_yesNo(row['dns_configured'])} · TLS ${_yesNo(row['tls_ready'])} · routing ${_yesNo(row['routing_ready'])} · runtime ${_yesNo(row['runtime_healthy'])}',
        status: row['verified'] == true
            ? 'verified'
            : '${row['status'] ?? 'pending'}',
        selection: <String, String>{
          'kind': 'domain',
          'id': '${row['id']}',
          'domain': '${row['domain'] ?? ''}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_domains',
      title: 'Domains',
      summary:
          'Provider-backed domain and routing state. Purchase or DNS changes remain consequential actions.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadIntegrations() async {
    final rows = await _client
        .from('enterprise_source_connections')
        .select(
          'id,source_type,display_name,status,last_success_at,last_attempt_at,customer_message,updated_at',
        )
        .eq('organization_id', _organizationId)
        .order('display_name');
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title: '${row['display_name'] ?? row['source_type'] ?? 'Integration'}',
        subtitle:
            '${row['customer_message'] ?? 'No provider message.'} Last success: ${_time(row['last_success_at'])}.',
        status: '${row['status'] ?? 'unknown'}',
        selection: <String, String>{
          'kind': 'source_connection',
          'id': '${row['id']}',
          'sourceType': '${row['source_type'] ?? ''}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_integrations',
      title: 'Integrations',
      summary:
          'Live source connection health. Healthy, connecting and unavailable sources remain visibly distinct.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadSecurity() async {
    final membershipRows = await _client
        .from('memberships')
        .select('user_id,role,status,created_at,updated_at')
        .eq('organization_id', _organizationId)
        .order('created_at');
    final approvalRows = await _client
        .from('approvals')
        .select('id,decision,request_reason,expires_at,created_at')
        .eq('organization_id', _organizationId)
        .order('created_at', ascending: false)
        .limit(20);
    final memberships = (membershipRows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['user_id']}',
        title: 'Organization member',
        subtitle: 'Role: ${row['role']} · status: ${row['status']}',
        status: '${row['status'] ?? 'unknown'}',
        selection: <String, String>{
          'kind': 'membership',
          'id': '${row['user_id']}',
          'role': '${row['role'] ?? ''}',
        },
      );
    });
    final approvals = (approvalRows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title: 'Approval · ${row['decision']}',
        subtitle: '${row['request_reason'] ?? 'No request reason supplied.'}',
        status: '${row['decision'] ?? 'pending'}',
        selection: <String, String>{
          'kind': 'approval',
          'id': '${row['id']}',
        },
      );
    });
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_security',
      title: 'Security',
      summary:
          'Membership and approval state only. Credential references remain inaccessible to direct clients by RLS.',
      items: <EnterpriseLiveItem>[...memberships, ...approvals],
    );
  }

  Future<EnterpriseLiveSnapshot> _loadAgents() async {
    final rows = await _client
        .from('projectos_agent_runtime_proofs')
        .select(
          'id,agent_key,vendor,role,proven_capabilities,phone_only_compatible,credential_state,quota_state,health_state,active_leases,max_concurrent_leases,verified_at,expires_at,is_active',
        )
        .eq('organization_id', _organizationId)
        .eq('is_active', true)
        .order('verified_at', ascending: false)
        .limit(30);
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final capabilities = (row['proven_capabilities'] as List?)
              ?.map((value) => value.toString())
              .take(4)
              .join(', ') ??
          '';
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title: '${row['agent_key'] ?? 'Agent'} · ${row['vendor'] ?? ''}',
        subtitle:
            'Role ${row['role'] ?? '—'} · leases ${row['active_leases'] ?? 0}/${row['max_concurrent_leases'] ?? 0}${capabilities.isEmpty ? '' : ' · $capabilities'}',
        status: '${row['health_state'] ?? 'unknown'}',
        selection: <String, String>{
          'kind': 'agent_runtime_proof',
          'id': '${row['id']}',
          'agentKey': '${row['agent_key'] ?? ''}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_agents',
      title: 'Agents',
      summary: items.isEmpty
          ? 'No independently verified active agent runtime proof is currently available. Pandora will not invent one.'
          : 'Independently verified agent runtime proofs and bounded capabilities.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadWorkflows() async {
    final rows = await _client
        .from('workflow_runs')
        .select(
          'id,workflow_key,workflow_version,status,risk_ceiling,budget_cents,started_at,completed_at,created_at,updated_at',
        )
        .eq('organization_id', _organizationId)
        .order('created_at', ascending: false)
        .limit(40);
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title:
            '${row['workflow_key'] ?? 'Workflow'} · ${row['workflow_version'] ?? ''}',
        subtitle:
            'Risk ${row['risk_ceiling'] ?? '—'} · budget ${row['budget_cents'] ?? 0}¢ · created ${_time(row['created_at'])}',
        status: '${row['status'] ?? 'queued'}',
        selection: <String, String>{
          'kind': 'workflow_run',
          'id': '${row['id']}',
          'workflowKey': '${row['workflow_key'] ?? ''}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_workflows',
      title: 'Workflows',
      summary:
          'Governed workflow runs. A command may request orchestration, but this page shows only persisted run state.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadLogs() async {
    final rows = await _client
        .from('audit_events')
        .select(
          'id,actor_type,event_type,created_at,request_id,resource_type,resource_id,provenance_redacted',
        )
        .eq('organization_id', _organizationId)
        .order('created_at', ascending: false)
        .limit(60);
    final items = (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return EnterpriseLiveItem(
        id: '${row['id']}',
        title: '${row['event_type'] ?? 'Audit event'}',
        subtitle:
            '${row['actor_type'] ?? 'system'} · ${row['resource_type'] ?? 'resource'} · ${_time(row['created_at'])}',
        status: 'recorded',
        selection: <String, String>{
          'kind': 'audit_event',
          'id': '${row['id']}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_logs',
      title: 'Logs',
      summary:
          'Append-only organization audit evidence. Payloads are redacted before they reach this surface.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadRegistry(String surface) async {
    final payload = await _client.rpc(
      'pandora_plugin_runtime_registry_v4',
      params: <String, Object?>{'p_organization_id': _organizationId},
    );
    final map = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final rawProviders = map['providers'];
    final providers = rawProviders is List ? rawProviders : const <dynamic>[];
    final items = providers.map((raw) {
      final row =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final health = row['health'] is Map
          ? Map<String, dynamic>.from(row['health'] as Map)
          : <String, dynamic>{};
      return EnterpriseLiveItem(
        id: '${row['provider'] ?? row['label'] ?? 'provider'}',
        title: '${row['label'] ?? row['provider'] ?? 'Provider'}',
        subtitle:
            '${row['authorization'] ?? 'Authorization state unavailable'} · read ${_yesNo(row['readAvailable'])} · write ${_yesNo(row['writeAvailable'])}',
        status: '${row['state'] ?? health['rawStatus'] ?? 'unknown'}',
        selection: <String, String>{
          'kind': surface == 'enterprise_mcp' ? 'mcp_provider' : 'api_provider',
          'id': '${row['provider'] ?? ''}',
        },
      );
    }).toList(growable: false);
    return EnterpriseLiveSnapshot(
      surface: surface,
      title: surface == 'enterprise_mcp' ? 'MCP' : 'API',
      summary: surface == 'enterprise_mcp'
          ? 'Verified connector/runtime registry. Provider credentials are never rendered here.'
          : 'Verified API/provider capabilities and authorization state. Secret values are not client-readable.',
      items: items,
    );
  }

  Future<EnterpriseLiveSnapshot> _loadSettings() async {
    final property = await _property();
    final items = property == null
        ? const <EnterpriseLiveItem>[]
        : <EnterpriseLiveItem>[
            EnterpriseLiveItem(
              id: '${property['id']}',
              title: '${property['display_name'] ?? 'Enterprise workspace'}',
              subtitle:
                  'Timezone ${property['timezone'] ?? '—'} · currency ${property['currency'] ?? '—'} · source ${property['source_status'] ?? 'unknown'}',
              status: '${property['source_status'] ?? 'unknown'}',
              selection: <String, String>{
                'kind': 'enterprise_property',
                'id': '${property['id']}',
                'slug': '${property['slug'] ?? ''}',
              },
            ),
          ];
    return EnterpriseLiveSnapshot(
      surface: 'enterprise_settings',
      title: 'Settings',
      summary:
          'Current Enterprise workspace settings. Consequential configuration changes remain approval-gated.',
      items: items,
    );
  }

  static String _yesNo(Object? value) => value == true ? 'ready' : 'not ready';

  static String _percent(Object? value) {
    if (value == null) return 'Unavailable';
    final number = num.tryParse(value.toString());
    if (number == null) return 'Unavailable';
    return '${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)}%';
  }

  static String _time(Object? value) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text)?.toLocal();
    if (parsed == null) return 'unavailable';
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} $hour:$minute';
  }
}

class EnterpriseLiveSnapshot {
  const EnterpriseLiveSnapshot({
    required this.surface,
    required this.title,
    required this.summary,
    required this.items,
    this.metrics = const <String, String>{},
    this.partial = false,
  });

  final String surface;
  final String title;
  final String summary;
  final List<EnterpriseLiveItem> items;
  final Map<String, String> metrics;
  final bool partial;
}

class EnterpriseLiveItem {
  const EnterpriseLiveItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.selection,
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final Map<String, String> selection;
}

class EnterpriseLiveException implements Exception {
  const EnterpriseLiveException(this.message);
  final String message;
}
