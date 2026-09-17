import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

/// Foundation seam for PLP enterprise property overview reads.
///
/// Feature widgets must not import `supabase_flutter` directly.
abstract interface class EnterprisePlpOverviewGateway {
  Future<EnterprisePlpOverviewSnapshot> load({
    String slug = 'plp-boracay',
  });
}

class EnterprisePlpOverviewSnapshot {
  const EnterprisePlpOverviewSnapshot({
    required this.overview,
    required this.sources,
    required this.attention,
    required this.activity,
    required this.refreshedAt,
  });

  final Map<String, dynamic>? overview;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> attention;
  final List<Map<String, dynamic>> activity;
  final DateTime refreshedAt;
}

class SupabaseEnterprisePlpOverviewGateway
    implements EnterprisePlpOverviewGateway {
  SupabaseEnterprisePlpOverviewGateway({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<EnterprisePlpOverviewSnapshot> load({
    String slug = 'plp-boracay',
  }) async {
    Map<String, dynamic>? overview;
    List<Map<String, dynamic>> sources = const [];
    List<Map<String, dynamic>> attention = const [];
    List<Map<String, dynamic>> activity = const [];

    try {
      overview = await _client
          .from('enterprise_property_overview_v1')
          .select()
          .eq('organization_id', PandoraConfig.organizationId)
          .eq('slug', slug)
          .maybeSingle();
    } catch (_) {
      overview = null;
    }

    final propertyId = '${overview?['property_id'] ?? ''}';
    if (propertyId.isNotEmpty) {
      try {
        final rows = await _client
            .from('enterprise_source_connections')
            .select(
              'source_type,display_name,status,last_success_at,customer_message',
            )
            .eq('property_id', propertyId)
            .order('display_name');
        sources = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final rows = await _client
            .from('enterprise_attention_items')
            .select(
              'id,priority,category,title,summary,action_prompt,status,occurred_at,due_at',
            )
            .eq('property_id', propertyId)
            .inFilter('status', const ['open', 'acknowledged'])
            .order('occurred_at', ascending: false)
            .limit(6);
        attention = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final rows = await _client
            .from('enterprise_business_activity')
            .select('id,activity_key,category,title,summary,occurred_at')
            .eq('property_id', propertyId)
            .order('occurred_at', ascending: false)
            .limit(6);
        activity = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    return EnterprisePlpOverviewSnapshot(
      overview: overview,
      sources: sources,
      attention: attention,
      activity: activity,
      refreshedAt: DateTime.now(),
    );
  }
}
