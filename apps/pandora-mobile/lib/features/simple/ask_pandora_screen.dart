import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/activity/pandora_activity_presentation_policy.dart';
import '../../core/activity/pandora_activity_timeline_controller.dart';
import '../../core/activity/pandora_activity_timeline_view.dart';
import '../../core/chat/pandora_chat.dart';
import '../../core/data/pandora_activity_stream_api.dart';
import '../../core/data/pandora_character_api.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/device/pandora_calendar_action_executor.dart';
import '../../core/device/pandora_calendar_command.dart';
import '../../core/device/pandora_communication_action_executor.dart';
import '../../core/device/pandora_communication_command.dart';
import '../../core/diagnostics/diagnostic_event.dart';
import '../../core/local/pandora_device_activity_local_sync.dart';
import '../../core/local/pandora_local_state_cache.dart';
import '../../core/local/pandora_local_sync_coordinator.dart';
import '../../core/local_ai/pandora_local_ai.dart';
import '../../core/local_ai/pandora_local_ai_runtime.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../enterprise/plp_staff_task_action.dart';
import 'chat/pandora_chat_composer.dart';
import 'chat/pandora_chat_presentation_controller.dart';
import 'chat/pandora_chat_viewport.dart';
import 'pandora_model_picker.dart';
import 'pandora_simple_ui.dart';

part 'chat/pandora_chat_action_adapters.dart';
part 'chat/pandora_chat_activity_details.dart';
part 'chat/pandora_chat_context_actions.dart';
part 'chat/pandora_chat_diagnostics.dart';
part 'chat/pandora_chat_history.dart';

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
    this.onPresentationChanged,
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
  final ValueChanged<PandoraChatPresentationState>? onPresentationChanged;
  final ValueChanged<bool>? onHistoryVisibilityChanged;

  @override
  State<AskPandoraScreen> createState() => AskPandoraScreenState();
}

class AskPandoraScreenState extends State<AskPandoraScreen>
    with WidgetsBindingObserver {
  final TextEditingController _objective = TextEditingController();
  final FocusNode _objectiveFocus = FocusNode();
  final PandoraChatViewportController _viewport =
      PandoraChatViewportController();
  final ValueNotifier<PandoraComposerState> _composerState =
      ValueNotifier(const PandoraComposerState());
  late final PandoraChatPresentationController _presentation;
  PandoraChatController? _controller;
  PandoraChatController get _chat => _controller!;
  late PandoraDependencies _dependencies;
  PandoraConversationStore? _store;
  bool _persistenceReady = false;
  bool _resetting = false;
  Timer? _saveTimer;
  final Map<String, Completer<String?>> _completions = {};
  final Set<String> _executing = {};
  final Map<String, _ChatTimingObservation> _timings = {};
  final Set<String> _reconciling = {};
  final Map<String, _CapturedChatInput> _inputs = {};
  final Map<String, _ChatExecutionRoute> _routes = {};
  final Map<String, Uri> _authorizationLinks = {};
  PandoraChatAttemptToken? _nativeGeneration;
  Completer<void>? _nativeSettled;
  Future<void> _nativeReset = Future<void>.value();
  bool _voiceActive = false;
  bool _shellHistoryExpanded = false;
  double _composerHeight = PandoraChatComposer.minimumExtent;
  PandoraTextAttachment? _attachment;
  PandoraImageAttachment? _imageAttachment;
  PandoraProjectContext? _projectContext;
  PandoraCapabilityProvider? _serviceContext;
  PandoraCharacterProfile? _characterContext;
  String? _characterSessionId;
  TransitionRoute<dynamic>? _contextRoute;
  int? _contextRouteIntent;
  Future<void> _contextRouteClosing = Future<void>.value();
  PandoraCharacterApi? _characterApi;
  PandoraCharacterApi get _characterClient =>
      _characterApi ??= PandoraCharacterApi();
  PandoraChatModelPickerSnapshot? _pickerSnapshot;
  String? _pickerError;
  int _pickerRequest = 0;
  bool _pickerLocalAiEnabled = false;
  bool _pickerLocalAiAvailable = false;
  String? _pickerLocalAiModelName;
  bool _pickerStartAtEnd = false;

  PandoraChatPresentationController get presentationController => _presentation;
  bool get _pickerOpen =>
      _presentation.value.surface == PandoraChatSurface.picker;
  bool get hasPendingScopeWork => _controller?.state.hasPendingWork ?? false;
  bool get _isCommonWorkspace {
    final selected = widget.enterpriseContext?['selectedObject'];
    return selected is Map &&
        selected['adapterKey'] == 'enterprise_core_v1' &&
        const {'member', 'administrator'}.contains(selected['workspaceMode']);
  }

  @visibleForTesting
  PandoraChatSessionState get debugChatState => _chat.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presentation =
        PandoraChatPresentationController(composerFocus: _objectiveFocus)
          ..addListener(_presentationChanged);
    _objective.addListener(_draftChanged);
    _shellHistoryExpanded =
        widget.shellOverlay && widget.initialHistoryExpanded;
    unawaited(PandoraLocalAiPreference.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _presentation.attachView(View.of(context));
    final dependencies = PandoraDependencies.of(context);
    final userId = dependencies.auth.currentSession?.userId;
    final scope =
        '${userId ?? 'local'}:${dependencies.intelligence?.organizationId ?? 'device'}';
    if (_controller?.state.scopeId == scope) {
      _dependencies = dependencies;
      return;
    }
    _saveTimer?.cancel();
    _dismissContextRoute(afterFrame: true);
    final prior = _controller;
    if (prior != null) {
      prior.removeListener(_chatChanged);
      final priorStore = _store;
      if (_persistenceReady && priorStore != null) {
        unawaited(priorStore.save(prior.state));
      }
      prior.dispose();
    }
    _dependencies = dependencies;
    _store = userId == null || dependencies.localStore == null
        ? null
        : PandoraConversationStore(dependencies.localStore!, scopeId: scope);
    _controller = PandoraChatController(
        scopeId: scope, initialScopeEpoch: _store?.nextScopeEpoch ?? 0);
    _persistenceReady = false;
    _inputs.clear();
    _routes.clear();
    _authorizationLinks.clear();
    _pickerRequest += 1;
    _pickerSnapshot = null;
    _pickerError = null;
    final initial = widget.initialPrompt?.trim() ?? '';
    if (initial.isNotEmpty) _chat.setDraft(initial);
    _objective.value = TextEditingValue(
      text: _chat.state.draft.text,
      selection: TextSelection.collapsed(offset: _chat.state.draft.text.length),
    );
    _chat.addListener(_chatChanged);
    _updateComposerProjection();
    unawaited(_restoreConversation(_chat, _store));
    if (_isPlpEnterpriseContext) unawaited(_prewarmPlpLocalAiIfSafe());
  }

  Future<void> _restoreConversation(
      PandoraChatController controller, PandoraConversationStore? store) async {
    final revision = controller.state.revision;
    try {
      final snapshot = await store?.loadActive();
      if (!mounted || !identical(controller, _controller)) return;
      if (snapshot != null) {
        controller.restore(snapshot.state, expectedRevision: revision);
      }
    } catch (_) {
      // An unreadable local snapshot never creates an identity-free transcript.
    } finally {
      if (mounted && identical(controller, _controller)) {
        _persistenceReady = true;
        if (controller.state.revision != revision) _scheduleSave();
        unawaited(_reconcilePending());
      }
    }
  }

  Future<T?> presentContextRoute<T>(PopupRoute<T> route,
          {int? expectedIntent}) =>
      _presentContextRoute(route, expectedIntent: expectedIntent);

  Future<T?> _presentContextRoute<T>(PopupRoute<T> route,
      {int? expectedIntent, bool closeOnComplete = true}) async {
    final owner = _chat;
    final epoch = owner.state.scopeEpoch;
    var intent = expectedIntent;
    if (intent == null) {
      final opening = _presentation.showContext();
      intent = _presentation.value.intentRevision;
      if (!await opening) return null;
    }
    await _contextRouteClosing;
    bool ownsIntent() =>
        mounted &&
        identical(_controller, owner) &&
        owner.state.scopeEpoch == epoch &&
        _presentation.value.intentRevision == intent &&
        _presentation.value.surface == PandoraChatSurface.context;
    if (!mounted || !ownsIntent()) return null;
    _contextRoute = route;
    _contextRouteIntent = intent;
    final result = await Navigator.of(context).push(route);
    await route.completed;
    if (identical(_contextRoute, route)) {
      _contextRoute = null;
      _contextRouteIntent = null;
    }
    if (!ownsIntent()) return null;
    if (closeOnComplete) _presentation.closeSurface();
    return result;
  }

  void _dismissContextRoute({bool afterFrame = false}) {
    final route = _contextRoute;
    if (route == null) return;
    _contextRoute = null;
    _contextRouteIntent = null;
    _contextRouteClosing = route.completed.then((_) {});
    void remove() {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }

  void _draftChanged() {
    final controller = _controller;
    if (controller != null) controller.setDraft(_objective.text);
  }

  void _chatChanged() {
    if (!mounted) return;
    final state = _chat.state;
    if (_objective.text != state.draft.text) {
      _objective.value = TextEditingValue(
        text: state.draft.text,
        selection: TextSelection.collapsed(offset: state.draft.text.length),
      );
    }
    _updateComposerProjection();
    for (final turn in state.turns.where((t) => t.phase.isTerminal)) {
      final completion = _completions.remove(turn.id);
      if (completion != null && !completion.isCompleted) {
        completion.complete(turn.phase == PandoraChatPhase.completed
            ? turn.reply
            : turn.failure?.message);
      }
    }
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_persistenceReady || _resetting || _store == null) return;
    _saveTimer?.cancel();
    final store = _store!;
    final controller = _chat;
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && identical(controller, _controller)) {
        unawaited(store.save(controller.state));
      }
    });
  }

  void _updateComposerProjection() {
    if (_controller == null) return;
    final state = _chat.state;
    final phase = state.hasUnresolvedOutcome ||
            state.hasUnresolvedAdmission ||
            state.activeTurn?.phase == PandoraChatPhase.cancelling
        ? PandoraComposerPhase.reconciling
        : state.queuedTurn != null
            ? PandoraComposerPhase.queued
            : state.activeTurn != null
                ? PandoraComposerPhase.generating
                : PandoraComposerPhase.idle;
    _composerState.value = PandoraComposerState(
      phase: phase,
      enabled: !state.loadingHistory,
      voiceActive: _voiceActive,
      generationIdentity: state.activeTurn?.attempt == null
          ? null
          : '${state.activeTurn!.attempt!.token.attemptId}:${state.activeTurn!.attempt!.token.deliveryEpoch}',
    );
  }

  void _presentationChanged() {
    if (!mounted) return;
    if (_contextRoute != null &&
        (_presentation.value.surface != PandoraChatSurface.context ||
            _presentation.value.intentRevision != _contextRouteIntent)) {
      _dismissContextRoute();
    }
    setState(() {});
    widget.onPresentationChanged?.call(_presentation.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reconcilePending());
    if (state == AppLifecycleState.paused &&
        _persistenceReady &&
        _store != null) {
      _saveTimer?.cancel();
      unawaited(_store!.save(_chat.state));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissContextRoute(afterFrame: true);
    _saveTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_chatChanged);
      if (_persistenceReady && _store != null) {
        unawaited(_store!.save(controller.state));
      }
      controller.dispose();
    }
    for (final completion in _completions.values) {
      if (!completion.isCompleted) completion.complete(null);
    }
    _presentation.removeListener(_presentationChanged);
    _presentation.dispose();
    _composerState.dispose();
    _objective.removeListener(_draftChanged);
    _objective.dispose();
    _objectiveFocus.dispose();
    super.dispose();
  }

  bool _sameAttempt(PandoraChatAttemptToken token) {
    if (!mounted || _controller == null) return false;
    final state = _chat.state;
    return state.scopeId == token.scopeId &&
        state.scopeEpoch == token.scopeEpoch &&
        state.conversationId == token.conversationId &&
        state.turn(token.turnId)?.attempt?.token == token;
  }

  bool _current(PandoraChatAttemptToken token) =>
      mounted && _controller != null && _chat.isCurrent(token);

  void _notice(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _setHistoryExpanded(bool expanded) {
    if (_shellHistoryExpanded == expanded) return;
    setState(() => _shellHistoryExpanded = expanded);
    if (widget.shellOverlay) widget.onHistoryVisibilityChanged?.call(expanded);
  }

  void showHistory() => _setHistoryExpanded(true);
  void minimizeHistory() => _setHistoryExpanded(false);

  void showExternalFailureMessage(String message) {
    // External page failures are transient page feedback, never orphan chat turns.
    if (!message
        .toLowerCase()
        .contains('could not validate this enterprise page context')) {
      _notice(message);
    }
  }

  Future<String?> submitExternalPrompt(String prompt,
      {bool requestFocus = true}) {
    final normalized = prompt.trim();
    if (normalized.isEmpty || !mounted) return Future<String?>.value(null);
    _chat.setDraft(normalized);
    if (requestFocus) {
      _objectiveFocus.requestFocus();
    } else {
      _objectiveFocus.unfocus();
    }
    return _submitText(normalized);
  }

  Future<String?> _submitText(String text) {
    final state = _chat.state;
    final timing = _ChatTimingObservation();
    if (_characterContext != null &&
        (_attachment != null || _imageAttachment != null)) {
      _notice(
          'Remove the attachment before sending a message in Character mode.');
      return Future<String?>.value(null);
    }
    final input = _CapturedChatInput(
      enterpriseContext: widget.enterpriseContext,
      cloudContext: _cloudEnterpriseContext(),
      projectId: _projectContext?.id,
      serviceSelected: _serviceContext != null,
      characterId: _characterContext?.id,
      characterSessionId: _characterSessionId,
      textAttachment: _attachment,
      imageAttachment: _imageAttachment,
    );
    final admission = _chat.submit(text,
        payload: input.request, draftRevision: state.draft.revision);
    if (!admission.admitted) {
      if (admission.reason == 'follow_up_already_pending') {
        _notice('Your next message is ready. You can keep editing this draft.');
      }
      return Future<String?>.value(null);
    }
    final turnId = admission.turnId!;
    final completion = Completer<String?>();
    _completions[turnId] = completion;
    _inputs[turnId] = input;
    _timings[turnId] = timing;
    if (_timings.length > 100) _timings.remove(_timings.keys.first);
    setState(() {
      _attachment = null;
      _imageAttachment = null;
    });
    showHistory();
    _presentation.closeSurface();
    _viewport.returnToLatest();
    final dispatch = admission.dispatch;
    if (dispatch != null) unawaited(_execute(dispatch));
    return completion.future;
  }

  Future<void> _execute(PandoraChatDispatch dispatch) async {
    final token = dispatch.token;
    _observeSpan(token, 'admitted');
    if (!_current(token) ||
        !_executing.add('${token.attemptId}:${token.deliveryEpoch}')) {
      return;
    }
    final input = _inputs[token.turnId] ??
        _CapturedChatInput.fromRequest(dispatch.request);
    final dependencies = _dependencies;
    try {
      final handled = await _executeLocalRoute(dispatch, input, dependencies);
      if (handled || !_current(token)) return;
      final intelligence = dependencies.intelligence;
      if (intelligence == null) {
        if (input.coreScope) {
          _chat.fail(token,
              message: 'Please sign in again to continue this conversation.',
              recoverable: false);
          return;
        }
        _routes[token.attemptId] = _ChatExecutionRoute.repository;
        _chat.processing(token);
        _chat.recordExecutionReceipt(
            token,
            PandoraChatExecutionReceipt(
                provider: 'device', routing: const {'effectStarted': true}));
        final receipt = await dependencies.repository.ask(
            message: _boundedConversationPrompt(dispatch.message),
            idempotencyKey: token.attemptId);
        if (_current(token)) {
          _chat.complete(token,
              reply: receipt.reply,
              reconciled: true,
              receipt: PandoraChatExecutionReceipt(
                  provider: 'device',
                  routing: const {'executionStatus': 'completed'}));
        }
        return;
      }
      _routes[token.attemptId] = _ChatExecutionRoute.cloud;
      _observeSpan(token, 'request_start');
      await for (final event in intelligence.executeChatTurn(dispatch)) {
        if (!_current(token)) break;
        await _applyWireEvent(dispatch, event);
        if (_sameAttempt(token) &&
            _chat.state.turn(token.turnId)!.phase.isTerminal) {
          _drainQueued();
          break;
        }
      }
    } on PandoraIntelligenceException catch (error) {
      if (_current(token)) {
        _chat.fail(token,
            message: error.message,
            code: error.code,
            recoverable: error.recoverable,
            outcomeUnknown: error.outcomeUnknown);
        if (error.outcomeUnknown &&
            _routes[token.attemptId] == _ChatExecutionRoute.cloud) {
          await _reconcile(token);
        }
      }
    } on PandoraRepositoryException catch (error) {
      if (_current(token)) {
        _chat.fail(token,
            message: error.message,
            recoverable: !error.outcomeMayBeUnknown,
            outcomeUnknown: error.outcomeMayBeUnknown);
      }
    } on PandoraCharacterException catch (error) {
      if (_current(token)) {
        _chat.fail(token,
            message: error.message, recoverable: false, outcomeUnknown: true);
      }
    } catch (_) {
      if (_current(token)) {
        final unknown = _routes[token.attemptId] != null;
        _chat.fail(token,
            message: unknown
                ? 'Checking the outcome of this message…'
                : 'This message could not be started. You can retry it.',
            outcomeUnknown: unknown);
        if (_routes[token.attemptId] == _ChatExecutionRoute.cloud) {
          await _reconcile(token);
        }
      }
    } finally {
      _executing.remove('${token.attemptId}:${token.deliveryEpoch}');
      if (_sameAttempt(token)) _drainQueued();
    }
  }

  Future<void> _applyWireEvent(
      PandoraChatDispatch dispatch, PandoraChatWireEvent event,
      {bool reconciled = false}) async {
    final token = dispatch.token;
    if (!_current(token)) return;
    if (event.admissionCancelled) {
      event.requireIdentity(
          organizationId: _dependencies.intelligence!.organizationId,
          turnId: token.turnId,
          attemptId: token.attemptId,
          generation: token.generation);
      _chat.cancel(token,
          threadId: event.threadId,
          sequence: event.sequence,
          receipt: _wireReceipt(event));
      return;
    }
    event.requireIdentity(
      organizationId: _dependencies.intelligence!.organizationId,
      turnId: token.turnId,
      attemptId: token.attemptId,
      generation: token.generation,
      threadId: _chat.state.threadId ?? dispatch.threadId,
    );
    final status = event.status;
    if (status == 'accepted') {
      _observeSpan(token, 'backend_accepted');
      final accepted = _chat.accept(token,
          threadId: event.threadId,
          activityJobId: event.activityJobId,
          userMessageId: event.userMessageId,
          turnSequence: (event.data['turnSequence'] as num?)?.toInt(),
          sequence: event.sequence);
      if (accepted) _observeSpan(token, 'acceptance_projected');
      return;
    }
    if (status == 'processing' || event.type == 'processing') {
      _chat.processing(token, sequence: event.sequence);
      return;
    }
    if (event.textDelta.isNotEmpty) {
      final projected = _chat.stream(token,
          delta: event.textDelta,
          sequence: event.sequence,
          streamSequence: event.streamSequence);
      if (projected) _observeContent(token);
      return;
    }
    if (status == 'completed') {
      final turn = event.turn!;
      var reply = turn.reply;
      final handoff = turn.handoff;
      if (!reconciled &&
          _chat.state.turn(token.turnId)?.attempt?.cancellationRequested !=
              true &&
          handoff?.source == 'project_workspace_change') {
        _setRoute(dispatch, _ChatExecutionRoute.project, 'project');
        final addendum = await _executeProjectHandoff(dispatch, handoff!);
        if (addendum != null) reply = '$reply\n\n$addendum';
      }
      if (!_current(token)) return;
      final accepted = _chat.complete(token,
          reply: reply,
          threadId: event.threadId,
          assistantMessageId: event.assistantMessageId,
          sequence: event.sequence,
          reconciled: reconciled ||
              _chat.state.turn(token.turnId)?.attempt?.cancellationRequested ==
                  true,
          receipt: _wireReceipt(event));
      if (!accepted) return;
      _observeSpan(token, 'generation_completed');
      if (_chat.state.turn(token.turnId)?.phase == PandoraChatPhase.completed) {
        _observeContent(token);
      }
      if (turn.authorizationUrl != null) {
        _authorizationLinks[token.turnId] = turn.authorizationUrl!;
        if (!kIsWeb && _sameAttempt(token)) {
          unawaited(_openAuthorization(turn.authorizationUrl!, token));
        }
      }
      if (handoff?.kind == 'core_navigation' &&
          handoff?.action != 'inspect' &&
          !reconciled &&
          _sameAttempt(token)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sameAttempt(token)) widget.onCoreNavigate?.call(handoff!);
        });
      }
      return;
    }
    if (status == 'cancelled' || status == 'canceled') {
      _chat.cancel(token,
          threadId: event.threadId,
          sequence: event.sequence,
          receipt: _wireReceipt(event));
      return;
    }
    if (status == 'superseded') {
      _chat.fail(token,
          message: 'This earlier message was not completed.',
          recoverable: false,
          sequence: event.sequence);
      return;
    }
    if (event.isTerminal || event.outcomeUnknown) {
      _observeSpan(token, 'generation_failed', failed: true);
      _chat.fail(token,
          message: event.plainMessage,
          code: event.errorCode,
          recoverable: event.recoverable,
          outcomeUnknown: event.outcomeUnknown,
          sequence: event.sequence);
    }
  }

  PandoraChatExecutionReceipt _wireReceipt(PandoraChatWireEvent event) {
    final turn = event.turn;
    final routing = turn?.routing ??
        (event.data['routing'] is Map
            ? Map<String, Object?>.from(event.data['routing'] as Map)
            : const <String, Object?>{});
    return PandoraChatExecutionReceipt(
      provider: routing['executedProvider']?.toString() ??
          routing['resolvedProvider']?.toString() ??
          routing['provider']?.toString(),
      model: routing['executedModel']?.toString() ??
          routing['resolvedModel']?.toString() ??
          routing['model']?.toString(),
      assistantMessageId: event.assistantMessageId,
      inspection: turn?.handoff?.kind == 'core_navigation' &&
              turn?.handoff?.action == 'inspect'
          ? PandoraIntelligenceHandoff.inspectFromJson(
                  turn!.handoff!.inspectionJson)
              ?.inspectionJson
          : null,
      routing: {
        ...routing,
        'executionStatus': event.status,
        if (turn != null) 'conversationLane': turn.conversationLane,
        if (turn != null) 'needsClarification': turn.needsClarification
      },
      usage: turn?.usage ?? const {},
    );
  }

  Future<void> _openAuthorization(
      Uri uri, PandoraChatAttemptToken token) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && _sameAttempt(token)) {
      _notice('The authorization page is ready. Tap Continue to open it.');
    }
  }

  void _drainQueued() {
    if (!mounted) return;
    final next = _chat.takeQueued().dispatch;
    if (next != null) unawaited(_execute(next));
  }

  void _retry(String turnId) {
    final dispatch = _chat.retry(turnId).dispatch;
    if (dispatch != null) {
      _timings[turnId] = _ChatTimingObservation();
      unawaited(_execute(dispatch));
    }
  }

  Future<void> _stop() async {
    final token = _chat.state.activeTurn?.attempt?.token;
    if (token == null || !_chat.requestCancellation(token)) return;
    final route = _routes[token.attemptId];
    if (route == _ChatExecutionRoute.local) {
      PandoraLocalAiRuntime.instance.invalidateConversation();
      final settled = _nativeSettled?.future;
      try {
        await PandoraLocalAi.instance.cancel();
        if (settled != null) {
          await settled.timeout(const Duration(seconds: 8));
        }
        if (_current(token)) {
          _chat.cancel(token,
              receipt: PandoraChatExecutionReceipt(
                  provider: 'local_device',
                  routing: const {'executionStatus': 'cancelled'}));
        }
      } catch (_) {
        if (_current(token)) {
          _chat.fail(token,
              message: 'Checking whether this response stopped…',
              outcomeUnknown: true);
        }
      }
      if (_sameAttempt(token)) _drainQueued();
      return;
    }
    if (route == null) {
      // Admission has not reached an execution adapter. The synchronous fence
      // prevents its awaited preparation from dispatching afterward.
      _chat.cancel(token);
      _drainQueued();
      return;
    }
    if (route != _ChatExecutionRoute.cloud) {
      final effectStarted =
          _chat.state.turn(token.turnId)?.receipt?.routing['effectStarted'] ==
              true;
      if (!effectStarted) {
        _chat.cancel(token,
            receipt: PandoraChatExecutionReceipt(
                provider: 'device',
                routing: const {'executionStatus': 'cancelled'}));
        _drainQueued();
        return;
      }
      // Device writes cannot be declared undone by dismissing their display.
      _chat.fail(token,
          message: 'This action has already started. Checking its outcome…',
          outcomeUnknown: true,
          recoverable: false);
      return;
    }
    try {
      final event = await _dependencies.intelligence!.cancelChatTurn(
          turnId: token.turnId,
          generation: token.generation,
          attemptId: token.attemptId);
      if (_current(token)) {
        await _applyWireEvent(_dispatchFor(token), event, reconciled: true);
      }
    } catch (_) {
      if (_current(token)) await _reconcile(token);
    }
    if (_sameAttempt(token)) _drainQueued();
  }

  Future<void> _cancelHeld(String turnId) async {
    final token = _chat.requestAdmissionCancellation(turnId);
    if (token == null) return;
    try {
      final event = await _dependencies.intelligence!.cancelChatTurn(
          turnId: token.turnId,
          generation: token.generation,
          attemptId: token.attemptId);
      if (_current(token)) {
        await _applyWireEvent(_dispatchFor(token), event, reconciled: true);
      }
    } catch (_) {
      if (_current(token)) await _reconcile(token);
    }
    if (_sameAttempt(token)) _drainQueued();
  }

  PandoraChatDispatch _dispatchFor(PandoraChatAttemptToken token) =>
      PandoraChatDispatch(
        token: token,
        turn: _chat.state.turn(token.turnId)!,
        threadId: _chat.state.threadId,
        isRetry: token.generation > 1,
        expectedGeneration: token.generation > 1 ? token.generation - 1 : null,
      );

  Future<void> _reconcile(PandoraChatAttemptToken token) async {
    if (!_current(token) ||
        !_reconciling.add('${token.attemptId}:${token.deliveryEpoch}')) {
      return;
    }
    final turn = _chat.state.turn(token.turnId)!;
    final source = turn.receipt?.provider;
    if (const {'local_device', 'device', 'character', 'project'}
        .contains(source)) {
      _reconciling.remove('${token.attemptId}:${token.deliveryEpoch}');
      _notice('Check this action in Activity before sending it again.');
      return;
    }
    try {
      final event =
          await _dependencies.intelligence?.readChatTurn(turnId: token.turnId);
      if (!_current(token)) return;
      if (event == null &&
          token.generation == 1 &&
          _chat.markNotAdmitted(token)) {
        return;
      }
      if (event != null &&
          event.generation == token.generation - 1 &&
          event.recoverable &&
          const {
            'failed_recoverably',
            'failed_recoverable',
            'recoverable_failure'
          }.contains(event.status)) {
        event.requireIdentity(
            organizationId: _dependencies.intelligence!.organizationId,
            turnId: token.turnId,
            threadId: _chat.state.threadId);
        final previous = turn.attempts.where((a) =>
            a.token.generation == event.generation &&
            a.token.attemptId == event.attemptId);
        if (previous.isNotEmpty && _chat.markNotAdmitted(token)) return;
      }
      if (event != null) {
        await _applyWireEvent(_dispatchFor(token), event, reconciled: true);
      }
      if (_current(token) && (event == null || !event.isTerminal)) {
        _chat.fail(token,
            message:
                'This message is still being checked. It will not be sent twice.',
            outcomeUnknown: true,
            recoverable: false);
      }
    } catch (_) {
      if (_current(token)) {
        _chat.fail(token,
            message:
                'Reconnect to check this message. It will not be sent twice.',
            outcomeUnknown: true,
            recoverable: false);
      }
    } finally {
      _reconciling.remove('${token.attemptId}:${token.deliveryEpoch}');
      if (_sameAttempt(token)) _drainQueued();
    }
  }

  Future<void> _reconcilePending() async {
    if (!mounted || _controller == null) return;
    final tokens = _chat.state.turns
        .where((t) => t.phase == PandoraChatPhase.reconciling)
        .map((t) => t.attempt?.token)
        .whereType<PandoraChatAttemptToken>()
        .toList();
    for (final token in tokens) {
      if (!mounted) return;
      final turn = _chat.state.turn(token.turnId);
      final localSource = turn?.receipt?.provider;
      if (localSource == null ||
          !const {'local_device', 'device', 'character', 'project'}
              .contains(localSource)) {
        await _reconcile(token);
      }
    }
  }

  void newChat() {
    _resetting = true;
    final accepted = _chat.newChat(resetPreferences: true);
    _resetting = false;
    if (!accepted) {
      _notice(
          'Finish or resolve the current message before starting a new chat.');
      return;
    }
    _saveTimer?.cancel();
    if (_store != null) {
      unawaited(_store!.resetActive(scopeEpoch: _chat.state.scopeEpoch));
    }
    _presentation.closeSurface();
    _pickerRequest += 1;
    _inputs.clear();
    _routes.clear();
    _authorizationLinks.clear();
    final characterId = _characterContext?.id;
    final characterSession = _characterSessionId;
    if (characterId != null && characterSession != null) {
      unawaited(_characterClient
          .reset(characterId: characterId, sessionId: characterSession)
          .catchError((_) {}));
    }
    PandoraLocalAiRuntime.instance.invalidateConversation();
    _nativeReset = _nativeReset
        .then((_) => PandoraLocalAi.instance.resetConversation())
        .catchError((_) {});
    setState(() {
      _attachment = null;
      _imageAttachment = null;
      _projectContext = null;
      _serviceContext = null;
      _characterContext = null;
      _characterSessionId = null;
    });
    showHistory();
    _objectiveFocus.requestFocus();
  }

  Future<void> loadThread(String threadId) async {
    if (threadId == _chat.state.threadId ||
        _dependencies.intelligence == null) {
      return;
    }
    final token = _chat.beginHistoryLoad(threadId);
    if (token == null) {
      _notice('Resolve the current message before changing conversations.');
      return;
    }
    _presentation.closeSurface();
    _pickerRequest += 1;
    _inputs.clear();
    _routes.clear();
    _authorizationLinks.clear();
    showHistory();
    try {
      final cachedFuture = _store?.loadThread(threadId);
      final history = await _dependencies.intelligence!.messages(threadId);
      final cached = await cachedFuture;
      if (!mounted || !_chat.matchesLoad(token)) return;
      if (!_replaceVerifiedHistory(token, history, cached)) {
        _chat.failHistoryLoad(token);
        _notice(
            'This conversation could not be verified. Please open it again.');
      } else {
        unawaited(_reconcilePending());
      }
      setState(() {
        _attachment = null;
        _imageAttachment = null;
        _characterSessionId = null;
      });
    } catch (_) {
      if (mounted && _chat.failHistoryLoad(token)) {
        _notice('This conversation could not be loaded. Try opening it again.');
      }
    }
  }

  Future<void> _dictate() async {
    if (_voiceActive) return;
    final draft = _chat.captureDraftToken();
    _voiceActive = true;
    _updateComposerProjection();
    try {
      final text = await PandoraNativeIo.dictate();
      if (!mounted || !_chat.matchesDraft(draft)) return;
      if (text == null) {
        _notice(
            'Voice input is unavailable. You can use the keyboard microphone.');
        return;
      }
      _chat.applyDraftResult(draft, text);
      _objectiveFocus.requestFocus();
    } finally {
      if (mounted) {
        _voiceActive = false;
        _updateComposerProjection();
      }
    }
  }

  Future<void> _pickModel() async {
    if (_isCommonWorkspace || _dependencies.intelligence == null) return;
    if (_pickerOpen ||
        _presentation.value.pendingSurface == PandoraChatSurface.picker) {
      _dismissPicker();
      return;
    }
    final request = ++_pickerRequest;
    final epoch = _chat.state.scopeEpoch;
    _pickerError = null;
    final showing = _presentation.showPicker();
    unawaited(_loadPicker(request, epoch));
    await showing;
  }

  Future<void> _loadPicker(int request, int epoch) async {
    try {
      final snapshot = await _dependencies.intelligence!
          .modelPicker(threadId: _chat.state.threadId);
      final enabled = await PandoraLocalAiPreference.load();
      PandoraLocalAiStatus? status;
      if (enabled) {
        try {
          status = await PandoraLocalAi.instance
              .status()
              .timeout(const Duration(milliseconds: 600));
        } catch (_) {}
      }
      if (!mounted ||
          request != _pickerRequest ||
          epoch != _chat.state.scopeEpoch ||
          (!_pickerOpen &&
              _presentation.value.pendingSurface !=
                  PandoraChatSurface.picker)) {
        return;
      }
      setState(() {
        _pickerSnapshot = snapshot;
        _pickerLocalAiEnabled = enabled;
        _pickerLocalAiAvailable =
            status?.supported == true && status?.configured == true;
        _pickerLocalAiModelName = status?.modelName;
        _pickerError = null;
      });
    } catch (_) {
      if (mounted &&
          request == _pickerRequest &&
          epoch == _chat.state.scopeEpoch &&
          _pickerOpen) {
        setState(() => _pickerError =
            'Model options could not be loaded. Your selection has not changed.');
      }
    }
  }

  void _dismissPicker() {
    _pickerRequest += 1;
    _presentation.closeSurface();
  }

  PandoraChatModelSelection get _modelSelection {
    final preference = _chat.state.preferences;
    return preference.isAuto
        ? const PandoraChatModelSelection.auto()
        : PandoraChatModelSelection.manual(
            provider: preference.provider!,
            model: preference.model!,
            fallbackMode: preference.fallbackMode,
          );
  }

  PandoraIntelligenceMode get _reasoningMode => PandoraIntelligenceMode.values
      .byName(_chat.state.preferences.reasoningMode);

  PandoraChatPreferences _preferences(
          PandoraChatModelSelection selection, String label) =>
      selection.isAuto
          ? PandoraChatPreferences.auto(
              reasoningMode: _chat.state.preferences.reasoningMode)
          : PandoraChatPreferences.manual(
              provider: selection.provider!,
              model: selection.model!,
              label: label,
              fallbackMode: selection.fallbackMode,
              reasoningMode: _chat.state.preferences.reasoningMode);

  void _applyPickerModel(PandoraModelPickerChoice choice) {
    _chat.setPreferences(_preferences(choice.selection, choice.label));
    _dismissPicker();
  }

  void _applyPickerReasoning(PandoraIntelligenceMode mode) {
    _chat.setPreferences(_chat.state.preferences.copyWithReasoning(mode.name));
    _dismissPicker();
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
      _pickerStartAtEnd = startAtEnd;
      _pickerLocalAiEnabled = localAiEnabled;
      _pickerLocalAiAvailable = localAiAvailable;
      _pickerLocalAiModelName = localAiModelName;
    });
    unawaited(_presentation.showPicker());
  }

  @visibleForTesting
  void debugSetModelSelection(
      PandoraChatModelSelection selection, String label) {
    _chat.setPreferences(_preferences(selection, label));
    _presentation.closeSurface();
  }

  void _refresh(VoidCallback mutation) {
    if (mounted) setState(mutation);
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

  bool _looksLikeTeamAdministrationTurn(String message) {
    final value = message.trim();
    if (value.isEmpty) return false;
    final hasScope = RegExp(
      r'\b(team|member|staff|user|access|invite)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final hasEmail = RegExp(
      r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
      caseSensitive: false,
    ).hasMatch(value);
    final hasRole = RegExp(
      r'\b(owner|admin|operator|member|viewer)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final inviteAction = RegExp(
      r'\b(add|invite|create)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final accessAction = RegExp(
      r'\b(suspend|disable|deactivate|revoke|remove|reactivate|activate|restore)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final roleAction = RegExp(
      r'\b(change|make|set|give|promote|demote)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final staffTask = RegExp(
      r'\bstaff\s+task\b|\btask\s+for\s+staff\b',
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

  Widget? _contextChips() {
    final chips = <Widget>[
      if (_attachment != null)
        _CompactContextToken(
            icon: Icons.insert_drive_file_outlined,
            label: _attachment!.name,
            onRemove: () => setState(() => _attachment = null)),
      if (_imageAttachment != null)
        _CompactContextToken(
            icon: Icons.photo_outlined,
            label: _imageAttachment!.name,
            onRemove: () => setState(() => _imageAttachment = null)),
      if (_projectContext != null)
        _CompactContextToken(
            icon: Icons.workspaces_outline,
            label: _projectContext!.name,
            onRemove: () => unawaited(_removeProjectContext())),
      if (_serviceContext != null)
        _CompactContextToken(
            icon: Icons.extension_outlined,
            label: _serviceContext!.label,
            onRemove: _removeServiceContext),
      if (_characterContext != null)
        _CompactContextToken(
            key: const ValueKey<String>('ask-pandora-character-context'),
            icon: Icons.face_retouching_natural_outlined,
            label: 'Character · ${_characterContext!.name}',
            onRemove: _removeCharacterContext),
    ];
    return chips.isEmpty
        ? null
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: Row(children: chips));
  }

  void _navigateInspection(
      PandoraIntelligenceHandoff handoff, PandoraChatSessionState painted) {
    final live = _chat.state;
    if (!mounted ||
        live.scopeId != painted.scopeId ||
        live.scopeEpoch != painted.scopeEpoch ||
        live.conversationId != painted.conversationId) {
      return;
    }
    final bounded =
        PandoraIntelligenceHandoff.inspectFromJson(handoff.inspectionJson);
    if (bounded != null) widget.onCoreNavigate?.call(bounded);
  }

  Widget _transcript(EdgeInsets padding) {
    final state = _chat.state;
    if (state.loadingHistory) {
      return Padding(
          padding: padding,
          child:
              const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (state.history.isEmpty && state.turns.isEmpty) {
      return Padding(padding: padding, child: const _EmptyConversation());
    }
    final order = <String, int>{
      for (final message in state.history.indexed)
        'history:${message.$2.id}': message.$2.sequence ?? message.$1 + 1,
      for (final turn in state.turns) turn.id: turn.sequence,
    };
    final items = <PandoraChatViewportItem>[
      for (final message in state.history)
        PandoraChatViewportItem(
            id: 'history:${message.id}',
            child: _ChatBubble(
                onCoreNavigate: (handoff) =>
                    _navigateInspection(handoff, state),
                message: message.isUser
                    ? _ChatMessage.user(message.text)
                    : _ChatMessage.pandora(message.text,
                        coreNavigation:
                            PandoraIntelligenceHandoff.inspectFromJson(
                                message.inspection)))),
      for (final turn in state.turns)
        PandoraChatViewportItem(
            id: turn.id,
            child: _ChatTurnView(
              turn: turn,
              latest: turn.id == state.turns.last.id,
              queued: turn.id == state.queuedTurnId,
              canRetry: !state.hasPendingWork ||
                  (turn.failure?.code == 'CHAT_NOT_ADMITTED' &&
                      state.activeTurn == null &&
                      !state.hasUnresolvedOutcome),
              onRetry: () => _retry(turn.id),
              onCheck: () {
                final token = turn.attempt?.token;
                if (token != null) unawaited(_reconcile(token));
              },
              onCancelQueued: () => _chat.cancelQueued(turn.id),
              onCancelHeld: turn.failure?.code == 'CHAT_NOT_ADMITTED'
                  ? () => unawaited(_cancelHeld(turn.id))
                  : null,
              authorizationUrl: _authorizationLinks[turn.id],
              onCoreNavigate: widget.onCoreNavigate == null
                  ? null
                  : (handoff) => _navigateInspection(handoff, state),
              onDetails: turn.attempt?.activityJobId != null &&
                      pandoraShouldRequestActivityTheatre(turn.text,
                          hasAttachment: (turn.request['attachments'] as List?)
                                  ?.isNotEmpty ??
                              false,
                          hasProjectContext: turn.request['projectId'] != null)
                  ? () => unawaited(_showActivityDetails(turn))
                  : null,
            )),
    ]..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    return Semantics(
        identifier:
            'pandora.chat.thread.${state.threadId ?? state.conversationId}',
        child: Semantics(
            identifier: 'pandora.chat.transcript',
            child: PandoraChatViewport(
              threadIdentity: '${state.scopeId}:${state.conversationId}',
              revision: state.revision,
              controller: _viewport,
              items: items,
              padding: padding,
            )));
  }

  @override
  Widget build(BuildContext context) {
    final state = _chat.state;
    final body = LayoutBuilder(builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final safeTop = media.padding.top;
      final safeBottom = media.padding.bottom;
      final active = state.threadId != null ||
          state.turns.isNotEmpty ||
          state.history.isNotEmpty;
      final header = (widget.shellOverlay || active) ? 56.0 : 0.0;
      _presentation.reportLayout(
          viewportSize: constraints.biggest,
          composerExtent: _composerHeight + safeBottom);
      final transcript = _transcript(EdgeInsets.fromLTRB(
          18, safeTop + header + 10, 18, _composerHeight + safeBottom + 16));
      final conversation = Material(
          color: PandoraSimpleColors.canvas,
          child: Stack(fit: StackFit.expand, children: [
            transcript,
            if (header > 0)
              Positioned(
                  top: safeTop,
                  left: 0,
                  right: 0,
                  child: _ChatHeader(
                    active: active,
                    minimal: widget.shellOverlay,
                    onNewChat: newChat,
                    onSearchChats: widget.onSearchChats,
                    onMore: widget.onMore,
                  )),
          ]));
      return Stack(fit: StackFit.expand, children: [
        if (widget.shellOverlay)
          Offstage(
            key: const ValueKey<String>('pandora-active-chat-history-offstage'),
            offstage: !_shellHistoryExpanded,
            child: KeyedSubtree(
                key: const ValueKey<String>('pandora-active-chat-history'),
                child: conversation),
          )
        else
          conversation,
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
                padding: EdgeInsets.only(bottom: safeBottom),
                child: PandoraChatComposer(
                  maxInputExtent: (constraints.maxHeight * .35).clamp(
                      (media.textScaler.scale(16.5) * 1.25 + 32)
                          .clamp(54.0, double.infinity),
                      (media.textScaler.scale(16.5) * 1.25 + 32)
                          .clamp(160.0, double.infinity)),
                  controller: _objective,
                  focusNode: _objectiveFocus,
                  state: _composerState,
                  modelLabel: state.preferences.label,
                  pickerOpen: _pickerOpen,
                  onModelOptions:
                      _isCommonWorkspace ? null : () => unawaited(_pickModel()),
                  onSend: (text) {
                    unawaited(_submitText(text));
                  },
                  onStop: () => unawaited(_stop()),
                  onVoice: () => unawaited(_dictate()),
                  onHeightChanged: (height) {
                    if (mounted && (height - _composerHeight).abs() > .5) {
                      setState(() => _composerHeight = height);
                    }
                  },
                  context: _contextChips(),
                  leading: _isCommonWorkspace
                      ? null
                      : _CompactAttachmentMenu(
                          disabled: state.loadingHistory,
                          onOpen: () => unawaited(_showAttachmentActions()),
                        ),
                ))),
        if (_pickerOpen)
          Positioned.fill(
              child: PandoraModelPickerOverlay(
            models: _pickerSnapshot?.models ?? const [],
            selection: _modelSelection,
            reasoningMode: _reasoningMode,
            localAiEnabled: _pickerLocalAiEnabled,
            localAiAvailable: _pickerLocalAiAvailable,
            localAiModelName: _pickerLocalAiModelName,
            startAtEnd: _pickerStartAtEnd,
            generationActive: state.hasPendingWork,
            error: _pickerError,
            onRetry: () =>
                unawaited(_loadPicker(++_pickerRequest, state.scopeEpoch)),
            onDismiss: _dismissPicker,
            onModelSelected: _applyPickerModel,
            onReasoningSelected: _applyPickerReasoning,
          )),
      ]);
    });
    final coordinated = PopScope(
      canPop: _presentation.value.surface == PandoraChatSurface.none &&
          !_presentation.value.keyboardVisible &&
          !_objectiveFocus.hasFocus &&
          !_presentation.value.transitioning,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _presentation.handleBack();
      },
      child: body,
    );
    return widget.shellOverlay
        ? coordinated
        : Scaffold(
            backgroundColor: PandoraSimpleColors.canvas,
            resizeToAvoidBottomInset: true,
            body: coordinated,
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
    this.minimal = false,
  });

  final bool active;
  final VoidCallback onNewChat;
  final VoidCallback? onSearchChats;
  final VoidCallback? onMore;
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
                PopupMenuItem<_ChatOverflowAction>(
                  key: ValueKey<String>('pandora-chat-menu-new'),
                  value: _ChatOverflowAction.newChat,
                  child: Semantics(
                      identifier: 'pandora.chat.new-chat',
                      child: Row(
                        children: [
                          Icon(Icons.add_comment_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('New chat'),
                        ],
                      )),
                ),
                if (onMore != null)
                  PopupMenuItem<_ChatOverflowAction>(
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

class _ChatTurnView extends StatelessWidget {
  const _ChatTurnView(
      {required this.turn,
      required this.latest,
      required this.queued,
      required this.canRetry,
      required this.onRetry,
      required this.onCheck,
      required this.onCancelQueued,
      this.authorizationUrl,
      this.onDetails,
      this.onCancelHeld,
      this.onCoreNavigate});
  final PandoraChatTurn turn;
  final bool latest;
  final bool queued;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onCheck;
  final VoidCallback onCancelQueued;
  final Uri? authorizationUrl;
  final VoidCallback? onDetails;
  final VoidCallback? onCancelHeld;
  final ValueChanged<PandoraIntelligenceHandoff>? onCoreNavigate;

  @override
  Widget build(BuildContext context) {
    final failed = turn.phase == PandoraChatPhase.failedRecoverably ||
        turn.phase == PandoraChatPhase.failedPermanently;
    final pending = turn.phase.isGenerating && turn.reply.isEmpty;
    final checking = turn.phase == PandoraChatPhase.reconciling ||
        turn.phase == PandoraChatPhase.cancelling;
    return Semantics(
        identifier: 'pandora.chat.turn.${turn.id}',
        container: true,
        child: Semantics(
            identifier: 'pandora.chat.turn.${turn.id}.${turn.phase.name}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                    identifier: 'pandora.chat.user.${turn.id}',
                    child: _ChatBubble(message: _ChatMessage.user(turn.text))),
                const SizedBox(height: 12),
                if (turn.reply.isNotEmpty &&
                    turn.phase != PandoraChatPhase.cancelled &&
                    !failed)
                  Semantics(
                      identifier: 'pandora.chat.response.${turn.id}',
                      child: _ChatBubble(
                          onCoreNavigate: onCoreNavigate,
                          message: _ChatMessage.pandora(turn.reply,
                              coreNavigation:
                                  PandoraIntelligenceHandoff.inspectFromJson(
                                      turn.receipt?.inspection),
                              authorizationUrl: authorizationUrl))),
                if (queued)
                  Row(children: [
                    const Expanded(
                        child: Text('Ready to send next',
                            style: TextStyle(
                                color: PandoraSimpleColors.muted,
                                fontSize: 13))),
                    TextButton(
                        onPressed: onCancelQueued, child: const Text('Remove')),
                  ])
                else if (pending)
                  const _ChatTurnStatus(
                      text: 'Pandora is working…', busy: true),
                if (checking)
                  Row(children: [
                    Expanded(
                        child: _ChatTurnStatus(
                            text: turn.phase == PandoraChatPhase.cancelling
                                ? 'Stopping…'
                                : 'Checking this message…',
                            busy: turn.phase == PandoraChatPhase.cancelling)),
                    if (turn.phase == PandoraChatPhase.reconciling)
                      Semantics(
                          identifier: 'pandora.chat.check.${turn.id}',
                          child: TextButton(
                              onPressed: onCheck,
                              child: const Text('Check again'))),
                  ]),
                if (failed)
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(
                        child: Text(
                            latest
                                ? (turn.failure?.message ??
                                    'This message could not be completed.')
                                : 'This earlier message was not completed.',
                            key: const ValueKey<String>(
                                'pandora-chat-message-error'),
                            style: const TextStyle(
                                color: PandoraSimpleColors.muted,
                                fontSize: 13,
                                height: 1.4))),
                    if (turn.canRetry)
                      Semantics(
                          identifier: 'pandora.chat.retry.${turn.id}',
                          button: true,
                          child: TextButton(
                              key: const ValueKey<String>('pandora-chat-retry'),
                              onPressed: canRetry ? onRetry : null,
                              child: const Text('Retry'))),
                    if (onCancelHeld != null)
                      Semantics(
                          identifier: 'pandora.chat.cancel.${turn.id}',
                          button: true,
                          child: TextButton(
                              onPressed: onCancelHeld,
                              child: const Text('Cancel'))),
                  ]),
                if (turn.phase == PandoraChatPhase.cancelled)
                  _ChatTurnStatus(
                    text: turn.receipt?.routing['executionStatus'] ==
                            'completed'
                        ? 'Stopped displaying this response. The action had already finished.'
                        : 'Stopped',
                  ),
                if (turn.phase == PandoraChatPhase.superseded)
                  const _ChatTurnStatus(
                      text: 'This earlier message was not completed'),
                if (onDetails != null)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                          identifier: 'pandora.chat.details.${turn.id}',
                          child: TextButton(
                              onPressed: onDetails,
                              child: const Text('Details')))),
              ],
            )));
  }
}

class _ChatTurnStatus extends StatelessWidget {
  const _ChatTurnStatus({required this.text, this.busy = false});
  final String text;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: busy,
      child: Row(children: [
        if (busy) ...[
          const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: PandoraSimpleColors.muted)),
          const SizedBox(width: 8),
        ],
        Flexible(
            child: Text(text,
                style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 13,
                    height: 1.4))),
      ]));
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onCoreNavigate});
  final _ChatMessage message;
  final ValueChanged<PandoraIntelligenceHandoff>? onCoreNavigate;

  @override
  Widget build(BuildContext context) {
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
                      height: 1.52),
                )),
              ),
              if (message.coreNavigation != null && onCoreNavigate != null)
                TextButton.icon(
                  key: const ValueKey('pandora-core-inspect-action'),
                  onPressed: () => onCoreNavigate!(message.coreNavigation!),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(message.coreNavigation!.request),
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

class _CompactAttachmentMenu extends StatelessWidget {
  const _CompactAttachmentMenu({required this.disabled, required this.onOpen});
  final bool disabled;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: 48,
      child: IconButton(
          key: const ValueKey<String>('ask-pandora-plus'),
          tooltip: 'Open menu',
          padding: EdgeInsets.zero,
          onPressed: disabled ? null : onOpen,
          icon: const Icon(Icons.add_rounded,
              color: PandoraSimpleColors.ink, size: 25)));
}

class _CompactContextToken extends StatelessWidget {
  const _CompactContextToken({
    super.key,
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
  Widget build(BuildContext context) => ListTile(
        onTap: onPressed,
        leading: Icon(icon, size: 21, color: PandoraSimpleColors.ink),
        title: Text(label,
            style: const TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
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
  _ChatMessage.user(String text)
      : text = _sanitizeVisibleUserText(text),
        isUser = true,
        authorizationUrl = null,
        coreNavigation = null;
  _ChatMessage.pandora(String text,
      {Uri? authorizationUrl, PandoraIntelligenceHandoff? coreNavigation})
      : text = _sanitizeVisiblePandoraText(text),
        isUser = false,
        authorizationUrl = authorizationUrl?.scheme == 'https' &&
                authorizationUrl?.host == 'www.facebook.com' &&
                authorizationUrl?.path.endsWith('/dialog/oauth') == true
            ? authorizationUrl
            : null,
        coreNavigation = coreNavigation == null
            ? null
            : PandoraIntelligenceHandoff.inspectFromJson(
                coreNavigation.inspectionJson);
  final String text;
  final bool isUser;
  final Uri? authorizationUrl;
  final PandoraIntelligenceHandoff? coreNavigation;
}
