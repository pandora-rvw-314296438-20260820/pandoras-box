import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/idempotency_key.dart';
import 'project_build_stream_cursor_store.dart';

class ProjectExperienceApi {
  ProjectExperienceApi({
    required SupabaseClient client,
    required String organizationId,
    IdempotencyKeyFactory? idempotencyKeys,
    ProjectBuildStreamCursorStore? cursorStore,
  })  : _client = client,
        _organizationId = organizationId,
        _keys = idempotencyKeys ?? IdempotencyKeyFactory(),
        _cursorStore = cursorStore ??
            const SharedPreferencesProjectBuildStreamCursorStore();

  final SupabaseClient _client;
  final String _organizationId;
  final IdempotencyKeyFactory _keys;
  final ProjectBuildStreamCursorStore _cursorStore;
  final Map<String, DateTime> _lastCompilationRequest = <String, DateTime>{};

  Future<String> submitIntent({
    required String projectId,
    required String intentText,
    String intentKind = 'build',
    String? idempotencyKey,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const ProjectExperienceException(
        'Please sign in again before changing this project.',
      );
    }
    final text = intentText.trim();
    if (text.isEmpty) {
      throw const ProjectExperienceException(
        'Tell Pandora what you want to build.',
      );
    }
    final key = idempotencyKey ?? _keys.create('project-intent');
    try {
      final result = await _client
          .from('pandora_project_intents')
          .insert(<String, Object?>{
            'organization_id': _organizationId,
            'project_id': projectId,
            'requester_id': userId,
            'intent_kind': intentKind,
            'intent_text': text,
            'source': 'customer',
            'idempotency_key': key,
            'provenance': const <String, Object?>{
              'surface': 'pandora_mobile_simple_mode',
            },
          })
          .select('id')
          .single();
      return _requiredText(result['id']);
    } on PostgrestException catch (error) {
      if (error.code != '23505') {
        throw const ProjectExperienceException(
          'Pandora could not save that request right now.',
        );
      }
      final existing = await _client
          .from('pandora_project_intents')
          .select('id')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('idempotency_key', key)
          .maybeSingle();
      if (existing == null) {
        throw const ProjectExperienceException(
          'Pandora could not confirm that request yet.',
        );
      }
      return _requiredText(existing['id']);
    }
  }

  Future<OwnerProjectUnderstanding> understanding({
    required String projectId,
    required String expectedSourceIntentId,
  }) async {
    try {
      final spec = await _client
          .from('pandora_project_specs')
          .select(
            'id,version,status,source_intent_id,project_type,'
            'target_user_summary,business_summary,created_at',
          )
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();

      if (spec == null ||
          _text(spec['source_intent_id']) != expectedSourceIntentId) {
        await _ensureCompilation(expectedSourceIntentId);
        return const OwnerProjectUnderstanding.waiting();
      }

      final status = _text(spec['status']);
      if (status == 'rejected') {
        return const OwnerProjectUnderstanding.rejected();
      }
      if (status != 'active') {
        await _ensureCompilation(expectedSourceIntentId);
        return const OwnerProjectUnderstanding.waiting();
      }

      final specId = _requiredText(spec['id']);
      final projectState = await _client
          .from('projectos_projects')
          .select('name,config')
          .eq('organization_id', _organizationId)
          .eq('id', projectId)
          .maybeSingle();
      if (projectState == null) {
        throw const ProjectExperienceException(
          'Pandora could not find that project right now.',
        );
      }
      final rawConfig = projectState['config'];
      final config = rawConfig is Map ? rawConfig : const <String, Object?>{};
      final rawJourney = config['customerJourney'];
      final journey =
          rawJourney is Map ? rawJourney : const <String, Object?>{};
      final distilledSummary = _optionalText(journey['intentSummary']);

      final objectives = await _client
          .from('pandora_project_business_objectives')
          .select('objective,desired_outcome')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('project_spec_id', specId)
          .order('ordinal')
          .limit(3);
      final requirements = await _client
          .from('pandora_project_requirements')
          .select('statement,category,priority')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('project_spec_id', specId)
          .order('category')
          .limit(8);

      return OwnerProjectUnderstanding.ready(
        specId: specId,
        version: _int(spec['version']),
        projectName: _text(projectState['name'], fallback: 'Project'),
        intentSummary: distilledSummary,
        projectType: _text(spec['project_type'], fallback: 'Project'),
        targetUsers: _optionalText(spec['target_user_summary']),
        businessSummary: _optionalText(spec['business_summary']),
        objectives: <String>[
          for (final row in objectives)
            if (_text(row['desired_outcome']).isNotEmpty)
              _text(row['desired_outcome'])
            else if (_text(row['objective']).isNotEmpty)
              _text(row['objective']),
        ],
        requirements: <String>[
          for (final row in requirements)
            if (_text(row['statement']).isNotEmpty) _text(row['statement']),
        ],
        compiledAt: DateTime.tryParse(_text(spec['created_at'])),
      );
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not refresh its understanding right now.',
      );
    }
  }

  Future<String> renameProject({
    required String projectId,
    required String name,
  }) async {
    final nextName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (nextName.length < 2 ||
        nextName.length > 80 ||
        nextName.contains('\n')) {
      throw const ProjectExperienceException(
        'Use a short project name between 2 and 80 characters.',
      );
    }
    try {
      final updated = await _client
          .from('projectos_projects')
          .update(<String, Object?>{
            'name': nextName,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('organization_id', _organizationId)
          .eq('id', projectId)
          .select('name')
          .maybeSingle();
      if (updated == null) {
        throw const ProjectExperienceException(
          'Pandora could not rename that project right now.',
        );
      }
      return _requiredText(updated['name']);
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not rename that project right now.',
      );
    }
  }

  Future<ProjectBuildStart> requestBuild({
    required String projectId,
    required String idempotencyKey,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before building this project.',
      );
    }
    try {
      final result = await _client.functions.invoke(
        'pandora-project-source-generator',
        body: <String, Object?>{
          'projectId': projectId,
          'idempotencyKey': idempotencyKey,
        },
      );
      final data = result.data;
      if (data is! Map) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable build response.',
        );
      }
      if (data['ok'] == false && data['state'] == 'blocked') {
        throw const ProjectExperienceException(
          'Pandora found something to resolve before this build can start.',
        );
      }
      final streamId = _optionalText(data['streamId']);
      if (streamId == null) {
        throw const ProjectExperienceException(
          'The build plan changed before coding started. Refresh the proposal and build it again.',
        );
      }
      return ProjectBuildStart(
        streamId: streamId,
        state: _text(data['state'], fallback: 'working'),
        buildJobId: _optionalText(data['buildJobId']),
        projectVersionId: _optionalText(data['projectVersionId']),
      );
    } on ProjectExperienceException {
      rethrow;
    } on FunctionException {
      throw const ProjectExperienceException(
        'Pandora could not start this build right now.',
      );
    }
  }

  Stream<List<ProjectBuildStreamEvent>> watchBuildStream({
    required String projectId,
    required String streamId,
  }) {
    return _client
        .from('pandora_build_stream_events')
        .stream(primaryKey: const <String>['id'])
        .eq('stream_id', streamId)
        .order('sequence')
        .map((rows) {
          for (final row in rows) {
            if (_text(row['organization_id']) != _organizationId ||
                _text(row['project_id']) != projectId ||
                _text(row['stream_id']) != streamId) {
              throw const ProjectExperienceException(
                'Pandora rejected a mismatched build stream.',
              );
            }
          }
          final now = DateTime.now().toUtc();
          final events = rows
              .map(ProjectBuildStreamEvent.fromJson)
              .where((event) =>
                  event.expiresAt == null || event.expiresAt!.isAfter(now))
              .toList()
            ..sort((left, right) => left.sequence.compareTo(right.sequence));
          return List<ProjectBuildStreamEvent>.unmodifiable(events);
        });
  }

  Future<ProjectBuildStreamReplay> replayBuildStream({
    required String projectId,
    required String streamId,
    int afterSequence = 0,
    int limit = 250,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before reopening this build.',
      );
    }
    if (afterSequence < 0 || limit < 1 || limit > 500) {
      throw const ProjectExperienceException(
        'Pandora rejected an invalid build replay request.',
      );
    }
    try {
      final raw = await _client.rpc(
        'pandora_build_stream_replay_v2',
        params: <String, Object?>{
          'p_stream_id': streamId,
          'p_after_sequence': afterSequence,
          'p_limit': limit,
        },
      );
      final data = _map(raw);
      final session = _map(data?['session']);
      if (data == null ||
          _int(data['protocolVersion']) != 2 ||
          session == null ||
          _text(session['streamId']) != streamId ||
          _text(session['organizationId']) != _organizationId ||
          _text(session['projectId']) != projectId) {
        throw const ProjectExperienceException(
          'Pandora rejected a mismatched build replay.',
        );
      }

      final rawEvents = data['events'];
      if (rawEvents is! List) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable build replay.',
        );
      }
      final events = <ProjectBuildStreamEvent>[];
      for (final rawEvent in rawEvents) {
        final eventMap = _map(rawEvent);
        if (eventMap == null) {
          throw const ProjectExperienceException(
            'Pandora returned an unreadable build replay.',
          );
        }
        events.add(ProjectBuildStreamEvent.fromJson(eventMap));
      }
      events.sort((left, right) => left.sequence.compareTo(right.sequence));
      for (var index = 1; index < events.length; index += 1) {
        if (events[index].sequence == events[index - 1].sequence) {
          throw const ProjectExperienceException(
            'Pandora rejected a duplicate build replay sequence.',
          );
        }
      }

      final build = _map(data['build']);
      final durableSummary =
          _map(data['durableSummary']) ?? const <String, dynamic>{};
      return ProjectBuildStreamReplay(
        events: List<ProjectBuildStreamEvent>.unmodifiable(events),
        watermarkSequence: _int(data['watermarkSequence']),
        oldestRetainedSequence: _optionalInt(data['oldestRetainedSequence']),
        historyGapDueToRetention: data['historyGapDueToRetention'] == true,
        hasMore: data['hasMore'] == true,
        streamStatus: _text(session['status'], fallback: 'building'),
        buildStatus: _optionalText(build?['status']),
        buildStage: _optionalText(build?['stage']),
        buildJobId: _optionalText(session['buildJobId']),
        projectVersionId: _optionalText(session['projectVersionId']),
        publicErrorCode: _optionalText(session['publicErrorCode']) ??
            _optionalText(build?['errorCode']),
        durableSummary: Map<String, Object?>.unmodifiable(
          durableSummary.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      );
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not reconcile this build right now.',
      );
    }
  }

  Stream<ProjectBuildStreamSnapshot> watchResilientBuildStream({
    required String projectId,
    required String streamId,
  }) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream<ProjectBuildStreamSnapshot>.error(
        const ProjectExperienceException(
          'Please sign in again before reopening this build.',
        ),
      );
    }

    final reconciler = ProjectBuildStreamReconciler();
    final controller = StreamController<ProjectBuildStreamSnapshot>();
    StreamSubscription<List<ProjectBuildStreamEvent>>? subscription;
    Timer? retryTimer;
    var closed = false;
    var reconciling = false;
    var reconnectAttempt = 0;

    Future<void> cancelLiveSubscription() async {
      await subscription?.cancel();
      subscription = null;
    }

    Future<void> persistCursor() async {
      final sequence = reconciler.latestSequence;
      if (sequence < 1) return;
      await _cursorStore.write(
        userId: userId,
        organizationId: _organizationId,
        projectId: projectId,
        streamId: streamId,
        sequence: sequence,
      );
    }

    Future<void> reconcile({bool reconnecting = false}) async {
      if (closed || reconciling) return;
      reconciling = true;
      try {
        if (!reconciler.hasSeededCursor) {
          final stored = await _cursorStore.read(
            userId: userId,
            organizationId: _organizationId,
            projectId: projectId,
            streamId: streamId,
          );
          reconciler.seedCursor(stored);
        }

        var pages = 0;
        while (!closed) {
          pages += 1;
          if (pages > 20) {
            throw const ProjectExperienceException(
              'Pandora stopped an unbounded build replay.',
            );
          }
          final before = reconciler.latestSequence;
          final replay = await replayBuildStream(
            projectId: projectId,
            streamId: streamId,
            afterSequence: before,
            limit: 500,
          );
          final snapshot = reconciler.mergeReplay(
            replay,
            reconnecting: reconnecting,
          );
          await persistCursor();
          if (!closed) controller.add(snapshot);
          if (!replay.hasMore) break;
          if (reconciler.latestSequence <= before) {
            throw const ProjectExperienceException(
              'Pandora rejected a non-advancing build replay.',
            );
          }
        }
        reconnectAttempt = 0;
      } catch (error, stackTrace) {
        if (!closed) controller.addError(error, stackTrace);
      } finally {
        reconciling = false;
      }
    }

    Future<void> handleLive(List<ProjectBuildStreamEvent> events) async {
      if (closed) return;
      final snapshot = reconciler.mergeLive(events);
      if (snapshot.requiresReplay) {
        await reconcile(reconnecting: true);
        return;
      }
      await persistCursor();
      if (!closed) controller.add(snapshot);
    }

    void subscribe() {
      if (closed) return;
      subscription = watchBuildStream(
        projectId: projectId,
        streamId: streamId,
      ).listen(
        (events) => unawaited(handleLive(events)),
        onError: (Object error, StackTrace stackTrace) {
          if (closed) return;
          controller.add(reconciler.snapshot(reconnecting: true));
          controller.addError(error, stackTrace);
          if (retryTimer?.isActive == true) return;
          final slot = reconnectAttempt > 3 ? 3 : reconnectAttempt;
          final delayMs = const <int>[500, 1000, 2000, 4000][slot];
          if (reconnectAttempt < 3) reconnectAttempt += 1;
          retryTimer = Timer(Duration(milliseconds: delayMs), () {
            if (closed) return;
            final current = subscription;
            subscription = null;
            if (current != null) unawaited(current.cancel());
            unawaited(reconcile(reconnecting: true));
            subscribe();
          });
        },
        onDone: () {
          if (closed || retryTimer?.isActive == true) return;
          final slot = reconnectAttempt > 3 ? 3 : reconnectAttempt;
          final delayMs = const <int>[500, 1000, 2000, 4000][slot];
          if (reconnectAttempt < 3) reconnectAttempt += 1;
          retryTimer = Timer(Duration(milliseconds: delayMs), () {
            if (closed) return;
            unawaited(reconcile(reconnecting: true));
            subscribe();
          });
        },
        cancelOnError: false,
      );
    }

    controller.onListen = () {
      subscribe();
      unawaited(reconcile());
    };
    controller.onCancel = () async {
      closed = true;
      retryTimer?.cancel();
      await cancelLiveSubscription();
      if (!controller.isClosed) {
        await controller.close();
      }
    };
    return controller.stream;
  }

  Future<List<Map<String, Object?>>> loadExactPreviewFiles({
    required String projectId,
    required String versionId,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before opening this preview.',
      );
    }
    try {
      final response = await _client.functions.invoke(
        'pandora-preview-content',
        body: <String, Object?>{
          'projectId': projectId.trim(),
          'versionId': versionId.trim(),
        },
      );
      final data = response.data;
      if (data is! Map || data['kind'] != 'pandora.mobile-preview-bundle.v1') {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable preview.',
        );
      }
      final responseProjectId = _text(data['projectId']).toLowerCase();
      final responseVersionId = _text(data['versionId']).toLowerCase();
      final artifactDigest = _text(data['artifactDigest']).toLowerCase();
      final requestedProjectId = projectId.trim().toLowerCase();
      final requestedVersionId = versionId.trim().toLowerCase();
      if (responseProjectId != requestedProjectId ||
          responseVersionId != requestedVersionId ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactDigest)) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable preview.',
        );
      }
      final rawFiles = data['files'];
      if (rawFiles is! List || rawFiles.isEmpty || rawFiles.length > 1000) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable preview.',
        );
      }
      final files = <Map<String, Object?>>[];
      for (final raw in rawFiles) {
        if (raw is! Map) {
          throw const ProjectExperienceException(
            'Pandora returned an unreadable preview.',
          );
        }
        final file = raw['file'];
        final mimeType = raw['mimeType'];
        final dataBase64 = raw['dataBase64'];
        final byteSize = raw['byteSize'];
        final fileDigest = _text(raw['sha256']).toLowerCase();
        if (file is! String ||
            file.trim().isEmpty ||
            mimeType is! String ||
            mimeType.trim().isEmpty ||
            dataBase64 is! String ||
            dataBase64.isEmpty ||
            byteSize is! int ||
            byteSize < 1 ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(fileDigest)) {
          throw const ProjectExperienceException(
            'Pandora returned an unreadable preview.',
          );
        }
        files.add(<String, Object?>{
          'file': file.trim(),
          'mimeType': mimeType.trim(),
          'dataBase64': dataBase64,
          'byteSize': byteSize,
          'sha256': fileDigest,
          'artifactDigest': artifactDigest,
          'previewProjectId': responseProjectId,
          'previewVersionId': responseVersionId,
        });
      }
      return files;
    } on ProjectExperienceException {
      rethrow;
    } on FunctionException {
      throw const ProjectExperienceException(
        'Pandora could not open this preview right now.',
      );
    }
  }

  Future<void> _ensureCompilation(String sourceIntentId) async {
    final now = DateTime.now();
    final last = _lastCompilationRequest[sourceIntentId];
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastCompilationRequest[sourceIntentId] = now;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _client.functions.invoke(
          'pandora-project-spec-compiler',
          body: <String, Object?>{'intentId': sourceIntentId},
        ).timeout(const Duration(seconds: 12));
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
        }
      }
    }

    // Do not hold the cooldown after a failed trigger. The durable intent is
    // still authoritative, and the next owner poll should be allowed to
    // retrigger compilation immediately instead of appearing stuck.
    _lastCompilationRequest.remove(sourceIntentId);
  }

  void beginAuthenticatedIdentityEpoch() {
    _lastCompilationRequest.clear();
  }
}

class ProjectBuildStart {
  const ProjectBuildStart({
    required this.streamId,
    required this.state,
    this.buildJobId,
    this.projectVersionId,
  });

  final String streamId;
  final String state;
  final String? buildJobId;
  final String? projectVersionId;
}

class ProjectBuildStreamEvent {
  const ProjectBuildStreamEvent({
    required this.id,
    required this.sequence,
    required this.eventType,
    required this.safePayload,
    required this.createdAt,
    this.eventSchemaVersion = 2,
    this.retentionClass,
    this.filePath,
    this.contentChunk,
    this.buildJobId,
    this.expiresAt,
  });

  factory ProjectBuildStreamEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['safe_payload'] ?? json['safePayload'];
    final payload = rawPayload is Map
        ? Map<String, Object?>.unmodifiable(
            rawPayload.map((key, value) => MapEntry(key.toString(), value)),
          )
        : const <String, Object?>{};
    final sequence = _optionalInt(json['sequence']);
    final id = _optionalInt(json['id']) ?? sequence;
    final createdAt = DateTime.tryParse(
      _text(json['created_at'] ?? json['createdAt']),
    );
    final expiresAt = DateTime.tryParse(
      _text(json['expires_at'] ?? json['expiresAt']),
    );
    if (id == null || sequence == null || sequence < 1 || createdAt == null) {
      throw const FormatException('Invalid build stream event.');
    }
    return ProjectBuildStreamEvent(
      id: id,
      sequence: sequence,
      eventSchemaVersion: _optionalInt(
              json['event_schema_version'] ?? json['eventSchemaVersion']) ??
          1,
      eventType: _requiredText(json['event_type'] ?? json['eventType']),
      retentionClass:
          _optionalText(json['retention_class'] ?? json['retentionClass']),
      safePayload: payload,
      createdAt: createdAt.toUtc(),
      expiresAt: expiresAt?.toUtc(),
      filePath: _optionalText(json['file_path'] ?? json['filePath']),
      contentChunk: (json['content_chunk'] ?? json['contentChunk']) is String
          ? (json['content_chunk'] ?? json['contentChunk']) as String
          : null,
      buildJobId: _optionalText(json['build_job_id'] ?? json['buildJobId']),
    );
  }

  final int id;
  final int sequence;
  final int eventSchemaVersion;
  final String eventType;
  final String? retentionClass;
  final String? filePath;
  final String? contentChunk;
  final String? buildJobId;
  final Map<String, Object?> safePayload;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

class ProjectBuildStreamReplay {
  const ProjectBuildStreamReplay({
    required this.events,
    required this.watermarkSequence,
    required this.oldestRetainedSequence,
    required this.historyGapDueToRetention,
    required this.hasMore,
    required this.streamStatus,
    required this.buildStatus,
    required this.buildStage,
    required this.buildJobId,
    required this.projectVersionId,
    required this.publicErrorCode,
    required this.durableSummary,
  });

  final List<ProjectBuildStreamEvent> events;
  final int watermarkSequence;
  final int? oldestRetainedSequence;
  final bool historyGapDueToRetention;
  final bool hasMore;
  final String streamStatus;
  final String? buildStatus;
  final String? buildStage;
  final String? buildJobId;
  final String? projectVersionId;
  final String? publicErrorCode;
  final Map<String, Object?> durableSummary;
}

class ProjectBuildStreamSnapshot {
  const ProjectBuildStreamSnapshot({
    required this.events,
    required this.latestSequence,
    required this.historyGapDueToRetention,
    required this.requiresReplay,
    required this.reconnecting,
    required this.streamStatus,
    required this.buildStatus,
    required this.buildStage,
    required this.buildJobId,
    required this.projectVersionId,
    required this.publicErrorCode,
    required this.durableSummary,
  });

  const ProjectBuildStreamSnapshot.empty()
      : events = const <ProjectBuildStreamEvent>[],
        latestSequence = 0,
        historyGapDueToRetention = false,
        requiresReplay = false,
        reconnecting = false,
        streamStatus = 'building',
        buildStatus = null,
        buildStage = null,
        buildJobId = null,
        projectVersionId = null,
        publicErrorCode = null,
        durableSummary = const <String, Object?>{};

  final List<ProjectBuildStreamEvent> events;
  final int latestSequence;
  final bool historyGapDueToRetention;
  final bool requiresReplay;
  final bool reconnecting;
  final String streamStatus;
  final String? buildStatus;
  final String? buildStage;
  final String? buildJobId;
  final String? projectVersionId;
  final String? publicErrorCode;
  final Map<String, Object?> durableSummary;
}

class ProjectBuildStreamReconciler {
  ProjectBuildStreamReconciler({this.maxBufferedEvents = 800})
      : assert(maxBufferedEvents > 0);

  final int maxBufferedEvents;
  final Map<int, ProjectBuildStreamEvent> _events =
      <int, ProjectBuildStreamEvent>{};
  var _latestSequence = 0;
  var _historyGapDueToRetention = false;
  var _hasSeededCursor = false;
  var _streamStatus = 'building';
  String? _buildStatus;
  String? _buildStage;
  String? _buildJobId;
  String? _projectVersionId;
  String? _publicErrorCode;
  Map<String, Object?> _durableSummary = const <String, Object?>{};

  int get latestSequence => _latestSequence;
  bool get hasSeededCursor => _hasSeededCursor;

  void seedCursor(int sequence) {
    _hasSeededCursor = true;
    if (sequence > _latestSequence) _latestSequence = sequence;
  }

  ProjectBuildStreamSnapshot mergeLive(
    List<ProjectBuildStreamEvent> incoming,
  ) {
    final ordered = List<ProjectBuildStreamEvent>.of(incoming)
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    var expected = _latestSequence + 1;
    var requiresReplay = false;
    for (final event in ordered) {
      if (event.sequence <= _latestSequence) continue;
      if (event.sequence != expected) {
        requiresReplay = true;
        break;
      }
      _events[event.sequence] = event;
      _latestSequence = event.sequence;
      expected = _latestSequence + 1;
    }
    _trim();
    return snapshot(requiresReplay: requiresReplay);
  }

  ProjectBuildStreamSnapshot mergeReplay(
    ProjectBuildStreamReplay replay, {
    bool reconnecting = false,
  }) {
    final initialRetentionGap = _latestSequence == 0 &&
        replay.watermarkSequence > 0 &&
        (replay.oldestRetainedSequence == null ||
            replay.oldestRetainedSequence! > 1);
    final retentionGap = replay.historyGapDueToRetention || initialRetentionGap;
    final ordered = List<ProjectBuildStreamEvent>.of(replay.events)
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    var expected = _latestSequence + 1;
    for (final event in ordered) {
      if (event.sequence <= _latestSequence) continue;
      if (event.sequence != expected && !retentionGap) {
        throw const FormatException('Build replay sequence gap.');
      }
      _events[event.sequence] = event;
      _latestSequence = event.sequence;
      expected = _latestSequence + 1;
    }
    if (retentionGap &&
        ordered.isEmpty &&
        replay.watermarkSequence > _latestSequence) {
      _latestSequence = replay.watermarkSequence;
    }
    if (replay.watermarkSequence < _latestSequence) {
      throw const FormatException('Build replay watermark regressed.');
    }

    _historyGapDueToRetention = _historyGapDueToRetention || retentionGap;
    _streamStatus = replay.streamStatus;
    _buildStatus = replay.buildStatus;
    _buildStage = replay.buildStage;
    _buildJobId = replay.buildJobId;
    _projectVersionId = replay.projectVersionId;
    _publicErrorCode = replay.publicErrorCode;
    _durableSummary = replay.durableSummary;
    _hasSeededCursor = true;
    _trim();
    return snapshot(
      reconnecting: reconnecting,
      requiresReplay: replay.hasMore,
    );
  }

  ProjectBuildStreamSnapshot snapshot({
    bool reconnecting = false,
    bool requiresReplay = false,
  }) {
    final ordered = _events.values.toList()
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    return ProjectBuildStreamSnapshot(
      events: List<ProjectBuildStreamEvent>.unmodifiable(ordered),
      latestSequence: _latestSequence,
      historyGapDueToRetention: _historyGapDueToRetention,
      requiresReplay: requiresReplay,
      reconnecting: reconnecting,
      streamStatus: _streamStatus,
      buildStatus: _buildStatus,
      buildStage: _buildStage,
      buildJobId: _buildJobId,
      projectVersionId: _projectVersionId,
      publicErrorCode: _publicErrorCode,
      durableSummary: _durableSummary,
    );
  }

  void _trim() {
    if (_events.length <= maxBufferedEvents) return;
    final keys = _events.keys.toList()..sort();
    final removeCount = _events.length - maxBufferedEvents;
    for (final key in keys.take(removeCount)) {
      _events.remove(key);
    }
  }
}

class ProjectExperienceException implements Exception {
  const ProjectExperienceException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum OwnerProjectUnderstandingState { waiting, ready, rejected }

class OwnerProjectUnderstanding {
  const OwnerProjectUnderstanding._({
    required this.state,
    this.specId,
    this.version,
    this.projectName,
    this.intentSummary,
    this.projectType,
    this.targetUsers,
    this.businessSummary,
    this.objectives = const <String>[],
    this.requirements = const <String>[],
    this.compiledAt,
  });

  const OwnerProjectUnderstanding.waiting()
      : this._(state: OwnerProjectUnderstandingState.waiting);

  const OwnerProjectUnderstanding.rejected()
      : this._(state: OwnerProjectUnderstandingState.rejected);

  factory OwnerProjectUnderstanding.ready({
    required String specId,
    required int version,
    required String projectName,
    required String? intentSummary,
    required String projectType,
    required String? targetUsers,
    required String? businessSummary,
    required List<String> objectives,
    required List<String> requirements,
    required DateTime? compiledAt,
  }) =>
      OwnerProjectUnderstanding._(
        state: OwnerProjectUnderstandingState.ready,
        specId: specId,
        version: version,
        projectName: projectName,
        intentSummary: intentSummary,
        projectType: projectType,
        targetUsers: targetUsers,
        businessSummary: businessSummary,
        objectives: List<String>.unmodifiable(objectives),
        requirements: List<String>.unmodifiable(requirements),
        compiledAt: compiledAt,
      );

  final OwnerProjectUnderstandingState state;
  final String? specId;
  final int? version;
  final String? projectName;
  final String? intentSummary;
  final String? projectType;
  final String? targetUsers;
  final String? businessSummary;
  final List<String> objectives;
  final List<String> requirements;
  final DateTime? compiledAt;

  bool get isReady => state == OwnerProjectUnderstandingState.ready;
}

String _text(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

String? _optionalText(Object? value) {
  final valueText = _text(value);
  return valueText.isEmpty ? null : valueText;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value == null) return null;
  return int.tryParse(value.toString());
}

Map<String, dynamic>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map(
    (key, item) => MapEntry(key.toString(), item),
  );
}

String _requiredText(Object? value) {
  final valueText = _text(value);
  if (valueText.isEmpty) {
    throw const ProjectExperienceException(
      'Pandora returned an unreadable project result.',
    );
  }
  return valueText;
}

int _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
