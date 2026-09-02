import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics/owner_analytics.dart';
import '../models/project_conversation_history.dart';
import '../models/project_source_models.dart';
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
            'target_user_summary,business_summary,product_scope,'
            'integration_scope,acceptance_scope,created_at',
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
      final productScope =
          _map(spec['product_scope']) ?? const <String, dynamic>{};
      final integrationScope =
          _map(spec['integration_scope']) ?? const <String, dynamic>{};
      final acceptanceScope =
          _map(spec['acceptance_scope']) ?? const <String, dynamic>{};
      final proposalIntegrations = <String>[
        ..._stringList(integrationScope['payment']),
        ..._stringList(integrationScope['messaging']),
        ..._stringList(integrationScope['analytics']),
        ..._stringList(integrationScope['externalApis']),
        ..._stringList(integrationScope['providerRequirements']),
      ];

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
        productPromise: _optionalText(productScope['productPromise']),
        audiences: _stringList(productScope['audiences']),
        customerValue: _optionalText(productScope['customerValue']),
        ownerValue: _optionalText(productScope['ownerValue']),
        coreExperiences: _stringList(productScope['coreExperiences']),
        firstVersionCapabilities:
            _stringList(productScope['firstVersionCapabilities']),
        primaryWorkflows: _stringList(productScope['primaryWorkflows']),
        integrations: List<String>.unmodifiable(proposalIntegrations),
        successCriteria: _stringList(acceptanceScope['successCriteria']),
        reviewAssurance: _optionalText(acceptanceScope['reviewAssurance']),
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

  Future<ProjectSourceTree> loadSourceTree({
    required String projectId,
    required String versionId,
  }) async {
    final data = await _invokeSourceFiles(
      projectId: projectId,
      versionId: versionId,
      operation: 'tree',
    );
    try {
      return ProjectSourceTree.fromJson(data);
    } on FormatException {
      throw const ProjectExperienceException(
        'Pandora returned an unreadable source tree.',
      );
    }
  }

  Future<ProjectSourceFile> loadSourceFile({
    required String projectId,
    required String versionId,
    required String path,
  }) async {
    final data = await _invokeSourceFiles(
      projectId: projectId,
      versionId: versionId,
      operation: 'read',
      path: path,
    );
    try {
      return ProjectSourceFile.fromJson(data);
    } on FormatException {
      throw const ProjectExperienceException(
        'Pandora returned an unreadable source file.',
      );
    }
  }

  Future<ProjectSourceSearchResult> searchSourceFiles({
    required String projectId,
    required String versionId,
    required String query,
  }) async {
    final data = await _invokeSourceFiles(
      projectId: projectId,
      versionId: versionId,
      operation: 'search',
      query: query,
    );
    try {
      return ProjectSourceSearchResult.fromJson(data);
    } on FormatException {
      throw const ProjectExperienceException(
        'Pandora returned unreadable source search results.',
      );
    }
  }

  Future<Uint8List> exportSourceZip({
    required String projectId,
    required String versionId,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before exporting source.',
      );
    }
    try {
      final response = await _client.functions.invoke(
        'pandora-source-files',
        body: <String, Object?>{
          'projectId': projectId,
          'versionId': versionId,
          'operation': 'export',
        },
      );
      final data = response.data;
      final Uint8List bytes;
      if (data is Uint8List && data.isNotEmpty) {
        bytes = data;
      } else if (data is List<int> && data.isNotEmpty) {
        bytes = Uint8List.fromList(data);
      } else {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable source export.',
        );
      }
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.sourceAccessGranted,
          projectId: projectId,
          projectVersionId: versionId,
          status: 'export',
        ),
      );
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.sourceExported,
          projectId: projectId,
          projectVersionId: versionId,
          count: bytes.length,
          status: 'export',
        ),
      );
      return bytes;
    } on ProjectExperienceException {
      rethrow;
    } on FunctionException catch (error) {
      throw ProjectExperienceException(
        _sourceFunctionMessage(error),
      );
    }
  }

  Future<Map<String, Object?>> _invokeSourceFiles({
    required String projectId,
    required String versionId,
    required String operation,
    String? path,
    String? query,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before opening source.',
      );
    }
    try {
      final response = await _client.functions.invoke(
        'pandora-source-files',
        body: <String, Object?>{
          'projectId': projectId,
          'versionId': versionId,
          'operation': operation,
          if (path != null) 'path': path,
          if (query != null) 'query': query,
        },
      );
      final data = _map(response.data);
      if (data == null ||
          _text(data['projectId']).toLowerCase() != projectId.toLowerCase() ||
          _text(data['versionId']).toLowerCase() != versionId.toLowerCase()) {
        throw const ProjectExperienceException(
          'Pandora rejected mismatched source evidence.',
        );
      }
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.sourceAccessGranted,
          projectId: projectId,
          projectVersionId: versionId,
          status: operation,
        ),
      );
      return Map<String, Object?>.from(data);
    } on ProjectExperienceException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map &&
          _text(details['code']) == 'SOURCE_ENTITLEMENT_REQUIRED') {
        unawaited(
          OwnerAnalytics.shared.capture(
            OwnerAnalyticsEvent.sourcePaywallViewed,
            projectId: projectId,
            projectVersionId: versionId,
            status: operation,
          ),
        );
      }
      throw ProjectExperienceException(
        _sourceFunctionMessage(error),
      );
    }
  }

  String _sourceFunctionMessage(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final code = _text(details['code']);
      final plainMessage = _optionalText(details['plainMessage']);
      if (code == 'SOURCE_ENTITLEMENT_REQUIRED') {
        return 'Source files are available with source access.';
      }
      if (plainMessage != null) return plainMessage;
    }
    return 'Pandora could not open source files right now.';
  }

  Future<List<ProjectConversationHistoryItem>> loadProjectConversation({
    required String projectId,
    int limit = 50,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before opening project history.',
      );
    }
    if (limit < 1 || limit > 100) {
      throw const ProjectExperienceException(
        'Pandora rejected an invalid history request.',
      );
    }
    try {
      final raw = await _client.rpc(
        'pandora_get_project_conversation_v1',
        params: <String, Object?>{
          'p_project_id': projectId,
          'p_limit': limit,
          'p_before_occurred_at': null,
          'p_before_item_id': null,
        },
      );
      if (raw is! List) {
        throw const ProjectExperienceException(
          'Pandora returned unreadable project history.',
        );
      }
      final items = <ProjectConversationHistoryItem>[];
      for (final row in raw) {
        final mapped = _map(row);
        if (mapped == null) {
          throw const ProjectExperienceException(
            'Pandora returned unreadable project history.',
          );
        }
        try {
          items.add(
            ProjectConversationHistoryItem.fromJson(
              Map<String, Object?>.from(mapped),
              expectedProjectId: projectId,
              expectedOrganizationId: _organizationId,
            ),
          );
        } on FormatException {
          throw const ProjectExperienceException(
            'Pandora rejected mismatched project history.',
          );
        }
      }
      items.sort((left, right) {
        final time = left.occurredAt.compareTo(right.occurredAt);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
      return List<ProjectConversationHistoryItem>.unmodifiable(items);
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not read project history right now.',
      );
    }
  }

  Future<String?> findBuildStreamId({
    required String projectId,
    required String buildJobId,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before reopening this build.',
      );
    }
    try {
      final row = await _client
          .from('pandora_build_stream_sessions')
          .select('id,organization_id,project_id,build_job_id,created_at')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('build_job_id', buildJobId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      if (_text(row['organization_id']) != _organizationId ||
          _text(row['project_id']) != projectId ||
          _text(row['build_job_id']) != buildJobId) {
        throw const ProjectExperienceException(
          'Pandora rejected a mismatched build stream.',
        );
      }
      return _requiredText(row['id']);
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not reopen this build right now.',
      );
    }
  }

  Future<Map<String, Object?>?> loadLatestPublishReceipt({
    required String projectId,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before reading this project history.',
      );
    }
    try {
      final raw = await _client.rpc(
        'pandora_get_project_conversation_v1',
        params: <String, Object?>{
          'p_project_id': projectId,
          'p_limit': 50,
        },
      );
      if (raw is! List) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable project history.',
        );
      }

      Map<String, Object?>? latest;
      DateTime? latestAt;
      for (final item in raw) {
        final row = _map(item);
        if (row == null || _text(row['kind']) != 'PUBLISH_RECEIPT') {
          continue;
        }
        final occurredAt =
            DateTime.tryParse(_text(row['occurred_at']))?.toUtc();
        final versionId = _optionalText(row['project_version_id']);
        final verificationRunId = _optionalText(row['verification_run_id']);
        final deploymentId = _optionalText(row['deployment_id']);
        final conversationItemId = _optionalText(row['conversation_item_id']);
        if (occurredAt == null ||
            versionId == null ||
            verificationRunId == null ||
            deploymentId == null ||
            conversationItemId == null) {
          continue;
        }
        if (latestAt != null && !occurredAt.isAfter(latestAt)) continue;
        final payload =
            _map(row['display_payload']) ?? const <String, dynamic>{};
        final rawVersion = payload['version'];
        final versionNumber = rawVersion is num
            ? rawVersion.toInt()
            : int.tryParse(rawVersion?.toString() ?? '');
        latestAt = occurredAt;
        latest = <String, Object?>{
          'conversationItemId': conversationItemId,
          'title': _text(row['title'], fallback: 'Live · Verified'),
          'summary': _text(
            row['summary'],
            fallback: 'Published and verified live.',
          ),
          'status': _text(row['status'], fallback: 'Live'),
          'projectVersionId': versionId,
          'verificationRunId': verificationRunId,
          'deploymentId': deploymentId,
          'occurredAt': occurredAt.toIso8601String(),
          'publishedAt': _optionalText(payload['publishedAt']) ??
              occurredAt.toIso8601String(),
          'versionNumber': versionNumber,
        };
      }
      return latest;
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not read the verified publish receipt right now.',
      );
    }
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
      final hostedPreview = _map(data['hostedPreview']);
      final previewDeploymentId =
          _optionalText(hostedPreview?['deploymentId'])?.toLowerCase();
      final sourceSha256 =
          _optionalText(hostedPreview?['sourceSha256'])?.toLowerCase();
      if (hostedPreview != null &&
          (previewDeploymentId == null ||
              !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
                  .hasMatch(previewDeploymentId) ||
              sourceSha256 == null ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha256))) {
        throw const ProjectExperienceException(
          'Pandora returned an unreadable preview.',
        );
      }
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
          if (previewDeploymentId != null)
            'previewDeploymentId': previewDeploymentId,
          if (sourceSha256 != null) 'sourceSha256': sourceSha256,
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
    this.productPromise,
    this.audiences = const <String>[],
    this.customerValue,
    this.ownerValue,
    this.coreExperiences = const <String>[],
    this.firstVersionCapabilities = const <String>[],
    this.primaryWorkflows = const <String>[],
    this.integrations = const <String>[],
    this.successCriteria = const <String>[],
    this.reviewAssurance,
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
    required String? productPromise,
    required List<String> audiences,
    required String? customerValue,
    required String? ownerValue,
    required List<String> coreExperiences,
    required List<String> firstVersionCapabilities,
    required List<String> primaryWorkflows,
    required List<String> integrations,
    required List<String> successCriteria,
    required String? reviewAssurance,
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
        productPromise: productPromise,
        audiences: List<String>.unmodifiable(audiences),
        customerValue: customerValue,
        ownerValue: ownerValue,
        coreExperiences: List<String>.unmodifiable(coreExperiences),
        firstVersionCapabilities:
            List<String>.unmodifiable(firstVersionCapabilities),
        primaryWorkflows: List<String>.unmodifiable(primaryWorkflows),
        integrations: List<String>.unmodifiable(integrations),
        successCriteria: List<String>.unmodifiable(successCriteria),
        reviewAssurance: reviewAssurance,
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
  final String? productPromise;
  final List<String> audiences;
  final String? customerValue;
  final String? ownerValue;
  final List<String> coreExperiences;
  final List<String> firstVersionCapabilities;
  final List<String> primaryWorkflows;
  final List<String> integrations;
  final List<String> successCriteria;
  final String? reviewAssurance;
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

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return List<String>.unmodifiable(
    value.map(_text).where((item) => item.isNotEmpty),
  );
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
