import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

typedef PlpGraphqlPost = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
});

Future<http.Response> _defaultPlpGraphqlPost(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) =>
    http.post(url, headers: headers, body: body);

class PlpGraphqlException implements Exception {
  const PlpGraphqlException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlpGraphqlDashboardBundle {
  const PlpGraphqlDashboardBundle({
    required this.overview,
    required this.guests,
    required this.operations,
    required this.activity,
    required this.ownerDashboards,
  });

  final Map<String, Object?>? overview;
  final List<Map<String, Object?>> guests;
  final List<Map<String, Object?>> operations;
  final List<Map<String, Object?>> activity;
  final List<Map<String, Object?>> ownerDashboards;
}

class PlpGraphqlApi {
  PlpGraphqlApi({
    SupabaseClient? supabase,
    PlpGraphqlPost? post,
    String? supabaseUrl,
    String? publishableKey,
  })  : _supabase = supabase,
        _post = post ?? _defaultPlpGraphqlPost,
        _supabaseUrl = supabaseUrl ?? PandoraConfig.supabaseUrl,
        _publishableKey =
            publishableKey ?? PandoraConfig.supabasePublishableKey;

  final SupabaseClient? _supabase;
  final PlpGraphqlPost _post;
  final String _supabaseUrl;
  final String _publishableKey;

  SupabaseClient get _client => _supabase ?? Supabase.instance.client;

  static const dashboardQuery = r'''
query PlpDashboardReadModel {
  plp_graphql_overview_v1Collection(first: 1) {
    edges {
      node {
        property_id
        organization_id
        property_slug
        property_name
        timezone
        currency
        source_status
        source_observed_at
        source_message
        snapshot_id
        business_date
        as_of
        occupancy_percent
        rooms_total
        rooms_available
        arrivals_today
        departures_today
        revenue_today
        adr
        revpar
        rooms_ready
        rooms_not_ready
        data_quality_state
        source_label
      }
    }
  }
  plp_graphql_guests_v1Collection(
    first: 250
    orderBy: [{check_in: AscNullsLast}, {full_name: AscNullsLast}]
  ) {
    edges {
      node {
        booking_id
        guest_id
        organization_id
        property_id
        business_date
        full_name
        booking_reference
        accommodation_name
        check_in
        check_out
        nights
        guest_count
        payment_status
        status
        special_requests
        source
        display_status
        is_mock
        updated_at
      }
    }
  }
  plp_graphql_operations_v1Collection(
    first: 200
    orderBy: [{updated_at: DescNullsLast}, {task_id: DescNullsLast}]
  ) {
    edges {
      node {
        task_id
        organization_id
        property_id
        booking_reference
        kind
        category
        priority
        status
        title
        note
        source
        actor
        created_at
        updated_at
        completed_at
        full_name
        accommodation_name
        is_mock
      }
    }
  }
  plp_graphql_activity_v1Collection(
    first: 80
    orderBy: [{occurred_at: DescNullsLast}, {activity_id: DescNullsLast}]
  ) {
    edges {
      node {
        activity_id
        organization_id
        property_id
        audience
        category
        title
        summary
        source_label
        occurred_at
        is_mock
      }
    }
  }
  enterprise_graphql_owner_dashboards_v1Collection(
    first: 50
    orderBy: [{property_name: AscNullsLast}]
  ) {
    edges {
      node {
        property_id
        organization_id
        property_slug
        property_name
        timezone
        currency
        source_status
        source_observed_at
        source_message
        snapshot_id
        business_date
        as_of
        occupancy_percent
        rooms_total
        rooms_available
        arrivals_today
        departures_today
        revenue_today
        adr
        revpar
        rooms_ready
        rooms_not_ready
        data_quality_state
        source_label
      }
    }
  }
}
''';

  static const businessActivityQuery = r'''
query PlpBusinessActivity {
  plp_graphql_activity_v1Collection(
    first: 80
    orderBy: [{occurred_at: DescNullsLast}, {activity_id: DescNullsLast}]
  ) {
    edges {
      node {
        activity_id
        organization_id
        property_id
        audience
        category
        title
        summary
        source_label
        occurred_at
        is_mock
      }
    }
  }
}
''';

  static const ownerDashboardsQuery = r'''
query OwnerDashboards {
  enterprise_graphql_owner_dashboards_v1Collection(
    first: 50
    orderBy: [{property_name: AscNullsLast}]
  ) {
    edges {
      node {
        property_id
        organization_id
        property_slug
        property_name
        timezone
        currency
        source_status
        source_observed_at
        source_message
        snapshot_id
        business_date
        as_of
        occupancy_percent
        rooms_total
        rooms_available
        arrivals_today
        departures_today
        revenue_today
        adr
        revpar
        rooms_ready
        rooms_not_ready
        data_quality_state
        source_label
      }
    }
  }
}
''';

  Future<PlpGraphqlDashboardBundle> loadDashboardBundle() async {
    final data = await _execute(dashboardQuery);
    final overview =
        _nodes(data, 'plp_graphql_overview_v1Collection').firstOrNull;
    return PlpGraphqlDashboardBundle(
      overview: overview,
      guests: _nodes(data, 'plp_graphql_guests_v1Collection'),
      operations: _nodes(data, 'plp_graphql_operations_v1Collection'),
      activity: _nodes(data, 'plp_graphql_activity_v1Collection'),
      ownerDashboards:
          _nodes(data, 'enterprise_graphql_owner_dashboards_v1Collection'),
    );
  }

  Future<Map<String, Object?>> loadBusinessActivity() async {
    final data = await _execute(businessActivityQuery);
    return <String, Object?>{
      'schemaVersion': 'plp.business-activity.graphql.v1',
      'items': _nodes(data, 'plp_graphql_activity_v1Collection')
          .map(_activityItem)
          .toList(growable: false),
    };
  }

  Future<List<Map<String, Object?>>> loadOwnerDashboards() async {
    final data = await _execute(ownerDashboardsQuery);
    return _nodes(data, 'enterprise_graphql_owner_dashboards_v1Collection');
  }

  Future<Map<String, Object?>> _execute(String query) async {
    SupabaseClient client;
    try {
      client = _client;
    } catch (_) {
      throw const PlpGraphqlException(
        'The authenticated resort data service is not initialized.',
      );
    }
    final session = client.auth.currentSession;
    final accessToken = session?.accessToken.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const PlpGraphqlException(
        'An authenticated Pandora session is required for resort data.',
      );
    }

    final endpoint =
        _supabaseUrl.replaceFirst(RegExp(r'/+$'), '') + '/graphql/v1';
    final response = await _post(
      Uri.parse(endpoint),
      headers: <String, String>{
        'apikey': _publishableKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'query': query}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PlpGraphqlException(
        'The verified resort data service is temporarily unavailable.',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const PlpGraphqlException(
        'The resort data service returned an invalid response.',
      );
    }
    if (decoded is! Map) {
      throw const PlpGraphqlException(
        'The resort data service returned an invalid response.',
      );
    }

    final envelope = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final errors = envelope['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw const PlpGraphqlException(
        'The requested resort data could not be verified.',
      );
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw const PlpGraphqlException(
        'The requested resort data could not be verified.',
      );
    }
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Map<String, Object?>> _nodes(
    Map<String, Object?> data,
    String connectionName,
  ) {
    final connection = _map(data[connectionName]);
    final edges = connection['edges'];
    if (edges is! List) return const <Map<String, Object?>>[];
    return edges
        .whereType<Map>()
        .map((edge) => _map(edge['node']))
        .where((node) => node.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, Object?> _activityItem(Map<String, Object?> row) =>
      <String, Object?>{
        'id': row['activity_id'],
        'audience': row['audience'],
        'category': row['category'],
        'title': row['title'],
        'summary': row['summary'],
        'sourceLabel': row['source_label'],
        'occurredAt': row['occurred_at'],
        'isMock': row['is_mock'],
      };

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }
}

Map<String, Object?> mergePlpGraphqlDashboardIntoBootstrap(
  Map<String, Object?> bootstrap,
  PlpGraphqlDashboardBundle bundle,
) {
  final overview = bundle.overview;
  if (overview == null) {
    return <String, Object?>{
      ...bootstrap,
      'graphqlReadState': 'empty',
    };
  }

  final today = _objectMap(bootstrap['today']);
  final guestExperience = _objectMap(bootstrap['guestExperience']);
  final sourceHealth = _objectMap(bootstrap['sourceHealth']);
  final businessDate = overview['business_date']?.toString() ??
      guestExperience['businessDate']?.toString();

  final inHouse = <Map<String, Object?>>[];
  final arrivals = <Map<String, Object?>>[];
  final departing = <Map<String, Object?>>[];
  for (final row in bundle.guests) {
    final guest = _guestItem(row, businessDate);
    final checkIn = row['check_in']?.toString();
    final checkOut = row['check_out']?.toString();
    final status = row['status']?.toString().toUpperCase() ?? '';
    if (businessDate != null && checkIn == businessDate) {
      arrivals.add(guest);
    }
    if (businessDate != null && checkOut == businessDate) {
      departing.add(guest);
    }
    if (businessDate != null &&
        checkOut != null &&
        checkOut.compareTo(businessDate) > 0 &&
        ((checkIn != null && checkIn.compareTo(businessDate) < 0) ||
            status == 'CHECKED_IN' ||
            status == 'IN_HOUSE')) {
      inHouse.add(guest);
    }
  }

  final attention =
      bundle.operations.map(_operationItem).toList(growable: false);
  final containsMockData = <Map<String, Object?>>[
    ...bundle.guests,
    ...bundle.operations,
  ].any((row) => _boolValue(row['is_mock']));

  final todayOverlay = <String, Object?>{
    ...today,
    if (overview['occupancy_percent'] != null)
      'occupancy_percent': overview['occupancy_percent'],
    if (overview['rooms_total'] != null)
      'rooms_total': overview['rooms_total'],
    if (overview['rooms_available'] != null)
      'rooms_available': overview['rooms_available'],
    if (overview['arrivals_today'] != null)
      'arrivals_today': overview['arrivals_today'],
    if (overview['departures_today'] != null)
      'departures_today': overview['departures_today'],
    if (overview['revenue_today'] != null)
      'sales_today_php': overview['revenue_today'],
    if (overview['adr'] != null) 'adr': overview['adr'],
    if (overview['revpar'] != null) 'revpar': overview['revpar'],
    if (overview['rooms_ready'] != null)
      'rooms_ready': overview['rooms_ready'],
    if (overview['rooms_not_ready'] != null)
      'rooms_not_ready': overview['rooms_not_ready'],
    'open_staff_tasks': bundle.operations.length,
  };

  return <String, Object?>{
    ...bootstrap,
    'today': todayOverlay,
    'sourceHealth': <String, Object?>{
      ...sourceHealth,
      if (overview['source_status'] != null)
        'state': overview['source_status'],
      if (overview['source_observed_at'] != null)
        'observedAt': overview['source_observed_at'],
      if (overview['source_message'] != null)
        'message': overview['source_message'],
    },
    'latestHospitalitySnapshot': <String, Object?>{
      'id': overview['snapshot_id'],
      'business_date': overview['business_date'],
      'as_of': overview['as_of'],
      'occupancy_percent': overview['occupancy_percent'],
      'rooms_total': overview['rooms_total'],
      'rooms_available': overview['rooms_available'],
      'arrivals_today': overview['arrivals_today'],
      'departures_today': overview['departures_today'],
      'revenue_today': overview['revenue_today'],
      'adr': overview['adr'],
      'revpar': overview['revpar'],
      'rooms_ready': overview['rooms_ready'],
      'rooms_not_ready': overview['rooms_not_ready'],
      'data_quality_state': overview['data_quality_state'],
      'source_label': overview['source_label'],
    },
    'guestExperience': <String, Object?>{
      ...guestExperience,
      if (businessDate != null) 'businessDate': businessDate,
      'inHouse': inHouse,
      'arrivals': arrivals,
      'departing': departing,
      'attention': attention,
      'containsMockData': containsMockData,
    },
    'graphqlOperationsContext': <String, Object?>{
      'source': 'supabase-graphql',
      'asOf': overview['as_of'],
      'openTaskCount': bundle.operations.length,
      'highPriorityCount': bundle.operations
          .where((row) {
            final priority = row['priority']?.toString().toLowerCase();
            return priority == 'high' || priority == 'critical';
          })
          .length,
      'tasks': bundle.operations
          .take(12)
          .map(_operationItem)
          .toList(growable: false),
    },
    'graphqlReadState': 'verified',
  };
}

Map<String, Object?> _guestItem(
  Map<String, Object?> row,
  String? businessDate,
) {
  var dayOfStay = 1;
  final checkIn = DateTime.tryParse(row['check_in']?.toString() ?? '');
  final date = DateTime.tryParse(businessDate ?? '');
  if (checkIn != null && date != null) {
    dayOfStay = date.difference(checkIn).inDays + 1;
    if (dayOfStay < 1) dayOfStay = 1;
  }
  return <String, Object?>{
    'id': row['guest_id'],
    'bookingId': row['booking_id'],
    'fullName': row['full_name'],
    'bookingReference': row['booking_reference'],
    'accommodationName': row['accommodation_name'],
    'checkIn': row['check_in'],
    'checkOut': row['check_out'],
    'stayDays': row['nights'],
    'dayOfStay': dayOfStay,
    'guestCount': row['guest_count'],
    'paymentStatus': row['payment_status'],
    'status': row['status'],
    'displayStatus': row['display_status'],
    'specialRequest': row['special_requests'],
    'source': row['source'],
    'isMock': row['is_mock'],
  };
}

Map<String, Object?> _operationItem(Map<String, Object?> row) =>
    <String, Object?>{
      'id': row['task_id'],
      'title': row['title'],
      'note': row['note'],
      'priority': row['priority'],
      'category': row['category'],
      'kind': row['kind'],
      'status': row['status'],
      'bookingReference': row['booking_reference'],
      'fullName': row['full_name'],
      'accommodationName': row['accommodation_name'],
      'source': row['source'],
      'actor': row['actor'],
      'updatedAt': row['updated_at'],
      'isMock': row['is_mock'],
    };

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes'}
      .contains(value?.toString().trim().toLowerCase());
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
