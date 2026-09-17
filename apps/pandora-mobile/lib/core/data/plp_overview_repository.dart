import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

class PlpOverviewRepository {
  const PlpOverviewRepository();

  Future<PlpOverviewData> load() async {
    final client = Supabase.instance.client;
    Map<String, dynamic>? overview;
    List<Map<String, dynamic>> sources = const [];
    List<Map<String, dynamic>> attention = const [];
    List<Map<String, dynamic>> activity = const [];

    try {
      overview = await client
          .from('enterprise_property_overview_v1')
          .select()
          .eq('organization_id', PandoraConfig.organizationId)
          .eq('slug', 'plp-boracay')
          .maybeSingle();
    } catch (_) {
      overview = null;
    }

    final propertyId = '${overview?['property_id'] ?? ''}';
    if (propertyId.isNotEmpty) {
      try {
        final rows = await client
            .from('enterprise_source_connections')
            .select(
                'source_type,display_name,status,last_success_at,customer_message')
            .eq('property_id', propertyId)
            .order('display_name');
        sources = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final rows = await client
            .from('enterprise_attention_items')
            .select(
                'id,priority,category,title,summary,action_prompt,status,occurred_at,due_at')
            .eq('property_id', propertyId)
            .inFilter('status', const ['open', 'acknowledged'])
            .order('occurred_at', ascending: false)
            .limit(6);
        attention = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final rows = await client
            .from('enterprise_business_activity')
            .select('id,activity_key,category,title,summary,occurred_at')
            .eq('property_id', propertyId)
            .order('occurred_at', ascending: false)
            .limit(6);
        activity = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    return PlpOverviewData(
      overview: overview,
      sources: sources,
      attention: attention,
      activity: activity,
      refreshedAt: DateTime.now(),
    );
  }
}

class PlpOverviewData {
  const PlpOverviewData({
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
