import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

class EnterpriseVisionRepository {
  const EnterpriseVisionRepository();

  SupabaseClient get _client => Supabase.instance.client;
  String get _organizationId => PandoraConfig.organizationId;

  Future<EnterpriseVisionSnapshot> load() async {
    final payload = await _client.rpc(
      'pandora_vision_overview_v1',
      params: <String, Object?>{'p_organization_id': _organizationId},
    );
    final map = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final cameras = _rows(map['cameras'])
        .map(EnterpriseVisionCamera.fromMap)
        .toList(growable: false);
    final events = _rows(map['latestEvents'])
        .map(EnterpriseVisionEvent.fromMap)
        .toList(growable: false);
    final alerts = _rows(map['latestAlerts'])
        .map(EnterpriseVisionAlert.fromMap)
        .toList(growable: false);
    return EnterpriseVisionSnapshot(
      cameras: cameras,
      events: events,
      alerts: alerts,
      openAlerts: _int(map['openAlerts']),
      events24h: _int(map['events24h']),
      incidentsOpen: _int(map['incidentsOpen']),
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
}

class EnterpriseVisionSnapshot {
  const EnterpriseVisionSnapshot({
    required this.cameras,
    required this.events,
    required this.alerts,
    required this.openAlerts,
    required this.events24h,
    required this.incidentsOpen,
  });

  final List<EnterpriseVisionCamera> cameras;
  final List<EnterpriseVisionEvent> events;
  final List<EnterpriseVisionAlert> alerts;
  final int openAlerts;
  final int events24h;
  final int incidentsOpen;

  int get liveAuthorizedCameras => cameras
      .where((camera) =>
          !camera.publicFeed &&
          camera.sourceStatus == 'live' &&
          camera.analysisEnabled)
      .length;
}

class EnterpriseVisionCamera {
  const EnterpriseVisionCamera({
    required this.id,
    required this.cameraKey,
    required this.displayName,
    required this.locationLabel,
    required this.sourceType,
    required this.sourceStatus,
    required this.analysisEnabled,
    required this.publicFeed,
    required this.biometricsEnabled,
    required this.anonymousTrackingEnabled,
    required this.lastFrameAt,
    required this.lastAnalysisAt,
  });

  factory EnterpriseVisionCamera.fromMap(Map<String, dynamic> row) =>
      EnterpriseVisionCamera(
        id: row['id']?.toString() ?? '',
        cameraKey: row['cameraKey']?.toString() ?? '',
        displayName: row['displayName']?.toString() ?? 'Camera',
        locationLabel: row['locationLabel']?.toString() ?? '',
        sourceType: row['sourceType']?.toString() ?? '',
        sourceStatus: row['sourceStatus']?.toString() ?? 'disconnected',
        analysisEnabled: row['analysisEnabled'] == true,
        publicFeed: row['publicFeed'] == true,
        biometricsEnabled: row['biometricsEnabled'] == true,
        anonymousTrackingEnabled: row['anonymousTrackingEnabled'] != false,
        lastFrameAt: row['lastFrameAt']?.toString() ?? '',
        lastAnalysisAt: row['lastAnalysisAt']?.toString() ?? '',
      );

  final String id;
  final String cameraKey;
  final String displayName;
  final String locationLabel;
  final String sourceType;
  final String sourceStatus;
  final bool analysisEnabled;
  final bool publicFeed;
  final bool biometricsEnabled;
  final bool anonymousTrackingEnabled;
  final String lastFrameAt;
  final String lastAnalysisAt;

  Map<String, String> get selection => <String, String>{
        'kind': 'vision_camera',
        'id': id,
        'cameraId': id,
        'cameraKey': cameraKey,
      };
}

class EnterpriseVisionEvent {
  const EnterpriseVisionEvent({
    required this.id,
    required this.cameraId,
    required this.eventType,
    required this.severity,
    required this.title,
    required this.description,
    required this.confidence,
    required this.startedAt,
    required this.humanState,
  });

  factory EnterpriseVisionEvent.fromMap(Map<String, dynamic> row) =>
      EnterpriseVisionEvent(
        id: row['id']?.toString() ?? '',
        cameraId: row['cameraId']?.toString() ?? '',
        eventType: row['eventType']?.toString() ?? 'activity',
        severity: row['severity']?.toString() ?? 'info',
        title: row['title']?.toString() ?? 'Vision event',
        description: row['description']?.toString() ?? '',
        confidence: double.tryParse(row['confidence']?.toString() ?? ''),
        startedAt: row['startedAt']?.toString() ?? '',
        humanState: row['humanState']?.toString() ?? 'machine',
      );

  final String id;
  final String cameraId;
  final String eventType;
  final String severity;
  final String title;
  final String description;
  final double? confidence;
  final String startedAt;
  final String humanState;
}

class EnterpriseVisionAlert {
  const EnterpriseVisionAlert({
    required this.id,
    required this.eventId,
    required this.cameraId,
    required this.severity,
    required this.title,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory EnterpriseVisionAlert.fromMap(Map<String, dynamic> row) =>
      EnterpriseVisionAlert(
        id: row['id']?.toString() ?? '',
        eventId: row['eventId']?.toString() ?? '',
        cameraId: row['cameraId']?.toString() ?? '',
        severity: row['severity']?.toString() ?? 'warning',
        title: row['title']?.toString() ?? 'Vision alert',
        message: row['message']?.toString() ?? '',
        status: row['status']?.toString() ?? 'open',
        createdAt: row['createdAt']?.toString() ?? '',
      );

  final String id;
  final String eventId;
  final String cameraId;
  final String severity;
  final String title;
  final String message;
  final String status;
  final String createdAt;
}
