import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_conversation_layer.dart';
import '../../app/pandora_dependencies.dart';
import '../../core/activity/pandora_activity_presentation_policy.dart';
import '../../core/activity/pandora_activity_projection.dart';
import '../../core/activity/pandora_activity_timeline_controller.dart';
import '../../core/activity/pandora_activity_timeline_view.dart';
import '../../core/data/pandora_activity_stream_api.dart';
import '../../core/data/pandora_character_api.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/device/pandora_calendar_action_executor.dart';
import '../../core/device/pandora_calendar_command.dart';
import '../../core/device/pandora_communication_action_executor.dart';
import '../../core/device/pandora_communication_command.dart';
import '../../core/local/pandora_device_activity_local_sync.dart';
import '../../core/local/pandora_local_state_cache.dart';
import '../../core/local/pandora_local_sync_coordinator.dart';
import '../../core/local_ai/pandora_local_ai.dart';
import '../../core/local_ai/pandora_local_ai_runtime.dart';
import '../../core/local_ai/plp_chat_fallback.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import 'pandora_model_picker.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../enterprise/plp_staff_task_action.dart';
import 'pandora_simple_ui.dart';

class AskPandoraScreen extends StatefulWidget {
  const AskPandoraScreen({
    super.key,
    this.initialPrompt,
    this.onHome,
    this.onProjects,
    this.onSearchChats,
    this.onMore,
    this.enterpriseContext,
    this.allowCharacterContext = true,
    this.allowProjectContext = true,
    this.shellOverlay = false,
    this.initialHistoryExpanded = true,
    this.onCoreNavigate,
    this.onHistoryVisibilityChanged,
  });

  final String? initialPrompt;
  final VoidCallback? onHome;
  final VoidCallback? onProjects;
  final VoidCallback? onSearchChats;
  final VoidCallback? onMore;
  final Map<String, Object?>? enterpriseContext;
  final bool allowCharacterContext;
  final bool allowProjectContext;
  final bool shellOverlay;
  final bool initialHistoryExpanded;
  final ValueChanged<PandoraIntelligenceHandoff>? onCoreNavigate;
  final ValueChanged<bool>? onHistoryVisibilityChanged;

  @override
  State<AskPandoraScreen> createState() => AskPandoraScreenState();
}

class AskPandoraScreenState extends State<AskPandoraScreen>
    with WidgetsBindingObserver {
  // CPU Qwen2.5 can legitimately spend more than 30 seconds in prompt prefill
  // before the first streamed token. Keep a bounded idle deadline, but do not
  // cancel a healthy on-device decode at the old 30-second wall.
  static const _localInferenceIdleTimeout = Duration(seconds: 120);

  final TextEditingController _objective = TextEditingController();
  final FocusNode _objectiveFocus = FocusNode();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _composerKey = GlobalKey();
  double _headerHeight = 0;
  double _composerHeight = 0;
  bool _overlayMeasureScheduled = false;
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  PandoraTextAttachment? _attachment;
  PandoraImageAttachment? _imageAttachment;
  PandoraProjectContext? _projectContext;
  PandoraCapabilityProvider? _serviceContext;
  PandoraCharacterProfile? _characterContext;
  String? _characterSessionId;
  PandoraCharacterApi? _characterApi;
  PandoraCharacterApi get _characterClient =>
      _characterApi ??= PandoraCharacterApi();
  String? _threadId;
  String? _pendingMessage;
  final PandoraActivityTimelineController _activityController =
      PandoraActivityTimelineController();
  String? _activeActivityJobId;
  bool _activityTheatreRequested = false;
  bool _activityTheatreSuppressed = false;
  bool _submitting = false;
  bool _localAiGenerating = false;
  bool _localAiPrewarmInFlight = false;
  bool _lastTurnUsedLocalAi = false;
  bool _teamAdministrationPending = false;
  bool _loadingThread = false;
  bool _localConversationRestoreStarted = false;
  bool _outcomeUnknown = false;
  String? _submissionKey;
  String? _error;
  bool _shellHistoryExpanded = false;
  PandoraChatModelSelection _modelSelection =
      const PandoraChatModelSelection.auto();
  PandoraIntelligenceMode _reasoningMode = PandoraIntelligenceMode.auto;
  String _modelLabel = 'Auto';
  PandoraChatModelPickerSnapshot? _pickerSnapshot;
  bool _pickerOpen = false;
  bool _pickerLocalAiEnabled = false;
  bool _pickerLocalAiAvailable = false;
  String? _pickerLocalAiModelName;
  bool _pickerStartAtEnd = false;

  bool get _isCommonWorkspace {
    final selected = widget.enterpriseContext?['selectedObject'];
    return selected is Map &&
        selected['adapterKey'] == 'enterprise_core_v1' &&
        const {'member', 'administrator'}.contains(selected['workspaceMode']);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activityController.addListener(_handleActivityTimelineChanged);
    unawaited(PandoraLocalAiPreference.load());
    _shellHistoryExpanded =
        widget.shellOverlay && widget.initialHistoryExpanded;
    final initial = widget.initialPrompt?.trim();
    if (initial != null && initial.isNotEmpty) {
      _objective.text = initial;
      _objective.selection = TextSelection.collapsed(offset: initial.length);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localConversationRestoreStarted) return;
    _localConversationRestoreStarted = true;
    unawaited(_restoreLocalConversation());
    if (_isPlpEnterpriseContext) {
      unawaited(_prewarmPlpLocalAiIfSafe());
    }
  }

  Future<void> _prewarmPlpLocalAiIfSafe() async {
    if (_localAiPrewarmInFlight) return;
    _localAiPrewarmInFlight = true;
    PandoraLocalAiStatus? probeStatus;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted || !_isPlpEnterpriseContext) return;
      final status = await PandoraLocalAi.instance.status();
      probeStatus = status;
      if (!status.supported || !status.configured) return;
      final decision = PandoraLocalAiRouter.decide(
        message: 'Prepare PLP local resort intelligence.',
        hasAttachment: false,
        hasProjectContext: true,
        hasSelectedCapability: false,
        hasCharacterContext: false,
        status: status,
      );
      if (!decision.useLocal) return;

      if (!status.loaded && !await PandoraLocalAi.instance.warm()) return;
      final warmed = await PandoraLocalAi.instance.status();
      unawaited(
        _recordLocalAiTurn(
          phase: 'prewarm',
          outcome: 'success',
          reason: 'model_ready_without_synthetic_generation',
          status: warmed,
        ),
      );
      PandoraLocalAiRuntime.instance.keepResident();
    } catch (error) {
      unawaited(
        _recordLocalAiTurn(
          phase: 'self_test',
          outcome: 'failed',
          reason: error.toString(),
          status: probeStatus,
        ),
      );
      await PandoraLocalAiRuntime.instance.unload();
      // A real user turn still continues through cloud if the local self-test
      // cannot prove the phone-local path.
    } finally {
      _localAiPrewarmInFlight = false;
    }
  }

  Future<void> _restoreLocalConversation() async {
    final localStore = PandoraDependencies.of(context).localStore;
    if (localStore == null) return;
    try {
      final cached = await PandoraLocalStateCache(localStore)
          .loadRecentConversation(threadIdentity: 'local-chat');
      if (!mounted ||
          cached.isEmpty ||
          _messages.isNotEmpty ||
          _threadId != null ||
          _pendingMessage != null) {
        return;
      }
      final restored = <_ChatMessage>[];
      for (final entry in cached) {
        final text = entry['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        if (entry['role'] == 'user') {
          restored.add(_ChatMessage.user(text));
        } else if (entry['role'] == 'pandora') {
          restored.add(_ChatMessage.pandora(text,
              coreNavigation: PandoraIntelligenceHandoff.inspectFromJson(
                  entry['inspectHandoff'])));
        }
      }
      if (restored.isEmpty) return;
      final teamPending = !restored.last.isUser &&
          _isTeamAdministrationClarification(restored.last.text);
      setState(() {
        _messages.addAll(restored);
        _teamAdministrationPending = teamPending;
      });
    } catch (_) {
      // Local conversation recovery must never prevent a fresh chat.
    }
  }

  void _setHistoryExpanded(bool expanded) {
    if (_shellHistoryExpanded == expanded) return;
    setState(() => _shellHistoryExpanded = expanded);
    if (widget.shellOverlay) {
      widget.onHistoryVisibilityChanged?.call(expanded);
    }
  }

  void showHistory() => _setHistoryExpanded(true);

  void minimizeHistory() => _setHistoryExpanded(false);

  void showExternalFailureMessage(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty || !mounted) return;
    if (normalized.toLowerCase().contains(
          'could not validate this enterprise page context',
        )) {
      return;
    }
    showHistory();
    setState(() {
      _messages.add(_ChatMessage.failure(normalized));
      _error = null;
    });
  }

  Future<String?> submitExternalPrompt(
    String prompt, {
    bool requestFocus = true,
  }) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty) return null;
    final before = _messages.length;
    _objective.text = normalized;
    _objective.selection = TextSelection.collapsed(offset: normalized.length);
    if (requestFocus) {
      _objectiveFocus.requestFocus();
    } else {
      _objectiveFocus.unfocus();
    }
    await _submit();
    if (!mounted) return null;
    if (_messages.length > before) {
      for (final message in _messages.skip(before).toList().reversed) {
        if (!message.isUser) return message.text;
      }
    }
    return _error;
  }

  void _handleActivityTimelineChanged() {
    if (!mounted) return;
    setState(() {
      if (_activeActivityJobId != null &&
          _activityController.jobId == _activeActivityJobId &&
          _activityController.isTerminal) {
        _activeActivityJobId = null;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activityController.removeListener(_handleActivityTimelineChanged);
    _activityController.dispose();
    _objective.dispose();
    _objectiveFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleOverlayMeasure();
  }

  void _scheduleOverlayMeasure() {
    if (_overlayMeasureScheduled) return;
    _overlayMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayMeasureScheduled = false;
      if (!mounted) return;

      final headerBox =
          _headerKey.currentContext?.findRenderObject() as RenderBox?;
      final composerBox =
          _composerKey.currentContext?.findRenderObject() as RenderBox?;
      final nextHeaderHeight = headerBox?.size.height ?? _headerHeight;
      final nextComposerHeight = composerBox?.size.height ?? _composerHeight;

      if ((nextHeaderHeight - _headerHeight).abs() < 0.5 &&
          (nextComposerHeight - _composerHeight).abs() < 0.5) {
        return;
      }

      setState(() {
        _headerHeight = nextHeaderHeight;
        _composerHeight = nextComposerHeight;
      });
    });
  }

  Future<void> _watchActivity(PandoraIntelligenceExecution execution) async {
    _activeActivityJobId = execution.jobId;
    await _activityController.bind(
      jobId: execution.jobId,
      stream: execution.events,
    );
  }

  Future<void> _watchDeviceActivity(
    PandoraDeviceActivityExecution execution,
  ) async {
    _activeActivityJobId = execution.jobId;
    await _activityController.bind(
      jobId: execution.jobId,
      stream: execution.events,
    );
  }

  Future<void> _dictate() async {
    _objectiveFocus.requestFocus();
    final text = await PandoraNativeIo.dictate();
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'System voice input is unavailable. You can still use the keyboard microphone.',
          ),
        ),
      );
      return;
    }
    final spacer = _objective.text.trim().isEmpty ? '' : ' ';
    _objective.text = '${_objective.text}$spacer$text';
    _objective.selection = TextSelection.collapsed(
      offset: _objective.text.length,
    );
    setState(() => _error = null);
  }

  Future<void> _attach() async {
    final attachment = await PandoraNativeIo.pickTextAttachment();
    if (!mounted) return;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No supported text file was attached. Choose TXT, Markdown, CSV, or JSON up to 32 KB.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _attachment = attachment;
      _error = null;
    });
  }

  Future<void> _pickCharacterContext() async {
    final selected = await showModalBottomSheet<PandoraCharacterProfile>(
      context: context,
      backgroundColor: PandoraSimpleColors.surface,
      showDragHandle: true,
      builder: (context) => const _CharacterContextSheet(),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _characterContext = selected;
      _characterSessionId = null;
      _serviceContext = null;
      _error = null;
    });
    _objectiveFocus.requestFocus();
  }

  void _removeCharacterContext() {
    setState(() {
      _characterContext = null;
      _characterSessionId = null;
    });
  }

  Future<void> _pickServiceContext() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    try {
      final registry = await intelligence.capabilityRegistry();
      if (!mounted) return;
      final selected = await showModalBottomSheet<PandoraCapabilityProvider>(
        context: context,
        backgroundColor: PandoraSimpleColors.surface,
        showDragHandle: true,
        builder: (context) =>
            _ServiceContextSheet(providers: registry.providers),
      );
      if (!mounted || selected == null) return;
      final prefix = '${selected.label}: ';
      setState(() {
        _serviceContext = selected;
        if (!_objective.text.toLowerCase().startsWith(prefix.toLowerCase())) {
          _objective.text = '$prefix${_objective.text}';
          _objective.selection = TextSelection.collapsed(
            offset: _objective.text.length,
          );
        }
        _error = null;
      });
      _objectiveFocus.requestFocus();
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _pickProjectContext() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    try {
      final projects = await intelligence.projectContexts();
      if (!mounted) return;
      final selected = await showModalBottomSheet<PandoraProjectContext>(
        context: context,
        backgroundColor: PandoraSimpleColors.surface,
        showDragHandle: true,
        builder: (context) => _ProjectContextSheet(projects: projects),
      );
      if (!mounted || selected == null) return;
      final threadId = _threadId;
      if (threadId != null) {
        await intelligence.associateThreadWithProject(threadId, selected.id);
        if (!mounted) return;
      }
      setState(() {
        _projectContext = selected;
        _error = null;
      });
      _objectiveFocus.requestFocus();
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _removeServiceContext() {
    final selected = _serviceContext;
    if (selected == null) return;
    final prefix = '${selected.label}: ';
    setState(() {
      if (_objective.text.toLowerCase().startsWith(prefix.toLowerCase())) {
        _objective.text = _objective.text.substring(prefix.length);
        _objective.selection = TextSelection.collapsed(
          offset: _objective.text.length,
        );
      }
      _serviceContext = null;
    });
  }

  Future<void> _removeProjectContext() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    final threadId = _threadId;
    try {
      if (intelligence != null && threadId != null) {
        await intelligence.associateThreadWithProject(threadId, null);
        if (!mounted) return;
      }
      setState(() => _projectContext = null);
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  bool _looksLikeActiveConstraint(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('constraint:') ||
        lower.startsWith('do not ') ||
        lower.startsWith("don't ") ||
        lower.startsWith('only ') ||
        lower.startsWith('make sure ') ||
        lower.startsWith('must not ') ||
        lower.startsWith('avoid ');
  }

  bool _looksLikeActiveCancel(String value) {
    final lower = value.trim().toLowerCase();
    return lower == 'cancel' ||
        lower == 'stop' ||
        lower == 'stop this' ||
        lower == 'cancel this' ||
        lower == 'never mind' ||
        lower == 'nevermind';
  }

  Future<void> _submitActiveControl(String objective) async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    final jobId = _activeActivityJobId;
    if (intelligence == null || jobId == null) return;
    final normalized = objective.trim();
    final type = normalized.isEmpty || _looksLikeActiveCancel(normalized)
        ? PandoraActivityControlType.cancel
        : _looksLikeActiveConstraint(normalized)
            ? PandoraActivityControlType.constraint
            : PandoraActivityControlType.redirect;
    var instruction =
        type == PandoraActivityControlType.cancel ? null : normalized;
    if (type == PandoraActivityControlType.constraint &&
        instruction != null &&
        instruction.toLowerCase().startsWith('constraint:')) {
      instruction = instruction.substring('constraint:'.length).trim();
    }
    if (type != PandoraActivityControlType.cancel &&
        (instruction == null || instruction.isEmpty)) {
      setState(() => _error = 'Add the update you want Pandora to apply.');
      return;
    }
    final requestId = _keys.create('pandora-chat-control');
    _objective.clear();
    setState(() => _error = null);
    try {
      await intelligence.controlActivityJob(
        jobId: jobId,
        requestId: requestId,
        type: type,
        instruction: instruction,
      );
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _submitCharacter(String objective) async {
    final character = _characterContext;
    if (character == null) return;
    final turn = await _characterClient.chat(
      characterId: character.id,
      message: objective,
      sessionId: _characterSessionId,
      mode: 'auto',
      responseLength: 'auto',
    );
    if (!mounted) return;
    setState(() {
      _characterSessionId = turn.sessionId;
      _messages.add(_ChatMessage.user(objective));
      _messages.add(_ChatMessage.pandora(turn.reply));
      _pendingMessage = null;
      _submissionKey = null;
      _outcomeUnknown = false;
    });
  }

  String _boundedRouteBridge(String objective) {
    if (_messages.isEmpty) return objective;
    final start = _messages.length > 4 ? _messages.length - 4 : 0;
    final context = _messages
        .sublist(start)
        .map((message) =>
            '${message.isUser ? 'User' : 'Pandora'}: ${message.text}')
        .join('\n');
    final bounded = context.length > 1600
        ? context.substring(context.length - 1600)
        : context;
    return 'Recent conversation context from the other inference route:\n'
        '$bounded\n\nCurrent user request:\n$objective';
  }

  String _boundedLocalEnterpriseContext() {
    final context = widget.enterpriseContext;
    if (context == null || context.isEmpty) return '';
    try {
      final localAi = context['localAiContext'];
      final localAiMap = localAi is Map
          ? localAi.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{};
      final localPayload = localAiMap['payload'];
      final today = context['today'];
      final snapshot = localPayload is Map && localPayload.isNotEmpty
          ? localPayload
          : today is Map
              ? today
              : const <String, Object?>{};
      final sourceHealth = context['sourceHealth'];
      final organization = context['organization'];
      final boundedContext = <String, Object?>{
        'property': organization,
        'authoritativeAsOf': localAiMap['authoritativeAsOf'],
        'sourceHealth': sourceHealth,
        'snapshot': snapshot,
      };
      final encoded = jsonEncode(boundedContext);
      final bounded =
          encoded.length > 3600 ? encoded.substring(0, 3600) : encoded;
      return 'Verified PLP resort snapshot already synchronized to this phone. '
          'Use fields present in this snapshot directly for PLP occupancy, rooms, '
          'arrivals, departures, revenue/sales, tasks, conflicts, and booking '
          'questions. If the requested field is present, answer from it and do '
          'NOT request cloud merely because the user says today, current, now, '
          'or so far. Do not claim the snapshot was refreshed during this turn. '
          'Request cloud only when required data is absent, an external action '
          'is required, or the task exceeds safe local reasoning.\n$bounded';
    } catch (_) {
      return '';
    }
  }

  bool get _isPlpEnterpriseContext {
    final context = widget.enterpriseContext;
    final organization = context?['organization'];
    if (organization is Map) {
      return organization['propertySlug']?.toString().trim() == 'plp-boracay';
    }
    return false;
  }

  Map<String, Object?>? _cloudEnterpriseContext() {
    final selection = widget.enterpriseContext?['selectedObject'];
    final memberWorkspace =
        selection is Map && selection['workspaceMode'] == 'member';
    if (_isPlpEnterpriseContext && !memberWorkspace) {
      return <String, Object?>{
        'surface': 'enterprise_overview',
        'route': '/enterprise/plp-boracay/alfred',
        'selectedObject': <String, Object?>{
          'workspaceSlug': 'plp-boracay',
          'assistant': 'alfred',
          if (widget.enterpriseContext?['selectedObject'] is Map)
            for (final key in const [
              'organizationId',
              'entryId',
              'workspaceMode',
              'adapterKey'
            ])
              if ((widget.enterpriseContext!['selectedObject'] as Map)[key] !=
                  null)
                key: (widget.enterpriseContext!['selectedObject'] as Map)[key],
        },
        'capabilities': const <String>['intelligence.chat'],
        'identityScope': 'enterprise_workspace',
      };
    }
    final context = widget.enterpriseContext;
    if (context == null || context.isEmpty) return null;
    const allowedSurfaces = <String>{
      'enterprise_overview',
      'enterprise_app_users',
      'enterprise_data',
      'enterprise_analytics',
      'enterprise_marketing',
      'enterprise_domains',
      'enterprise_integrations',
      'enterprise_security',
      'enterprise_code',
      'enterprise_agents',
      'enterprise_workflows',
      'enterprise_logs',
      'enterprise_api',
      'enterprise_settings',
      'enterprise_mcp',
      'enterprise_operations_room',
      'enterprise_tax',
    };
    const allowedScopes = <String>{
      'enterprise_workspace',
      'pandora_organization',
      'plp_staff',
    };
    final surface = context['surface']?.toString().trim();
    final route = context['route']?.toString().trim();
    final identityScope = context['identityScope']?.toString().trim();
    if (!allowedSurfaces.contains(surface) ||
        route == null ||
        !route.startsWith('/enterprise/') ||
        !allowedScopes.contains(identityScope)) {
      return null;
    }
    return Map<String, Object?>.from(context);
  }

  Future<void> _recordLocalAiTurn({
    required String phase,
    required String outcome,
    required String reason,
    PandoraLocalAiStatus? status,
  }) async {
    if (!_isPlpEnterpriseContext) return;
    final organization = widget.enterpriseContext?['organization'];
    final organizationId =
        organization is Map ? organization['id']?.toString().trim() : null;
    if (organizationId == null || organizationId.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'record_phone_local_ai_turn_v1',
        params: <String, Object?>{
          'p_organization_id': organizationId,
          'p_phase': phase,
          'p_outcome': outcome,
          'p_reason': reason.length > 160 ? reason.substring(0, 160) : reason,
          'p_model_name': status?.modelName,
          'p_model_sha256': status?.modelSha256,
        },
      );
    } catch (_) {
      // Local inference must never depend on telemetry delivery.
    }
  }

  String? _plpActionPendingRequestId;
  String? _plpActionPendingObjective;

  Future<bool> _trySubmitPlpStaffTask(String objective) async {
    if (!_isPlpEnterpriseContext) return false;
    final command = PlpStaffTaskCommand.tryParse(objective);
    if (command == null) return false;

    final priorObjective = _plpActionPendingObjective;
    final priorRequestId = _plpActionPendingRequestId;
    if (priorRequestId != null &&
        priorObjective != null &&
        priorObjective != objective) {
      setState(() {
        _error =
            'A prior PLP staff-task outcome is still unconfirmed. Check Activity before creating another task.';
        _pendingMessage = null;
      });
      return true;
    }

    final requestId = priorRequestId ?? _keys.create('plp-staff-task');
    _plpActionPendingRequestId = requestId;
    _plpActionPendingObjective = objective;

    try {
      final result = await const PlpStaffTaskAction().execute(
        requestId: requestId,
        command: command,
      );
      if (!mounted) return true;
      setState(() {
        _messages.add(_ChatMessage.user(objective));
        _messages.add(
          _ChatMessage.pandora(
            'Staff task created for ' +
                result.bookingReference +
                ': ' +
                result.title +
                '. Supabase provider readback is verified and the real execution is recorded in Activity.',
          ),
        );
        _pendingMessage = null;
        _submissionKey = null;
        _outcomeUnknown = false;
        _lastTurnUsedLocalAi = false;
        _plpActionPendingRequestId = null;
        _plpActionPendingObjective = null;
      });
      return true;
    } on PlpStaffTaskActionException catch (error) {
      if (!mounted) return true;
      setState(() {
        _outcomeUnknown = true;
        _pendingMessage = null;
        _error = error.message +
            ' Pandora retained the same idempotency key. Check Activity before retrying the same command.';
      });
      return true;
    }
  }

  Future<bool> _trySubmitLocalAi(
    String objective, {
    bool forceLocal = false,
  }) async {
    final localEnabled = PandoraLocalAiPreference.cachedEnabled;
    if (!localEnabled) {
      if (forceLocal) {
        _recordTurnFailure(
          objective,
          'Phone AI is off. Turn it on in Settings or choose Auto.',
          retryable: false,
        );
        return true;
      }
      return false;
    }
    final status = await (() async {
      try {
        return await PandoraLocalAi.instance.status().timeout(
              const Duration(milliseconds: 600),
            );
      } catch (_) {
        return null;
      }
    })();
    if (status == null) return false;
    final route = PandoraLocalAiRouter.decide(
      message: objective,
      hasAttachment: _attachment != null || _imageAttachment != null,
      hasProjectContext: _projectContext != null ||
          (widget.enterpriseContext?.isNotEmpty ?? false),
      hasSelectedCapability: _serviceContext != null,
      hasCharacterContext: _characterContext != null,
      status: status,
    );
    if (!route.useLocal) {
      unawaited(
        _recordLocalAiTurn(
          phase: 'route',
          outcome: 'bypassed',
          reason: route.reason,
          status: status,
        ),
      );
      if (forceLocal && mounted) {
        setState(() {
          _pendingMessage = null;
          _error =
              'Local device (Qwen) cannot safely handle this turn. Choose Auto or a cloud model.';
        });
        return true;
      }
      return false;
    }
    unawaited(
      _recordLocalAiTurn(
        phase: 'route',
        outcome: 'started',
        reason: route.reason,
        status: status,
      ),
    );

    if (!status.loaded && !forceLocal) {
      unawaited(
        _recordLocalAiTurn(
          phase: 'fallback',
          outcome: 'cloud',
          reason: 'local_cold_background_prewarm',
          status: status,
        ),
      );
      if (_isPlpEnterpriseContext) {
        unawaited(_prewarmPlpLocalAiIfSafe());
      }
      // Auto never blocks a response on a cold local model.
      return false;
    }

    PandoraLocalAiRuntime.instance.cancelIdleUnload();
    final bridgeFromOtherRoute = !_lastTurnUsedLocalAi && _messages.isNotEmpty;

    // Warm first. The old order asked a cold engine to reset conversation,
    // which performed an implicit load plus a second system-prompt reset and
    // made cold-start failures harder to recover.
    try {
      if (!await PandoraLocalAi.instance.warm()) {
        unawaited(
          _recordLocalAiTurn(
            phase: 'warm',
            outcome: 'failed',
            reason: 'warm_returned_false',
            status: status,
          ),
        );
        await PandoraLocalAiRuntime.instance.unload();
        return false;
      }
      unawaited(
        _recordLocalAiTurn(
          phase: 'warm',
          outcome: 'success',
          reason: 'model_ready',
          status: status,
        ),
      );
    } on PandoraLocalAiException catch (error) {
      if (error.message.contains('already preparing or generating')) {
        unawaited(
          _recordLocalAiTurn(
            phase: 'warm',
            outcome: 'cloud',
            reason: 'background_prewarm_in_progress',
            status: status,
          ),
        );
        // The background prewarm owns the model load. Let this turn continue
        // through cloud without cancelling that load; the next eligible turn
        // can use the now-warm Qwen model.
        return false;
      }
      unawaited(
        _recordLocalAiTurn(
          phase: 'warm',
          outcome: 'failed',
          reason: error.message,
          status: status,
        ),
      );
      await PandoraLocalAiRuntime.instance.unload();
      return false;
    } catch (_) {
      await PandoraLocalAiRuntime.instance.unload();
      return false;
    }

    if (bridgeFromOtherRoute) {
      try {
        await PandoraLocalAi.instance.resetConversation();
      } catch (_) {
        // Do not cold-warm on the user's response path. A failed warm reset
        // falls through to cloud and background prewarm repairs local state.
        await PandoraLocalAiRuntime.instance.unload();
        if (_isPlpEnterpriseContext) {
          unawaited(_prewarmPlpLocalAiIfSafe());
        }
        return false;
      }
    }
    final routedPrompt =
        bridgeFromOtherRoute ? _boundedRouteBridge(objective) : objective;
    final enterpriseBridge = _boundedLocalEnterpriseContext();
    final localPrompt = enterpriseBridge.isEmpty
        ? routedPrompt
        : '$enterpriseBridge\n\nCurrent user request:\n$routedPrompt';

    var response = '';
    var started = false;
    _localAiGenerating = true;
    try {
      await for (final chunk in PandoraLocalAi.instance
          .generate(
            localPrompt,
            predictLength: _isPlpEnterpriseContext ? 96 : 192,
          )
          .timeout(_localInferenceIdleTimeout)) {
        if (!mounted) return true;
        response += chunk;
        setState(() {
          if (!started) {
            started = true;
            _messages.add(_ChatMessage.user(objective));
            _messages.add(_ChatMessage.pandora(response));
            _pendingMessage = null;
          } else {
            _messages[_messages.length - 1] = _ChatMessage.pandora(response);
          }
        });
      }
    } catch (error) {
      unawaited(
        _recordLocalAiTurn(
          phase: 'generation',
          outcome: 'failed',
          reason: error.toString(),
          status: status,
        ),
      );
      if (error is TimeoutException) {
        await PandoraLocalAi.instance.cancel();
        PandoraLocalAiRuntime.instance.keepResident();
      } else {
        await PandoraLocalAiRuntime.instance.unload();
      }
      if (!mounted) return true;
      if (started && _messages.length >= 2) {
        setState(() {
          _messages.removeLast();
          _messages.removeLast();
          _pendingMessage = objective;
          _error = null;
        });
      }
      return false;
    } finally {
      _localAiGenerating = false;
    }

    if (!mounted) return true;
    final normalized = response.trim();
    if (normalized == '[[PANDORA_CLOUD_REQUIRED]]') {
      if (started && _messages.length >= 2) {
        setState(() {
          _messages.removeLast();
          _messages.removeLast();
          _pendingMessage = objective;
        });
      }
      unawaited(
        _recordLocalAiTurn(
          phase: 'fallback',
          outcome: 'cloud',
          reason: 'model_requested_cloud',
          status: status,
        ),
      );
      PandoraLocalAiRuntime.instance.keepResident();
      return false;
    }
    if (!started || normalized.isEmpty) {
      await PandoraLocalAiRuntime.instance.unload();
      return false;
    }

    setState(() {
      _messages[_messages.length - 1] = _ChatMessage.pandora(normalized);
      _submissionKey = null;
      _outcomeUnknown = false;
      _pendingMessage = null;
      _lastTurnUsedLocalAi = true;
    });
    unawaited(
      _recordLocalAiTurn(
        phase: 'success',
        outcome: 'success',
        reason: route.reason,
        status: status,
      ),
    );
    PandoraLocalAiRuntime.instance.keepResident();
    return true;
  }

  bool _looksLikeTeamAdministrationTurn(String message) {
    final value = message.trim();
    if (value.isEmpty) return false;
    final hasScope = RegExp(
      r'\\b(team|member|staff|user|access|invite)\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final hasEmail = RegExp(
      r'\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final hasRole = RegExp(
      r'\\b(owner|admin|operator|member|viewer)\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final inviteAction = RegExp(
      r'\\b(add|invite|create)\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final accessAction = RegExp(
      r'\\b(suspend|disable|deactivate|revoke|remove|reactivate|activate|restore)\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final roleAction = RegExp(
      r'\\b(change|make|set|give|promote|demote)\\b',
      caseSensitive: false,
    ).hasMatch(value);
    final staffTask = RegExp(
      r'\\bstaff\\s+task\\b|\\btask\\s+for\\s+staff\\b',
      caseSensitive: false,
    ).hasMatch(value);
    if (staffTask) return false;
    return ((hasScope || hasEmail) &&
            (inviteAction || accessAction || roleAction)) ||
        (hasRole && roleAction);
  }

  bool _isTeamAdministrationClarification(String message) {
    final value = message.trim();
    return value == 'What email address should I invite?' ||
        value ==
            'What role should I give them: owner, admin, operator, member, or viewer?' ||
        value ==
            'Which team member should I change? Give me their name or email address.' ||
        value == 'What should I change: their role, or their access status?' ||
        (value.startsWith("I couldn't find ") &&
            value.endsWith('Give me the exact email address.')) ||
        (value.startsWith('I found more than one match for ') &&
            value.endsWith('Give me the exact email address.'));
  }

  bool _applyPlpContinuityFallback(String objective) {
    if (!_isPlpEnterpriseContext || !mounted) return false;
    final actionLike = !PlpChatFallback.isReadOnlyTurn(objective);
    final deterministic = actionLike
        ? null
        : PlpChatFallback.deterministicReply(
            message: objective,
            enterpriseContext: widget.enterpriseContext,
          );
    final reply = deterministic ??
        PlpChatFallback.continuityNotice(
          actionLike: actionLike,
        );
    setState(() {
      _messages.add(_ChatMessage.user(objective));
      _messages.add(_ChatMessage.pandora(reply));
      _pendingMessage = null;
      _attachment = null;
      _imageAttachment = null;
      _submissionKey = null;
      _outcomeUnknown = false;
      _lastTurnUsedLocalAi = false;
      _error = null;
    });
    return true;
  }

  void _recordTurnFailure(
    String objective,
    String message, {
    bool retryable = true,
    bool outcomeUnknown = false,
  }) {
    if (!mounted) return;
    final normalizedObjective = objective.trim();
    final visibleObjective = _sanitizeVisibleUserText(normalizedObjective);
    setState(() {
      final alreadyCommitted = _messages.isNotEmpty &&
          _messages.last.isUser &&
          _messages.last.text == visibleObjective;
      if (visibleObjective.isNotEmpty && !alreadyCommitted) {
        _messages.add(_ChatMessage.user(visibleObjective));
      }
      _messages.add(
        _ChatMessage.failure(
          message,
          retryObjective: retryable ? normalizedObjective : null,
        ),
      );
      _pendingMessage = null;
      _error = null;
      _outcomeUnknown = outcomeUnknown;
      if (!outcomeUnknown) _submissionKey = null;
    });
  }

  Future<void> _retryFailedTurn(_ChatMessage message) async {
    final objective = message.retryObjective?.trim();
    if (objective == null || objective.isEmpty || _submitting) return;
    final index = _messages.indexOf(message);
    setState(() {
      if (index >= 0) {
        _messages.removeAt(index);
        final preceding = index - 1;
        if (preceding >= 0 &&
            preceding < _messages.length &&
            _messages[preceding].isUser &&
            _messages[preceding].text == _sanitizeVisibleUserText(objective)) {
          _messages.removeAt(preceding);
        }
      }
      _error = null;
      _outcomeUnknown = false;
    });
    _objective.text = objective;
    _objective.selection =
        TextSelection.collapsed(offset: _objective.text.length);
    await _submit();
  }

  Future<void> _submit() async {
    final objective = _objective.text.trim();
    if (_submitting && _localAiGenerating && objective.isEmpty) {
      await PandoraLocalAi.instance.cancel();
      return;
    }
    if (_submitting && _activeActivityJobId != null) {
      await _submitActiveControl(objective);
      return;
    }
    if (objective.isEmpty) {
      setState(() => _error = 'Message Pandora first.');
      _objectiveFocus.requestFocus();
      return;
    }
    if (_characterContext != null &&
        (_attachment != null || _imageAttachment != null)) {
      setState(
        () => _error =
            'Character mode uses its prepared memory right now. Remove the attachment before sending.',
      );
      return;
    }
    final dependencies = PandoraDependencies.of(context);
    final hasIntelligence = dependencies.intelligence != null;
    final suppressActivityTheatre =
        hasIntelligence && pandoraIsTrivialConversationTurn(objective);
    final requestActivityTheatre = !hasIntelligence ||
        pandoraShouldRequestActivityTheatre(
          objective,
          hasAttachment: _attachment != null || _imageAttachment != null,
          hasSelectedCapability: _serviceContext != null,
          hasProjectContext: _projectContext != null ||
              (widget.enterpriseContext?.isNotEmpty ?? false),
        );
    // A completed user turn must never inherit a prior turn's request identity.
    _submissionKey = null;
    await _activityController.clear();
    if (!mounted) return;
    _activeActivityJobId = null;
    if (widget.shellOverlay) showHistory();
    setState(() {
      _submitting = true;
      _activityTheatreRequested = requestActivityTheatre;
      _activityTheatreSuppressed = suppressActivityTheatre;
      _pendingMessage = objective;
      _objective.clear();
      _error = null;
    });
    PandoraIntelligenceHandoff? coreHandoff;
    final selectedScope = widget.enterpriseContext?['selectedObject'];
    final coreScope = selectedScope is Map &&
        (selectedScope['coreMode'] == 'owner' ||
            selectedScope['entryId'] != null ||
            selectedScope['workspaceMode'] == 'member' ||
            selectedScope['workspaceMode'] == 'administrator');
    try {
      if (_characterContext != null && !coreScope) {
        _lastTurnUsedLocalAi = false;
        await _submitCharacter(objective);
        return;
      }
      if (!coreScope && await _trySubmitPlpStaffTask(objective)) return;
      final teamAdministrationTurn = coreScope ||
          _teamAdministrationPending ||
          _looksLikeTeamAdministrationTurn(objective);
      final calendarParse = teamAdministrationTurn
          ? null
          : PandoraCalendarCommand.tryParse(
              objective,
              now: DateTime.now(),
            );
      if (calendarParse != null) {
        _lastTurnUsedLocalAi = false;
        if (!calendarParse.isReady) {
          setState(() {
            _messages.add(_ChatMessage.user(objective));
            _messages.add(
              _ChatMessage.pandora(
                calendarParse.clarification ??
                    'Tell me the missing calendar detail before I make a change.',
              ),
            );
            _pendingMessage = null;
            _submissionKey = null;
            _outcomeUnknown = false;
          });
          return;
        }
        await _handleCalendarCommand(
          dependencies,
          objective,
          calendarParse.command!,
        );
        return;
      }
      final deviceCommunication = teamAdministrationTurn
          ? null
          : PandoraDeviceCommunicationCommand.tryParse(
              objective,
            );
      if (deviceCommunication != null) {
        _lastTurnUsedLocalAi = false;
        await _handleDeviceCommunication(
            dependencies, objective, deviceCommunication);
        return;
      }
      final priorTurnUsedLocalAi = _lastTurnUsedLocalAi;
      final forceLocal = isPandoraLocalDeviceSelection(_modelSelection);
      if (!teamAdministrationTurn &&
          await _trySubmitLocalAi(objective, forceLocal: forceLocal)) {
        return;
      }
      if (forceLocal) {
        _recordTurnFailure(
          objective,
          'Local device (Qwen) is unavailable for this turn. Choose Auto or a cloud model.',
        );
        return;
      }

      final routedObjective = priorTurnUsedLocalAi && _messages.isNotEmpty
          ? _boundedRouteBridge(objective)
          : objective;
      _lastTurnUsedLocalAi = false;

      final intelligence = dependencies.intelligence;
      if (intelligence == null && coreScope) {
        _recordTurnFailure(objective,
            'Pandora could not verify the current account scope. Refresh before trying this command.');
        return;
      }
      if (intelligence == null) {
        // A Project is optional persistent context, never a prerequisite for
        // talking to Pandora or using a non-project capability. Fall back to
        // the general governed ask path instead of creating a Project.
        _submissionKey ??= _keys.create('simple-intake');
        final receipt = await dependencies.repository.ask(
          message: routedObjective,
          idempotencyKey: _submissionKey,
        );
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage.user(objective));
          _messages.add(_ChatMessage.pandora(receipt.reply));
          _pendingMessage = null;
          _attachment = null;
          _imageAttachment = null;
          _submissionKey = null;
        });
        return;
      }

      final turnRequestId = _submissionKey ??= _keys.create(
        'pandora-chat-turn',
      );
      final execution = await intelligence.startChatExecution(
        message: routedObjective,
        requestId: turnRequestId,
        threadId: _threadId,
        projectId: _projectContext?.id,
        textAttachment: _attachment,
        imageAttachment: _imageAttachment,
        enterpriseContext: _cloudEnterpriseContext(),
        mode: _reasoningMode,
        modelSelection: _modelSelection,
      );
      await _watchActivity(execution);
      PandoraIntelligenceTurn turn;
      try {
        turn = await execution.turn;
      } on PandoraIntelligenceException {
        final recovered =
            await intelligence.recoverCompletedChatTurn(execution.jobId);
        if (recovered == null) rethrow;
        turn = recovered;
      } catch (_) {
        final recovered =
            await intelligence.recoverCompletedChatTurn(execution.jobId);
        if (recovered == null) rethrow;
        turn = recovered;
      }
      if (!mounted) return;
      setState(() {
        _threadId = turn.threadId;
        _teamAdministrationPending = turn.needsClarification &&
            (turn.conversationLane == 'team_admin' ||
                _isTeamAdministrationClarification(turn.reply));
        _messages.add(_ChatMessage.user(objective));
        _messages.add(_ChatMessage.pandora(
          turn.reply,
          authorizationUrl: turn.authorizationUrl,
          coreNavigation: turn.handoff?.kind == 'core_navigation' &&
                  turn.handoff?.action == 'inspect' &&
                  widget.onCoreNavigate != null
              ? turn.handoff
              : null,
        ));
        _pendingMessage = null;
        _attachment = null;
        _imageAttachment = null;
        _outcomeUnknown = false;
      });

      final authorizationUrl = turn.authorizationUrl;
      if (authorizationUrl != null && !kIsWeb) {
        final launched = await launchUrl(
          authorizationUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          setState(
            () => _error =
                'Pandora prepared the secure authorization page, but this device could not open it.',
          );
        }
      }

      final handoff = turn.handoff;
      if (handoff?.kind == 'core_navigation' &&
          handoff?.action != 'inspect' &&
          widget.onCoreNavigate != null) {
        coreHandoff = handoff;
      }
      final experience = dependencies.projectExperienceRepository;
      final handoffProjectId = handoff?.projectId?.trim();
      if (handoff?.source == 'project_workspace_change' &&
          experience != null &&
          handoffProjectId != null &&
          handoffProjectId.isNotEmpty) {
        final actionRequest = handoff!.request.trim();
        if (actionRequest.length < 4) {
          setState(() => _error = 'Pandora needs a clearer project change.');
          return;
        }

        var mutationAccepted = false;
        final executionKey = _submissionKey ??= _keys.create(
          'pandora-chat-project-change',
        );
        try {
          final projection = await experience.loadExperience(handoffProjectId);
          if (!mounted) return;

          final initialBuildReady = projection.state.name == 'build' &&
              projection.currentVersionId == null &&
              projection.candidateVersionId == null &&
              projection.activeBuildJobId == null;
          if (initialBuildReady) {
            mutationAccepted = true;
            final start = await experience.requestBuild(
              projectId: handoffProjectId,
              idempotencyKey: '$executionKey:initial-build',
            );
            if (!mounted) return;
            setState(() {
              _messages.add(
                _ChatMessage.pandora(
                  start.streamId.trim().isNotEmpty
                      ? 'Build started with Gemini. I’ll keep this chat open while Pandora generates and verifies the real source.'
                      : 'The build request was accepted, but its live stream is not available yet. Check Activity before retrying.',
                ),
              );
              _submissionKey = null;
              _outcomeUnknown = false;
            });
            return;
          }

          if (projection.activeBuildJobId != null) {
            _submissionKey = null;
            setState(() {
              _messages.add(
                _ChatMessage.pandora(
                  'A real build is already running for this project. I won’t start a duplicate.',
                ),
              );
            });
            return;
          }

          if (projection.canChange != true) {
            _submissionKey = null;
            setState(() {
              _error =
                  'This project is not ready for a change yet. Pandora kept you in chat and did not start a duplicate build.';
            });
            return;
          }

          final intentId = await experience.submitChange(
            projectId: handoffProjectId,
            changeText: actionRequest,
            idempotencyKey: '$executionKey:intent',
          );
          mutationAccepted = true;

          var understandingReady = false;
          var rejected = false;
          for (var attempt = 0; attempt < 45; attempt += 1) {
            final understanding = await experience.understanding(
              projectId: handoffProjectId,
              expectedSourceIntentId: intentId,
            );
            if (understanding.isReady) {
              understandingReady = true;
              break;
            }
            if (understanding.state.name == 'rejected') {
              rejected = true;
              break;
            }
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (!mounted) return;
          if (rejected) {
            _submissionKey = null;
            setState(() {
              _error =
                  'Pandora needs a different instruction before it can build that change.';
            });
            return;
          }
          if (!understandingReady) {
            setState(() {
              _outcomeUnknown = true;
              _error =
                  'Your change is saved and still being prepared. Pandora will not submit it twice. Check Activity before retrying.';
            });
            return;
          }

          final start = await experience.requestBuild(
            projectId: handoffProjectId,
            idempotencyKey: '$executionKey:build:$intentId',
          );
          if (!mounted) return;
          setState(() {
            _messages.add(
              _ChatMessage.pandora(
                start.streamId.trim().isNotEmpty
                    ? 'Build started. I’ll keep this chat open while Pandora works. Open the project only when you want to inspect the result.'
                    : 'Pandora accepted the change, but the build stream is not available yet. Check Activity before retrying.',
              ),
            );
            _submissionKey = null;
            _outcomeUnknown = false;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            if (mutationAccepted) {
              _outcomeUnknown = true;
              _error =
                  'Your change may already be saved. Pandora will not retry it automatically. Check Activity before sending it again.';
            } else {
              _submissionKey = null;
              _error = 'Pandora could not start that project change right now.';
            }
          });
        }
        return;
      }

      // `intelligence.chat` owns exactly one dispatch for this turn. Explicit
      // selected-project changes execute through the real project runtime in
      // this chat. They never navigate away, never reopen ProjectOS intake,
      // and never resubmit the owner instruction as a second intelligence turn.
      // Progress and verified terminal evidence remain authoritative.
    } on PandoraCharacterException catch (error) {
      if (!mounted) return;
      _recordTurnFailure(objective, error.message);
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      if (_applyPlpContinuityFallback(objective)) return;
      _recordTurnFailure(objective, error.message);
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      if (!error.outcomeMayBeUnknown &&
          _applyPlpContinuityFallback(objective)) {
        return;
      }
      _recordTurnFailure(
        objective,
        error.outcomeMayBeUnknown
            ? error.message +
                ' Pandora will not retry this write. Check Activity before sending another request.'
            : error.message,
        retryable: !error.outcomeMayBeUnknown,
        outcomeUnknown: error.outcomeMayBeUnknown,
      );
    } catch (_) {
      if (!mounted) return;
      if (_applyPlpContinuityFallback(objective)) return;
      _recordTurnFailure(
        objective,
        'Pandora intelligence is temporarily unavailable.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _pendingMessage = null;
        });
        if (coreHandoff != null) {
          final handoff = coreHandoff;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onCoreNavigate?.call(handoff);
          });
        }
      }
    }
  }

  Future<void> _handleCalendarCommand(
    PandoraDependencies dependencies,
    String objective,
    PandoraCalendarCommand command,
  ) async {
    final operationId = _submissionKey ??= _keys.create('pandora-calendar');
    final intelligence = dependencies.intelligence;
    final localStore = dependencies.localStore;
    final localFacts = <Map<String, Object?>>[];

    if (localStore != null && intelligence != null) {
      unawaited(
        PandoraLocalSyncCoordinator(
          store: localStore,
          transport: PandoraDeviceActivityLocalSyncTransport(intelligence),
        ).drain(),
      );
    }

    PandoraDeviceActivityExecution? activity;
    if (intelligence != null) {
      try {
        activity = await intelligence.startDeviceActivity(
          requestId: operationId,
          threadId: _threadId,
          projectId: _projectContext?.id,
        );
        await _watchDeviceActivity(activity);
      } on PandoraIntelligenceException {
        activity = null;
      }
    }

    final executor = PandoraCalendarActionExecutor(
      localCache:
          localStore == null ? null : PandoraLocalStateCache(localStore),
      reporter: (fact) async {
        localFacts.add(<String, Object?>{
          'capability': fact.capability,
          'stage': fact.stage,
          'observedAt': fact.observedAt.toUtc().toIso8601String(),
        });
        if (activity == null || intelligence == null) return;
        try {
          await intelligence.recordDeviceActivity(
            jobId: activity.jobId,
            operationId: operationId,
            capability: fact.capability,
            stage: fact.stage,
            observedAt: fact.observedAt,
          );
        } on PandoraIntelligenceException {
          if (localStore == null) return;
          await enqueuePandoraDeviceFact(
            store: localStore,
            jobId: activity.jobId,
            operationId: operationId,
            capability: fact.capability,
            stage: fact.stage,
            observedAt: fact.observedAt,
          );
        }
      },
    );
    final result = await executor.execute(command, operationId: operationId);

    if (activity == null && localStore != null && localFacts.isNotEmpty) {
      await enqueuePandoraDeviceTimeline(
        store: localStore,
        requestId: operationId,
        threadId: _threadId,
        projectId: _projectContext?.id,
        events: localFacts,
      );
    }
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage.user(objective));
      _messages.add(_ChatMessage.pandora(result.reply));
      _pendingMessage = null;
      _attachment = null;
      _imageAttachment = null;
      _submissionKey = null;
      _outcomeUnknown = false;
    });
  }

  Future<void> _handleDeviceCommunication(
    PandoraDependencies dependencies,
    String objective,
    PandoraDeviceCommunicationCommand command,
  ) async {
    final operationId =
        _submissionKey ??= _keys.create('pandora-direct-communication');
    final intelligence = dependencies.intelligence;
    PandoraDeviceActivityExecution? activity;
    if (intelligence != null) {
      try {
        activity = await intelligence.startDeviceActivity(
          requestId: operationId,
          threadId: _threadId,
          projectId: _projectContext?.id,
        );
        await _watchDeviceActivity(activity);
      } on PandoraIntelligenceException {
        activity = null;
      }
    }

    final localStore = dependencies.localStore;
    final executor = PandoraCommunicationActionExecutor(
      resolvedContactObserver: localStore == null
          ? null
          : (displayName, phoneNumber) =>
              PandoraLocalStateCache(localStore).cacheSelectedContact(
                displayName: displayName,
                phoneNumber: phoneNumber,
              ),
      reporter: activity == null || intelligence == null
          ? null
          : (fact) => intelligence.recordDeviceActivity(
                jobId: activity!.jobId,
                operationId: operationId,
                capability: fact.capability,
                stage: fact.stage,
                observedAt: fact.observedAt,
              ),
    );
    final result = await executor.execute(
      command,
      operationId: operationId,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage.user(objective));
      _messages.add(_ChatMessage.pandora(result.reply));
      _pendingMessage = null;
      _attachment = null;
      _imageAttachment = null;
      _submissionKey = null;
      _outcomeUnknown = result.outcomeUnknown;
    });
  }

  void newChat() {
    if (_submitting) return;
    final priorCharacter = _characterContext;
    final priorCharacterSession = _characterSessionId;
    if (priorCharacter != null &&
        priorCharacterSession != null &&
        priorCharacterSession.isNotEmpty) {
      unawaited(
        _characterClient.reset(
          characterId: priorCharacter.id,
          sessionId: priorCharacterSession,
        ),
      );
    }
    _activeActivityJobId = null;
    _activityTheatreRequested = false;
    _activityTheatreSuppressed = false;
    unawaited(_activityController.clear());
    unawaited(PandoraLocalAi.instance.resetConversation());
    _lastTurnUsedLocalAi = false;
    if (widget.shellOverlay) showHistory();
    setState(() {
      _teamAdministrationPending = false;
      _messages.clear();
      _objective.clear();
      _attachment = null;
      _imageAttachment = null;
      _projectContext = null;
      _serviceContext = null;
      _characterContext = null;
      _characterSessionId = null;
      _threadId = null;
      _pendingMessage = null;
      _error = null;
      _outcomeUnknown = false;
      _submissionKey = null;
      _modelSelection = const PandoraChatModelSelection.auto();
      _reasoningMode = PandoraIntelligenceMode.auto;
      _modelLabel = 'Auto';
      _pickerOpen = false;
      _pickerSnapshot = null;
      _pickerStartAtEnd = false;
    });
    _objectiveFocus.requestFocus();
  }

  /// A tenant transition must not abandon an unresolved mutation or reuse its
  /// pending result in another organization. Page navigation is unaffected.
  bool get hasPendingScopeWork =>
      _submitting ||
      _loadingThread ||
      _outcomeUnknown ||
      _plpActionPendingRequestId != null ||
      _activeActivityJobId != null;

  Future<void> _pickModel() async {
    if (_isCommonWorkspace) return;
    if (_pickerOpen) {
      setState(() {
        _pickerOpen = false;
        _pickerStartAtEnd = false;
      });
      return;
    }
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null || _submitting || _outcomeUnknown) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final snapshot = await intelligence.modelPicker(threadId: _threadId);
      final localEnabled = await PandoraLocalAiPreference.load();
      PandoraLocalAiStatus? localStatus;
      if (localEnabled) {
        try {
          localStatus = await PandoraLocalAi.instance.status().timeout(
                const Duration(milliseconds: 600),
              );
        } catch (_) {
          localStatus = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _pickerSnapshot = snapshot;
        _pickerLocalAiEnabled = localEnabled;
        _pickerLocalAiAvailable = localStatus != null &&
            localStatus.supported &&
            localStatus.configured;
        _pickerLocalAiModelName = localStatus?.modelName;
        _pickerStartAtEnd = false;
        _pickerOpen = true;
        _error = null;
      });
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage.failure(error.message));
        _error = null;
      });
    }
  }

  void _dismissPicker() {
    if (!_pickerOpen) return;
    setState(() {
      _pickerOpen = false;
      _pickerStartAtEnd = false;
    });
  }

  void _applyPickerModel(PandoraModelPickerChoice choice) {
    if (!mounted) return;
    setState(() {
      _modelSelection = choice.selection;
      _modelLabel = choice.label;
      _pickerOpen = false;
      _pickerStartAtEnd = false;
      _error = null;
    });
  }

  void _applyPickerReasoning(PandoraIntelligenceMode mode) {
    if (!mounted) return;
    setState(() {
      _reasoningMode = mode;
      _pickerOpen = false;
      _pickerStartAtEnd = false;
      _error = null;
    });
  }

  @visibleForTesting
  void debugShowModelPicker(
    PandoraChatModelPickerSnapshot snapshot, {
    bool startAtEnd = false,
    bool localAiEnabled = false,
    bool localAiAvailable = false,
    String? localAiModelName,
  }) {
    setState(() {
      _pickerSnapshot = snapshot;
      _pickerOpen = true;
      _pickerStartAtEnd = startAtEnd;
      _pickerLocalAiEnabled = localAiEnabled;
      _pickerLocalAiAvailable = localAiAvailable;
      _pickerLocalAiModelName = localAiModelName;
    });
  }

  @visibleForTesting
  void debugSetModelSelection(
    PandoraChatModelSelection selection,
    String label,
  ) {
    setState(() {
      _modelSelection = selection;
      _modelLabel = label;
      _pickerOpen = false;
    });
  }

  Future<void> loadThread(String threadId) async {
    if (_submitting || _loadingThread || threadId == _threadId) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    _activeActivityJobId = null;
    _activityTheatreRequested = false;
    _activityTheatreSuppressed = false;
    await _activityController.clear();
    if (widget.shellOverlay) showHistory();
    setState(() {
      _loadingThread = true;
      _error = null;
      _pendingMessage = null;
      _pickerOpen = false;
      _pickerStartAtEnd = false;
    });
    try {
      final history = await intelligence.messages(threadId);
      PandoraChatModelPickerSnapshot? picker;
      try {
        if (!_isCommonWorkspace)
          picker = await intelligence.modelPicker(threadId: threadId);
      } on PandoraIntelligenceException {
        picker = null;
      }
      if (!mounted) return;
      final teamPending = history.isNotEmpty &&
          !history.last.isUser &&
          _isTeamAdministrationClarification(history.last.content);
      setState(() {
        _threadId = threadId;
        _teamAdministrationPending = teamPending;
        _messages
          ..clear()
          ..addAll(
            history.map(
              (message) => message.isUser
                  ? _ChatMessage.user(message.content)
                  : _ChatMessage.pandora(message.content,
                      coreNavigation: message.inspectHandoff),
            ),
          );
        _objective.clear();
        _attachment = null;
        _imageAttachment = null;
        _outcomeUnknown = false;
        _submissionKey = null;
        if (picker != null) {
          _modelSelection = picker.selection;
          _reasoningMode = picker.reasoningMode;
          _modelLabel = picker.labelFor(picker.selection);
        } else {
          _modelSelection = const PandoraChatModelSelection.auto();
          _reasoningMode = PandoraIntelligenceMode.auto;
          _modelLabel = 'Auto';
        }
      });
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingThread = false);
    }
  }

  Future<void> _pickImage({required bool camera}) async {
    final image = camera
        ? await PandoraNativeIo.takePhoto()
        : await PandoraNativeIo.pickPhoto();
    if (!mounted) return;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            camera
                ? 'No camera image was attached.'
                : 'No supported photo was attached.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _imageAttachment = image;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shellOverlay) _scheduleOverlayMeasure();
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final topInset = media.padding.top;
    final conversationActive =
        _threadId != null || _messages.isNotEmpty || _pendingMessage != null;
    final headerHeight =
        conversationActive ? (_headerHeight > 0 ? _headerHeight : 56.0) : 0.0;
    final composerHeight = _composerHeight > 0
        ? _composerHeight
        : PandoraConversationLayer.compactComposerHeight;
    final viewportHeight = media.size.height > keyboardInset
        ? media.size.height - keyboardInset
        : 0.0;
    final conversationPadding = widget.shellOverlay
        ? const EdgeInsets.only(
            top: 56,
            bottom: 12,
          )
        : EdgeInsets.only(
            top: topInset + headerHeight,
            bottom: composerHeight,
          );
    final viewportSize = Size(media.size.width, viewportHeight);
    final conversationContent = _loadingThread
        ? Padding(
            padding: conversationPadding,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PandoraSimpleColors.muted,
              ),
            ),
          )
        : _messages.isEmpty && _pendingMessage == null && _error == null
            ? Padding(
                padding: conversationPadding,
                child: const _EmptyConversation(),
              )
            : _Conversation(
                threadIdentity: _threadId ?? 'local-chat',
                messages: _messages,
                pendingMessage: _pendingMessage,
                thinking: _submitting,
                activityRequested: _activityTheatreRequested,
                activitySuppressed: _activityTheatreSuppressed,
                activityEvents: _activityController.events,
                activityError: _activityController.publicError,
                inlineError: _error,
                onRetry: (message) => unawaited(_retryFailedTurn(message)),
                onCoreNavigate: widget.onCoreNavigate,
                contentPadding: conversationPadding,
                viewportSize: viewportSize,
              );

    if (widget.shellOverlay) {
      final snapshot = _pickerSnapshot;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            key: const ValueKey<String>('pandora-active-chat-history-offstage'),
            offstage: !_shellHistoryExpanded,
            child: Padding(
              // The app-level conversation is a contextual command layer, not
              // a replacement screen. Keep a substantial portion of the live
              // business workspace visible and interactive above the panel.
              padding: EdgeInsets.fromLTRB(
                10,
                topInset + 10,
                10,
                keyboardInset + composerHeight + 10,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: .66,
                  child: Material(
                    key: const ValueKey<String>('pandora-active-chat-history'),
                    color: const Color(0xFF0A0A0A),
                    elevation: 18,
                    shadowColor: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(child: conversationContent),
                        if (_shellHistoryExpanded)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: KeyedSubtree(
                              key: _headerKey,
                              child: _ChatHeader(
                                active: conversationActive,
                                minimal: true,
                                onNewChat: newChat,
                                onSearchChats: widget.onSearchChats,
                                onMore: widget.onMore,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_pickerOpen && snapshot != null)
            Positioned.fill(
              child: PandoraModelPickerOverlay(
                models: snapshot.models,
                selection: _modelSelection,
                reasoningMode: _reasoningMode,
                localAiEnabled: _pickerLocalAiEnabled,
                localAiAvailable: _pickerLocalAiAvailable,
                localAiModelName: _pickerLocalAiModelName,
                startAtEnd: _pickerStartAtEnd,
                onDismiss: _dismissPicker,
                onModelSelected: _applyPickerModel,
                onReasoningSelected: _applyPickerReasoning,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboardInset,
            child: KeyedSubtree(
              key: _composerKey,
              child: _Composer(
                controller: _objective,
                focusNode: _objectiveFocus,
                attachment: _attachment,
                imageAttachment: _imageAttachment,
                projectContext: _projectContext,
                serviceContext: _serviceContext,
                characterContext: _characterContext,
                error: _error,
                submitting: _submitting,
                disabled: _outcomeUnknown,
                modelLabel: _modelLabel,
                pickerOpen: _pickerOpen,
                onModel: _pickModel,
                showModelControl: !_isCommonWorkspace,
                showContextControls: !_isCommonWorkspace,
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
                onCamera: () => _pickImage(camera: true),
                onPhotos: () => _pickImage(camera: false),
                onAttach: _attach,
                onCharacters:
                    widget.allowCharacterContext ? _pickCharacterContext : null,
                onServices: _pickServiceContext,
                onProjectContext:
                    widget.allowProjectContext ? _pickProjectContext : null,
                onDictate: _dictate,
                onSubmit: _submit,
                onRemoveAttachment: () => setState(() => _attachment = null),
                onRemoveImage: () => setState(() => _imageAttachment = null),
                onRemoveCharacterContext: _removeCharacterContext,
                onRemoveServiceContext: _removeServiceContext,
                onRemoveProjectContext: _removeProjectContext,
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: PandoraSimpleColors.canvas,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: conversationContent),
          if (conversationActive)
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: KeyedSubtree(
                key: _headerKey,
                child: _ChatHeader(
                  active: true,
                  onNewChat: newChat,
                  onSearchChats: widget.onSearchChats,
                  onMore: widget.onMore,
                ),
              ),
            ),
          if (_pickerOpen && _pickerSnapshot != null)
            Positioned.fill(
              child: PandoraModelPickerOverlay(
                models: _pickerSnapshot!.models,
                selection: _modelSelection,
                reasoningMode: _reasoningMode,
                localAiEnabled: _pickerLocalAiEnabled,
                localAiAvailable: _pickerLocalAiAvailable,
                localAiModelName: _pickerLocalAiModelName,
                startAtEnd: _pickerStartAtEnd,
                onDismiss: _dismissPicker,
                onModelSelected: _applyPickerModel,
                onReasoningSelected: _applyPickerReasoning,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboardInset,
            child: KeyedSubtree(
              key: _composerKey,
              child: _Composer(
                controller: _objective,
                focusNode: _objectiveFocus,
                attachment: _attachment,
                imageAttachment: _imageAttachment,
                projectContext: _projectContext,
                serviceContext: _serviceContext,
                characterContext: _characterContext,
                error: _error,
                submitting: _submitting,
                disabled: _outcomeUnknown,
                modelLabel: _modelLabel,
                pickerOpen: _pickerOpen,
                onModel: _pickModel,
                showModelControl: !_isCommonWorkspace,
                showContextControls: !_isCommonWorkspace,
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
                onCamera: () => _pickImage(camera: true),
                onPhotos: () => _pickImage(camera: false),
                onAttach: _attach,
                onCharacters:
                    widget.allowCharacterContext ? _pickCharacterContext : null,
                onServices: _pickServiceContext,
                onProjectContext:
                    widget.allowProjectContext ? _pickProjectContext : null,
                onDictate: _dictate,
                onSubmit: _submit,
                onRemoveAttachment: () => setState(() => _attachment = null),
                onRemoveImage: () => setState(() => _imageAttachment = null),
                onRemoveCharacterContext: _removeCharacterContext,
                onRemoveServiceContext: _removeServiceContext,
                onRemoveProjectContext: _removeProjectContext,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChatOverflowAction { newChat, more }

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.active,
    required this.onNewChat,
    this.onSearchChats,
    this.onMore,
    this.enterpriseContext,
    this.allowCharacterContext = true,
    this.allowProjectContext = true,
    this.minimal = false,
  });

  final bool active;
  final VoidCallback onNewChat;
  final VoidCallback? onSearchChats;
  final VoidCallback? onMore;
  final Map<String, Object?>? enterpriseContext;
  final bool allowCharacterContext;
  final bool allowProjectContext;
  final bool minimal;

  @override
  Widget build(BuildContext context) => PandoraPageHeader(
        title: '',
        actions: [
          if (onSearchChats != null)
            IconButton(
              key: const ValueKey<String>('pandora-recent-chats'),
              tooltip: 'Recent chats',
              onPressed: onSearchChats,
              icon: const Icon(Icons.history_rounded),
              color: PandoraSimpleColors.ink,
            ),
          if (!minimal && !active)
            IconButton(
              key: const ValueKey<String>('pandora-temporary-chat'),
              tooltip: 'Temporary chat',
              onPressed: onNewChat,
              icon: const Icon(Icons.history_toggle_off_rounded),
              color: PandoraSimpleColors.ink,
            )
          else if (!minimal)
            PopupMenuButton<_ChatOverflowAction>(
              key: const ValueKey<String>('pandora-chat-overflow'),
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              color: PandoraSimpleColors.surface,
              onSelected: (action) {
                switch (action) {
                  case _ChatOverflowAction.newChat:
                    onNewChat();
                    break;
                  case _ChatOverflowAction.more:
                    onMore?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<_ChatOverflowAction>(
                  key: ValueKey<String>('pandora-chat-menu-new'),
                  value: _ChatOverflowAction.newChat,
                  child: Row(
                    children: [
                      Icon(Icons.add_comment_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('New chat'),
                    ],
                  ),
                ),
                if (onMore != null)
                  const PopupMenuItem<_ChatOverflowAction>(
                    key: ValueKey<String>('pandora-chat-menu-more'),
                    value: _ChatOverflowAction.more,
                    child: Row(
                      children: [
                        Icon(Icons.more_horiz_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('More'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
        child: PandoraMark(
          key: ValueKey<String>('pandora-logo-only-landing'),
          size: 28,
          color: Colors.white,
        ),
      );
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.threadIdentity,
    required this.messages,
    required this.pendingMessage,
    required this.thinking,
    required this.activityRequested,
    required this.activitySuppressed,
    required this.activityEvents,
    required this.contentPadding,
    required this.viewportSize,
    required this.onRetry,
    this.onCoreNavigate,
    this.activityError,
    this.inlineError,
  });

  final String threadIdentity;
  final List<_ChatMessage> messages;
  final String? pendingMessage;
  final bool thinking;
  final bool activityRequested;
  final bool activitySuppressed;
  final List<PandoraActivityProjection> activityEvents;
  final EdgeInsets contentPadding;
  final Size viewportSize;
  final String? activityError;
  final String? inlineError;
  final ValueChanged<_ChatMessage> onRetry;
  final ValueChanged<PandoraIntelligenceHandoff>? onCoreNavigate;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final ScrollController _scrollController = ScrollController();
  late int _lastRenderedItemCount;
  bool _followLatest = true;

  bool get _hasPending =>
      widget.pendingMessage != null && widget.pendingMessage!.isNotEmpty;
  PandoraActivityProjection? get _presentedActivity =>
      pandoraLatestPresentableActivity(widget.activityEvents);
  bool get _hasMeaningfulActivity =>
      pandoraHasMeaningfulActivity(widget.activityEvents);
  bool get _hasActivitySlot =>
      widget.thinking &&
      !widget.activitySuppressed &&
      (widget.activityRequested || _hasMeaningfulActivity);

  int get _renderedItemCount =>
      widget.messages.length +
      (_hasPending ? 1 : 0) +
      (_hasActivitySlot ? 1 : 0) +
      (widget.inlineError == null ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _lastRenderedItemCount = _renderedItemCount;
    _scheduleScrollToLatest(jump: true);
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextCount = _renderedItemCount;
    final oldPresented = pandoraLatestPresentableActivity(
      oldWidget.activityEvents,
    );
    final nextPresented = _presentedActivity;
    final activityChanged = oldPresented?.eventId != nextPresented?.eventId ||
        oldWidget.activityError != widget.activityError ||
        oldWidget.activityRequested != widget.activityRequested ||
        oldWidget.activitySuppressed != widget.activitySuppressed;
    final threadChanged = oldWidget.threadIdentity != widget.threadIdentity;
    final messagesChanged =
        oldWidget.messages.length != widget.messages.length || threadChanged;
    final userSubmitted =
        oldWidget.pendingMessage != widget.pendingMessage && _hasPending;
    final viewportChanged = oldWidget.contentPadding != widget.contentPadding ||
        oldWidget.viewportSize != widget.viewportSize;
    if (threadChanged || userSubmitted) {
      _followLatest = true;
    }
    if (nextCount != _lastRenderedItemCount ||
        activityChanged ||
        viewportChanged) {
      _lastRenderedItemCount = nextCount;
      _scheduleScrollToLatest(
        jump: threadChanged || viewportChanged,
        force: threadChanged || userSubmitted,
      );
    }
    if (messagesChanged && widget.messages.isNotEmpty) {
      unawaited(_cacheMessages());
    }
  }

  Future<void> _cacheMessages() async {
    if (!mounted || widget.messages.isEmpty) return;
    final localStore = PandoraDependencies.of(context).localStore;
    if (localStore == null) return;
    final cache = PandoraLocalStateCache(localStore);
    try {
      await cache.cacheRecentConversation(
        threadIdentity: widget.threadIdentity,
        messages: widget.messages
            .where((message) => !message.isFailure)
            .map((message) {
          final text = message.text.length <= 4000
              ? message.text
              : message.text.substring(0, 4000);
          return <String, Object?>{
            'role': message.isUser ? 'user' : 'pandora',
            'text': text,
            if (message.coreNavigation != null)
              'inspectHandoff': message.coreNavigation!.inspectionJson,
          };
        }).toList(growable: false),
      );
    } catch (_) {
      // Local conversation cache is never the source of truth.
    }
  }

  void _scheduleScrollToLatest({
    bool jump = false,
    bool force = false,
  }) {
    if (!force && !_followLatest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    final presentedActivity = _presentedActivity;
    Widget? activitySlot;
    if (_hasActivitySlot) {
      final showActivity = !widget.activitySuppressed &&
          (widget.activityRequested || _hasMeaningfulActivity) &&
          (presentedActivity != null || widget.activityError != null);
      activitySlot = showActivity
          ? _ActivityTimelineSlot(
              events: presentedActivity == null
                  ? const <PandoraActivityProjection>[]
                  : <PandoraActivityProjection>[presentedActivity],
              error: widget.activityError,
            )
          : const _PandoraThinkingBubble();
    }

    for (final message in widget.messages) {
      if (message.text.trim().isEmpty) continue;
      items.add(
        _ChatBubble(
          message: message,
          onCoreNavigate: widget.onCoreNavigate,
          onRetry: message.retryObjective == null
              ? null
              : () => widget.onRetry(message),
        ),
      );
    }
    if (_hasPending) {
      items.add(
        _ChatBubble(message: _ChatMessage.user(widget.pendingMessage!)),
      );
    }
    if (activitySlot != null) items.add(activitySlot);
    if (widget.inlineError != null && widget.inlineError!.trim().isNotEmpty) {
      items.add(_InlineConversationError(message: widget.inlineError!));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) {
          _followLatest = notification.metrics.extentAfter < 96;
        }
        return false;
      },
      child: ListView.separated(
        controller: _scrollController,
        reverse: false,
        padding: EdgeInsets.fromLTRB(
          12,
          widget.contentPadding.top + 10,
          12,
          widget.contentPadding.bottom + 14,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: items.length,
        itemBuilder: (context, index) => items[index],
        separatorBuilder: (_, __) => const SizedBox(height: 18),
      ),
    );
  }
}

class _ActivityTimelineSlot extends StatelessWidget {
  const _ActivityTimelineSlot({required this.events, this.error});

  final List<PandoraActivityProjection> events;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('ask' '-pandora-activity-theatre'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (events.isNotEmpty) PandoraActivityTimelineView(events: events),
            if (error != null) ...[
              if (events.isNotEmpty) const SizedBox(height: 8),
              Semantics(
                container: true,
                label: error,
                child: Text(
                  error!,
                  key: const ValueKey<String>(
                    'ask' '-pandora-activity-integrity-error',
                  ),
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

class _InlineConversationError extends StatelessWidget {
  const _InlineConversationError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        key: const ValueKey<String>('pandora-chat-inline-error'),
        style: TextStyle(
          color: Colors.white.withValues(alpha: .46),
          fontSize: 12.5,
          height: 1.4,
        ),
      );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onRetry, this.onCoreNavigate});
  final _ChatMessage message;
  final VoidCallback? onRetry;
  final ValueChanged<PandoraIntelligenceHandoff>? onCoreNavigate;

  @override
  Widget build(BuildContext context) {
    if (message.isFailure) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  message.text,
                  key: const ValueKey<String>('pandora-chat-message-error'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .50),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  key: const ValueKey<String>('pandora-chat-retry'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 15.5,
                  height: 1.42,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: PandoraMark(size: 20, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: 'Pandora: ${message.text}',
                child: ExcludeSemantics(
                  child: SelectableText(
                    message.text,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 15.5,
                      height: 1.52,
                    ),
                  ),
                ),
              ),
              if (message.coreNavigation != null && onCoreNavigate != null)
                TextButton.icon(
                  key: const ValueKey('pandora-core-inspect-action'),
                  onPressed: () => onCoreNavigate!(message.coreNavigation!),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(message.coreNavigation!.request.trim().isEmpty
                      ? 'Open details'
                      : message.coreNavigation!.request),
                ),
              if (message.authorizationUrl != null)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    message.authorizationUrl!,
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Continue to Meta'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PandoraThinkingBubble extends StatelessWidget {
  const _PandoraThinkingBubble();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const PandoraMark(size: 24, color: Colors.white),
          const SizedBox(width: 11),
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: PandoraSimpleColors.muted,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Thinking through the request…',
              style: const TextStyle(
                color: PandoraSimpleColors.muted,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.attachment,
    required this.imageAttachment,
    required this.projectContext,
    required this.serviceContext,
    required this.characterContext,
    required this.error,
    required this.submitting,
    required this.disabled,
    required this.modelLabel,
    required this.pickerOpen,
    required this.onModel,
    this.showModelControl = true,
    this.showContextControls = true,
    required this.onChanged,
    required this.onCamera,
    required this.onPhotos,
    required this.onAttach,
    required this.onCharacters,
    required this.onServices,
    required this.onProjectContext,
    required this.onDictate,
    required this.onSubmit,
    required this.onRemoveAttachment,
    required this.onRemoveImage,
    required this.onRemoveCharacterContext,
    required this.onRemoveServiceContext,
    required this.onRemoveProjectContext,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PandoraTextAttachment? attachment;
  final PandoraImageAttachment? imageAttachment;
  final PandoraProjectContext? projectContext;
  final PandoraCapabilityProvider? serviceContext;
  final PandoraCharacterProfile? characterContext;
  final String? error;
  final bool submitting;
  final bool disabled;
  final String modelLabel;
  final bool pickerOpen;
  final VoidCallback onModel;
  final bool showModelControl;
  final bool showContextControls;
  final VoidCallback onChanged;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onAttach;
  final VoidCallback? onCharacters;
  final VoidCallback onServices;
  final VoidCallback? onProjectContext;
  final VoidCallback onDictate;
  final VoidCallback onSubmit;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onRemoveImage;
  final VoidCallback onRemoveCharacterContext;
  final VoidCallback onRemoveServiceContext;
  final VoidCallback onRemoveProjectContext;

  bool get _hasContext =>
      attachment != null ||
      imageAttachment != null ||
      projectContext != null ||
      serviceContext != null ||
      characterContext != null;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasContext)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (attachment != null)
                          _CompactContextToken(
                            icon: Icons.description_outlined,
                            label: attachment!.name,
                            onRemove: onRemoveAttachment,
                          ),
                        if (imageAttachment != null)
                          _CompactContextToken(
                            icon: Icons.image_outlined,
                            label: imageAttachment!.name,
                            onRemove: onRemoveImage,
                          ),
                        if (characterContext != null)
                          KeyedSubtree(
                            key: const ValueKey<String>(
                              'ask-pandora-character-context',
                            ),
                            child: _CompactContextToken(
                              icon: Icons.face_retouching_natural_outlined,
                              label: 'Character · ${characterContext!.name}',
                              onRemove: onRemoveCharacterContext,
                            ),
                          ),
                        if (serviceContext != null)
                          _CompactContextToken(
                            icon: Icons.extension_outlined,
                            label: serviceContext!.label,
                            onRemove: onRemoveServiceContext,
                          ),
                        if (projectContext != null)
                          _CompactContextToken(
                            icon: Icons.workspaces_outline,
                            label: projectContext!.name,
                            onRemove: onRemoveProjectContext,
                          ),
                      ],
                    ),
                  ),
                ),
              KeyedSubtree(
                key: const ValueKey<String>('ask-pandora-composer-dock'),
                child: Container(
                  key: const ValueKey<String>('ask-pandora-composer'),
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (showContextControls)
                        _CompactAttachmentMenu(
                          disabled: disabled || submitting,
                          onCamera: onCamera,
                          onPhotos: onPhotos,
                          onAttach: onAttach,
                          onCharacters: onCharacters,
                          onServices: onServices,
                          onProjectContext: onProjectContext,
                        ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey<String>('ask-pandora-objective'),
                          controller: controller,
                          focusNode: focusNode,
                          readOnly: disabled,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 4000,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText:
                                submitting ? 'Follow up' : 'Message Pandora…',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: .40),
                              fontSize: 16.5,
                              fontWeight: FontWeight.w400,
                            ),
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.fromLTRB(3, 10, 3, 10),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            height: 1.25,
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                      if (showModelControl)
                        _CompactModelControl(
                          label: modelLabel,
                          open: pickerOpen,
                          enabled: !disabled && !submitting,
                          onTap: onModel,
                        ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          final empty = value.text.trim().isEmpty;
                          final voiceReady = !submitting && empty;
                          final cancelReady = submitting && empty;
                          final VoidCallback action = () {
                            if (disabled) return;
                            final current = controller.text.trim();
                            if (!submitting && current.isEmpty) {
                              onDictate();
                              return;
                            }
                            onSubmit();
                          };
                          return SizedBox.square(
                            dimension: 40,
                            child: IconButton(
                              key: const ValueKey<String>('ask-pandora-submit'),
                              tooltip: voiceReady
                                  ? 'Voice input'
                                  : (cancelReady ? 'Stop' : 'Send'),
                              padding: EdgeInsets.zero,
                              splashRadius: 20,
                              onPressed: disabled ? null : action,
                              icon: Icon(
                                voiceReady
                                    ? Icons.mic_none_rounded
                                    : cancelReady
                                        ? Icons.stop_rounded
                                        : Icons.arrow_upward_rounded,
                                color: disabled
                                    ? Colors.white.withValues(alpha: .28)
                                    : Colors.white.withValues(alpha: .86),
                                size: voiceReady ? 21 : 20,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 5),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CompactAttachmentMenu extends StatelessWidget {
  const _CompactAttachmentMenu({
    required this.disabled,
    required this.onCamera,
    required this.onPhotos,
    required this.onAttach,
    required this.onCharacters,
    required this.onServices,
    required this.onProjectContext,
  });

  final bool disabled;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onAttach;
  final VoidCallback? onCharacters;
  final VoidCallback onServices;
  final VoidCallback? onProjectContext;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        alignmentOffset: const Offset(0, -8),
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF151515)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        menuChildren: [
          _ComposerMenuItem(
            key: const ValueKey<String>('ask-pandora-menu-camera'),
            label: 'Camera',
            icon: Icons.camera_alt_outlined,
            onPressed: onCamera,
          ),
          _ComposerMenuItem(
            key: const ValueKey<String>('ask-pandora-menu-photos'),
            label: 'Photos',
            icon: Icons.photo_outlined,
            onPressed: onPhotos,
          ),
          _ComposerMenuItem(
            key: const ValueKey<String>('ask-pandora-menu-files'),
            label: 'Files',
            icon: Icons.insert_drive_file_outlined,
            onPressed: onAttach,
          ),
          if (onCharacters != null)
            _ComposerMenuItem(
              key: const ValueKey<String>('ask-pandora-menu-characters'),
              label: 'Characters',
              icon: Icons.face_retouching_natural_outlined,
              onPressed: onCharacters!,
            ),
          _ComposerMenuItem(
            key: const ValueKey<String>('ask-pandora-menu-services'),
            label: 'Services',
            icon: Icons.extension_outlined,
            onPressed: onServices,
          ),
          if (onProjectContext != null)
            _ComposerMenuItem(
              key: const ValueKey<String>('ask-pandora-menu-project-context'),
              label: 'Project context',
              icon: Icons.workspaces_outline,
              onPressed: onProjectContext!,
            ),
        ],
        builder: (context, menuController, child) => SizedBox.square(
          dimension: 40,
          child: IconButton(
            key: const ValueKey<String>('ask-pandora-plus'),
            tooltip: 'Open menu',
            padding: EdgeInsets.zero,
            splashRadius: 20,
            onPressed: disabled
                ? null
                : () => menuController.isOpen
                    ? menuController.close()
                    : menuController.open(),
            icon: Icon(
              Icons.add_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: .45),
            ),
          ),
        ),
      );
}

class _CompactModelControl extends StatelessWidget {
  const _CompactModelControl({
    required this.label,
    required this.open,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool open;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (label == 'Auto') {
      return GestureDetector(
        key: const ValueKey<String>('ask-pandora-model-control'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox.square(
          dimension: 40,
          child: Icon(
            Icons.tune_rounded,
            size: 18,
            color: Colors.white.withValues(
              alpha: enabled ? (open ? .90 : .45) : .22,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      key: const ValueKey<String>('ask-pandora-model-control'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Container(
          height: 26,
          constraints: const BoxConstraints(maxWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .065),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              fontSize: 12.5,
              height: 1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactContextToken extends StatelessWidget {
  const _CompactContextToken({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white.withValues(alpha: .42)),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .44),
                  fontSize: 11.5,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: Colors.white.withValues(alpha: .34),
                ),
              ),
            ),
          ],
        ),
      );
}

class _CharacterContextSheet extends StatelessWidget {
  const _CharacterContextSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Characters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Private character conversations use prepared memory and the local model.',
                style: TextStyle(color: PandoraSimpleColors.muted),
              ),
              const SizedBox(height: 12),
              ...PandoraCharacterApi.availableCharacters.map(
                (character) => ListTile(
                  key: ValueKey<String>('character-${character.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.face_retouching_natural_outlined),
                  ),
                  title: Text(character.name),
                  subtitle: Text(character.description),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(character),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ServiceContextSheet extends StatelessWidget {
  const _ServiceContextSheet({required this.providers});

  final List<PandoraCapabilityProvider> providers;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Services',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: providers.isEmpty
                    ? const Center(
                        child: Text(
                          'No verified service state is available.',
                          style: TextStyle(color: PandoraSimpleColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                        itemCount: providers.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: PandoraSimpleColors.line,
                        ),
                        itemBuilder: (context, index) {
                          final provider = providers[index];
                          return ListTile(
                            title: Text(
                              provider.label,
                              style: const TextStyle(
                                color: PandoraSimpleColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              provider.state,
                              style: const TextStyle(
                                color: PandoraSimpleColors.muted,
                              ),
                            ),
                            trailing: provider.canUseNow
                                ? const Icon(
                                    Icons.check_circle_outline,
                                    color: PandoraSimpleColors.ink,
                                  )
                                : const Icon(
                                    Icons.info_outline_rounded,
                                    color: PandoraSimpleColors.muted,
                                  ),
                            onTap: () => Navigator.of(context).pop(provider),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
}

class _ProjectContextSheet extends StatelessWidget {
  const _ProjectContextSheet({required this.projects});

  final List<PandoraProjectContext> projects;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Project context',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: projects.isEmpty
                    ? const Center(
                        child: Text(
                          'No existing projects are available.',
                          style: TextStyle(color: PandoraSimpleColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                        itemCount: projects.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: PandoraSimpleColors.line,
                        ),
                        itemBuilder: (context, index) {
                          final project = projects[index];
                          return ListTile(
                            title: Text(
                              project.name,
                              style: const TextStyle(
                                color: PandoraSimpleColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              project.repository ?? project.projectKey,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PandoraSimpleColors.muted,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(project),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
}

class _ComposerMenuItem extends StatelessWidget {
  const _ComposerMenuItem({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MenuItemButton(
        onPressed: onPressed,
        leadingIcon: Icon(icon, size: 21),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
          foregroundColor:
              const WidgetStatePropertyAll(PandoraSimpleColors.ink),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      );
}

String _stripInternalContext(String input) {
  final output = <String>[];
  for (final line in input.split('\n')) {
    final trimmed = line.trim();
    final lower = trimmed.toLowerCase();
    final machineJson = trimmed.startsWith('{') &&
        trimmed.endsWith('}') &&
        (trimmed.contains('"surface"') ||
            trimmed.contains('"identityScope"') ||
            trimmed.contains('"enterprise_'));
    if (lower.contains('bounded enterprise page context:') ||
        lower.contains('bounded project context:') ||
        lower.startsWith('operations room contract:') ||
        lower.startsWith(
          'treat this context as navigation and scope information only.',
        ) ||
        lower.startsWith('the authenticated actorrole is authoritative.') ||
        lower.startsWith(
          'never map roles across identityscope namespaces.',
        ) ||
        machineJson) {
      continue;
    }
    output.add(line);
  }
  return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _sanitizeVisiblePandoraText(String input) {
  final clean = _stripInternalContext(input);
  return clean.isEmpty
      ? "I couldn't produce a clean reply for that turn. Please try again."
      : clean;
}

String _sanitizeVisibleUserText(String input) => _stripInternalContext(input);

class _ChatMessage {
  const _ChatMessage._(
    this.text,
    this.isUser,
    this.authorizationUrl, {
    this.retryObjective,
    this.coreNavigation,
    this.isFailure = false,
  });

  _ChatMessage.user(String text)
      : this._(_sanitizeVisibleUserText(text), true, null);
  _ChatMessage.pandora(String text,
      {Uri? authorizationUrl, PandoraIntelligenceHandoff? coreNavigation})
      : this._(
          _sanitizeVisiblePandoraText(text),
          false,
          authorizationUrl?.scheme == 'https' &&
                  authorizationUrl?.host == 'www.facebook.com' &&
                  authorizationUrl?.path.endsWith('/dialog/oauth') == true
              ? authorizationUrl
              : null,
          coreNavigation: coreNavigation == null
              ? null
              : PandoraIntelligenceHandoff.inspectFromJson(
                  coreNavigation.inspectionJson),
        );
  _ChatMessage.failure(String text, {String? retryObjective})
      : this._(
          _sanitizeVisiblePandoraText(text),
          false,
          null,
          retryObjective: retryObjective,
          isFailure: true,
        );

  final String text;
  final bool isUser;
  final Uri? authorizationUrl;
  final PandoraIntelligenceHandoff? coreNavigation;
  final String? retryObjective;
  final bool isFailure;
}
