import 'package:supabase_flutter/supabase_flutter.dart';

enum EurofishSurface {
  commandCenter,
  commercial,
  importOperations,
  aquaculture,
  floriculture,
  customers,
  suppliers,
  compliance,
  finance,
  evidence,
  integrations,
}

extension EurofishSurfaceContract on EurofishSurface {
  String get rpcName => switch (this) {
        EurofishSurface.commandCenter => 'overview',
        EurofishSurface.commercial => 'commercial',
        EurofishSurface.importOperations => 'import_operations',
        EurofishSurface.aquaculture => 'aquaculture',
        EurofishSurface.floriculture => 'floriculture',
        EurofishSurface.customers => 'customers',
        EurofishSurface.suppliers => 'suppliers',
        EurofishSurface.compliance => 'compliance',
        EurofishSurface.finance => 'finance',
        EurofishSurface.evidence => 'evidence',
        EurofishSurface.integrations => 'integrations',
      };

  String get label => switch (this) {
        EurofishSurface.commandCenter => 'Command Center',
        EurofishSurface.commercial => 'Commercial',
        EurofishSurface.importOperations => 'Import Operations',
        EurofishSurface.aquaculture => 'Aquaculture',
        EurofishSurface.floriculture => 'Floriculture',
        EurofishSurface.customers => 'Customers',
        EurofishSurface.suppliers => 'Suppliers',
        EurofishSurface.compliance => 'Compliance',
        EurofishSurface.finance => 'Finance',
        EurofishSurface.evidence => 'Evidence & Documents',
        EurofishSurface.integrations => 'Integrations & Admin',
      };
}

class EurofishWorkspaceException implements Exception {
  const EurofishWorkspaceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EurofishWorkspaceSnapshot {
  const EurofishWorkspaceSnapshot({
    required this.projectKey,
    required this.memoryNamespace,
    required this.surface,
    required this.profile,
    required this.facts,
    required this.sources,
    required this.generatedAt,
  });

  final String projectKey;
  final String memoryNamespace;
  final String surface;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> facts;
  final List<Map<String, dynamic>> sources;
  final DateTime? generatedAt;

  factory EurofishWorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    return EurofishWorkspaceSnapshot(
      projectKey: _text(json['projectKey'], fallback: 'enterprise-eurofish'),
      memoryNamespace: _text(json['memoryNamespace'], fallback: 'real_life'),
      surface: _text(json['surface'], fallback: 'overview'),
      profile: _map(json['profile']),
      facts: _listOfMaps(json['facts']),
      sources: _listOfMaps(json['sources']),
      generatedAt: DateTime.tryParse(_text(json['generatedAt'])),
    );
  }

  Map<String, dynamic>? source(String key) {
    for (final item in sources) {
      if (_text(item['key']) == key) return item;
    }
    return null;
  }

  Map<String, dynamic>? fact(String key) {
    for (final item in facts) {
      if (_text(item['key']) == key) return item;
    }
    return null;
  }

  int get verifiedEvidenceCount => facts
      .where((item) => const {'verified', 'verified_historical'}
          .contains(_text(item['truthStatus'])))
      .length;

  int get needsVerificationCount => facts
      .where((item) =>
          _text(item['truthStatus']) == 'requires_current_verification')
      .length;

  int get connectedSourceCount => sources
      .where((item) =>
          const {'verified', 'connected'}.contains(_text(item['status'])))
      .length;

  int get notConnectedSourceCount =>
      sources.where((item) => _text(item['status']) == 'not_connected').length;
}

class EurofishWorkspaceApi {
  EurofishWorkspaceApi({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<EurofishWorkspaceSnapshot> load(EurofishSurface surface) async {
    try {
      final raw = await _client.rpc(
        'pandora_eurofish_workspace_v1',
        params: <String, Object?>{'p_surface': surface.rpcName},
      );
      final json = _map(raw);
      if (json.isEmpty) {
        throw const EurofishWorkspaceException(
          'Euro-Fish workspace returned no authoritative state.',
        );
      }
      return EurofishWorkspaceSnapshot.fromJson(json);
    } on PostgrestException {
      throw const EurofishWorkspaceException(
        'Euro-Fish workspace is temporarily unavailable.',
      );
    }
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

List<Map<String, dynamic>> _listOfMaps(Object? value) => value is List
    ? value.map(_map).where((item) => item.isNotEmpty).toList(growable: false)
    : const <Map<String, dynamic>>[];

String _text(Object? value, {String fallback = ''}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}
