import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/data/pandora_core_api.dart';
import '../core/data/pandora_enterprise_api.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/design/pandora_theme.dart';
import '../core/design/pandora_tokens.dart';
import '../core/local_ai/pandora_local_ai.dart';
import '../core/security/pandora_identity_verification.dart';
import '../core/widgets/pandora_mark.dart';
import '../core/widgets/pandora_navigation.dart';
import '../core/widgets/pandora_navigation_layout.dart';
import '../features/activity/activity_screen.dart';
import '../features/core/pandora_core_screen.dart';
import '../features/enterprise/batalla_workspace_screen.dart';
import '../features/enterprise/bok_workspace_screen.dart';
import '../features/enterprise/enterprise_vision_screen.dart';
import '../features/enterprise/enterprise_workspace_home.dart';
import '../features/enterprise/marketing_growth_workspace_screen.dart';
import '../features/enterprise/pandora_enterprise_workspace_screen.dart';
import '../features/enterprise/provider_ecosystem_screen.dart';
import '../features/enterprise/tax_compliance_screen.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/plugins/plugins_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/chat/pandora_chat_presentation_controller.dart';
import '../features/simple/more_screen.dart';
import '../features/simple/offline_evidence_screen.dart';
import '../features/simple/pandora_v2_ui.dart';
import '../features/simple/projects_screen.dart';
import '../features/simple/simple_safety_screen.dart';
import '../pandora_config.dart';
import 'eurofish_enterprise_shell.dart';
import 'pandora_conversation_layer.dart';
import 'pandora_core_client_scope.dart';
import 'pandora_dependencies.dart';
import 'pandora_shared_conversation_scope.dart';
import 'plp_enterprise_shell.dart';

enum PandoraStartPage { chat, home }

class PandoraChatShell extends StatefulWidget {
  const PandoraChatShell(
      {super.key,
      this.startPage = PandoraStartPage.chat,
      this.coreGateway,
      this.clientRuntimeFactory,
      this.enterpriseGateway,
      this.memberWorkspace,
      this.initialEntry,
      this.onLeaveMemberWorkspace,
      this.onMemberSignOut});

  final PandoraStartPage startPage;
  final PandoraCoreGateway? coreGateway;
  final PandoraClientRuntimeFactory? clientRuntimeFactory;
  final PandoraEnterpriseGateway? enterpriseGateway;
  final PandoraEnterpriseMembership? memberWorkspace;
  final PandoraClientEntry? initialEntry;
  final VoidCallback? onLeaveMemberWorkspace;
  final Future<void> Function()? onMemberSignOut;

  @override
  State<PandoraChatShell> createState() => _PandoraChatShellState();
}

class _PandoraChatShellState extends State<PandoraChatShell>
    with WidgetsBindingObserver {
  static const _destinations = <_ChatDestination>[
    _ChatDestination('Pandora', Icons.chat_bubble_outline_rounded,
        Icons.chat_bubble_rounded),
    _ChatDestination('Projects', Icons.folder_outlined, Icons.folder_rounded),
    _ChatDestination('Needs You', Icons.check_circle_outline_rounded,
        Icons.check_circle_rounded),
    _ChatDestination('Settings & More', Icons.tune_rounded, Icons.tune_rounded),
    _ChatDestination('Activity', Icons.history_rounded, Icons.history_rounded),
    _ChatDestination(
        'Live Connections', Icons.extension_outlined, Icons.extension_rounded),
    _ChatDestination('Saved evidence', Icons.offline_pin_outlined,
        Icons.offline_pin_rounded),
    _ChatDestination(
        'Verify & Safety', Icons.shield_outlined, Icons.shield_rounded),
    _ChatDestination(
        'Operations Room', Icons.groups_2_outlined, Icons.groups_2_rounded),
    _ChatDestination('Home', Icons.home_outlined, Icons.home_rounded),
    _ChatDestination(
      'Vision Intelligence',
      Icons.videocam_outlined,
      Icons.videocam_rounded,
    ),
    _ChatDestination(
      'Capabilities & Providers',
      Icons.account_tree_outlined,
      Icons.account_tree_rounded,
    ),
    _ChatDestination(
        'Clients', Icons.business_outlined, Icons.business_rounded),
    _ChatDestination(
        'Business', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
    _ChatDestination('Platform', Icons.hub_outlined, Icons.hub_rounded),
    _ChatDestination('Administration', Icons.admin_panel_settings_outlined,
        Icons.admin_panel_settings_rounded),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _clientNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _ownerNavigatorKey =
      GlobalKey<NavigatorState>();
  GlobalKey<AskPandoraScreenState> _chatKey =
      GlobalKey<AskPandoraScreenState>();
  final Map<int, Widget> _roots = <int, Widget>{};
  final Map<int, Map<String, String>> _coreContexts = {};
  final Map<int, Object> _coreContextTokens = {};
  Map<String, Object?>? _activeEnterpriseContext;
  EnterpriseWorkspaceSelection? _activeWorkspaceSelection;
  Map<String, String> _surfaceSelectedObject = const <String, String>{};
  final Set<int> _visited = <int>{0};
  List<PandoraIntelligenceThread> _threads =
      const <PandoraIntelligenceThread>[];
  bool _historyLoading = false;
  bool _historyLoaded = false;
  bool _chatVisible = true;
  int _index = 0;
  final _drawerScrollController = ScrollController();
  final _recentChatsScrollController = ScrollController();
  final _drawerFocus = FocusScopeNode(debugLabel: 'Pandora navigation');
  final _primaryDrawerPresence = GlobalKey();
  final _recentDrawerPresence = GlobalKey();
  _DrawerProjection? _drawerProjection;
  bool _drawerProjectionScheduled = false;
  bool _issuingDrawerCommand = false;
  PandoraChatPresentationController? _preparedDrawerController;
  int? _preparedDrawerIntent;
  late final PandoraCoreGateway _coreGateway;
  PandoraClientRuntime? _clientRuntime;
  PandoraClientEntry? _clientEntry;
  Timer? _clientExpiry;
  Timer? _clientValidation;
  bool _entryValidationInFlight = false;
  int _scopeEpoch = 0;
  bool _switchingScope = false;
  bool _enterpriseMutationPending = false;
  PandoraCoreFailure? _scopeInitializationFailure;
  late final PandoraEnterpriseGateway _enterpriseGateway;
  bool get _inClientWorkspace =>
      _clientEntry != null || widget.memberWorkspace != null;
  String? get _workspaceOrganizationId =>
      _clientEntry?.organizationId ?? widget.memberWorkspace?.organizationId;
  String get _workspaceName =>
      _clientEntry?.displayName ??
      widget.memberWorkspace?.displayName ??
      'Workspace';
  String get _workspaceAdapter =>
      _clientEntry?.adapter ?? widget.memberWorkspace?.adapter ?? '';
  String? get _workspacePropertyId =>
      _clientEntry?.propertyId ?? widget.memberWorkspace?.propertyId;

  PandoraDependencies get _activeDependencies =>
      _clientRuntime?.dependencies ?? PandoraDependencies.of(context);

  bool get _presentationOwnsBack {
    final presentation = _chatKey.currentState?.presentationController;
    if (_drawerProjection != null) return true;
    if (presentation == null) return false;
    return presentation.value.surface != PandoraChatSurface.none ||
        presentation.value.transitioning ||
        presentation.value.keyboardVisible ||
        presentation.composerFocus.hasFocus;
  }

  bool get _canReturnFromOwnerChat =>
      !_inClientWorkspace &&
      _index != 0 &&
      _chatVisible &&
      !_presentationOwnsBack;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clientExpiry?.cancel();
    _clientValidation?.cancel();
    _clientRuntime?.dispose();
    _scopeEpoch++;
    _drawerScrollController.dispose();
    _recentChatsScrollController.dispose();
    _drawerFocus.dispose();
    super.dispose();
  }

  void _resetDrawerScroll() {
    if (_drawerScrollController.hasClients) _drawerScrollController.jumpTo(0);
  }

  void _openDrawer() => _requestDrawer(PandoraChatDrawerKind.primary);

  void _openRecentChats() => _requestDrawer(PandoraChatDrawerKind.recent);

  void _requestDrawer(PandoraChatDrawerKind kind) {
    final presentation = _chatKey.currentState?.presentationController;
    if (presentation == null) return;
    presentation.attachDrawerFocus(_drawerFocus);
    unawaited(presentation.showDrawer(kind: kind));
    _scheduleDrawerProjection();
  }

  void _dismissDrawers() {
    final presentation = _chatKey.currentState?.presentationController;
    if (presentation?.value.surface == PandoraChatSurface.drawer ||
        presentation?.value.pendingSurface == PandoraChatSurface.drawer) {
      presentation?.closeSurface();
    }
    _scheduleDrawerProjection();
  }

  void _handleChatPresentation(PandoraChatPresentationState state) {
    if (!mounted) return;
    // Input/back intents can update the mounted Scaffold immediately. Waiting
    // for a post-frame callback adds another frame before its animation starts
    // and leaves the departing drawer intercepting the next interaction.
    if (WidgetsBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _projectDrawerSurface();
    }
    _scheduleDrawerProjection();
    // The child coordinator owns presentation. Rebuild only its measured
    // composer clearance and the policy for beginning a navigation gesture.
    setState(() {});
  }

  void _scheduleDrawerProjection() {
    if (!mounted || _drawerProjectionScheduled) return;
    _drawerProjectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drawerProjectionScheduled = false;
      if (mounted) _projectDrawerSurface();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  GlobalKey _presenceKey(PandoraChatDrawerKind kind) =>
      kind == PandoraChatDrawerKind.primary
          ? _primaryDrawerPresence
          : _recentDrawerPresence;

  void _issueDrawerCommand(PandoraChatDrawerKind kind, {required bool open}) {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    _issuingDrawerCommand = true;
    try {
      if (kind == PandoraChatDrawerKind.primary) {
        open ? scaffold.openDrawer() : scaffold.closeDrawer();
      } else {
        open ? scaffold.openEndDrawer() : scaffold.closeEndDrawer();
      }
    } finally {
      // Flutter's drawer callback acknowledges the start of the command, not
      // animation completion. A programmatic false is never a user dismissal.
      _issuingDrawerCommand = false;
    }
  }

  void _projectDrawerSurface() {
    final scaffold = _scaffoldKey.currentState;
    final presentation = _chatKey.currentState?.presentationController;
    if (scaffold == null || presentation == null) return;
    presentation.attachDrawerFocus(_drawerFocus);
    final state = presentation.value;
    final requested =
        state.surface == PandoraChatSurface.drawer ? state.drawerKind : null;
    final supported = requested != null &&
        (requested == PandoraChatDrawerKind.primary
            ? scaffold.widget.drawer != null
            : scaffold.widget.endDrawer != null);
    final desired = supported ? requested : null;
    if (requested != null && !supported) {
      // A permanent desktop sidebar already fulfils primary navigation. Do not
      // leave an invisible modal intent behind when crossing the breakpoint.
      presentation.closeSurface();
    }

    final current = _drawerProjection;
    if (current != null) {
      if (current.closing) {
        // This is also the close-before-first-paint case: no Drawer subtree was
        // mounted, so no unmount notification can arrive. Read actual presence.
        if (_presenceKey(current.kind).currentContext == null) {
          setState(() => _drawerProjection = null);
          _scheduleDrawerProjection();
        }
        return;
      }
      if (!identical(current.controller, presentation) ||
          current.kind != desired) {
        current.closing = true;
        _issueDrawerCommand(current.kind, open: false);
        _scheduleDrawerProjection();
        return;
      }
      current.intentRevision = state.intentRevision;
      return;
    }
    if (desired == null) return;

    final prepare = !identical(_preparedDrawerController, presentation) ||
        _preparedDrawerIntent != state.intentRevision;
    if (prepare) {
      _preparedDrawerController = presentation;
      _preparedDrawerIntent = state.intentRevision;
      if (desired == PandoraChatDrawerKind.recent) {
        _historyLoaded = true;
        unawaited(_refreshHistory());
      }
    }
    _drawerProjection = _DrawerProjection(
      controller: presentation,
      kind: desired,
      intentRevision: state.intentRevision,
      resetScrollOnMount: prepare,
    );
    _issueDrawerCommand(desired, open: true);
  }

  void _onDrawerChanged(PandoraChatDrawerKind kind, bool open) {
    if (!mounted || _issuingDrawerCommand) return;
    final presentation = _chatKey.currentState?.presentationController;
    if (presentation == null) return;
    final current = _drawerProjection;
    if (open) {
      // Only an unmanaged edge gesture creates a new drawer intent here.
      // A late callback from a departing drawer cannot replace another target.
      if (current == null &&
          presentation.value.surface == PandoraChatSurface.none &&
          !presentation.value.transitioning) {
        presentation.reportDrawer(true, kind: kind);
        _drawerProjection = _DrawerProjection(
          controller: presentation,
          kind: kind,
          intentRevision: presentation.value.intentRevision,
          resetScrollOnMount: true,
        );
      } else if (current != null &&
          current.kind == kind &&
          current.closing &&
          identical(current.controller, presentation) &&
          presentation.value.surface == PandoraChatSurface.none &&
          !presentation.value.transitioning) {
        // The user may reverse a closing swipe before it reaches the edge.
        // This is a fresh visible gesture, not a late close acknowledgement.
        presentation.reportDrawer(true, kind: kind);
        current
          ..closing = false
          ..intentRevision = presentation.value.intentRevision;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onDrawerMounted(kind));
      _scheduleDrawerProjection();
      return;
    }
    if (current != null && current.kind == kind && !current.closing) {
      current.closing = true;
      if (identical(current.controller, presentation)) {
        presentation.reportDrawer(false,
            kind: kind, expectedIntent: current.intentRevision);
      }
    }
    _scheduleDrawerProjection();
  }

  void _onDrawerMounted(PandoraChatDrawerKind kind) {
    if (!mounted) return;
    var current = _drawerProjection;
    final presentation = _chatKey.currentState?.presentationController;
    if (current == null &&
        presentation != null &&
        presentation.value.surface == PandoraChatSurface.none &&
        !presentation.value.transitioning) {
      // Capture an edge gesture at its first visible frame, before Flutter's
      // halfway callback, so late IME metrics can still withhold this surface.
      presentation.reportDrawer(true, kind: kind);
      current = _DrawerProjection(
        controller: presentation,
        kind: kind,
        intentRevision: presentation.value.intentRevision,
        resetScrollOnMount: true,
      );
      _drawerProjection = current;
      _scheduleDrawerProjection();
    }
    if (current != null &&
        current.kind == kind &&
        !current.closing &&
        current.resetScrollOnMount) {
      current.resetScrollOnMount = false;
      if (kind == PandoraChatDrawerKind.primary) {
        _resetDrawerScroll();
      } else if (_recentChatsScrollController.hasClients) {
        _recentChatsScrollController.jumpTo(0);
      }
    }
  }

  void _onDrawerUnmounted(PandoraChatDrawerKind kind) {
    if (!mounted || _presenceKey(kind).currentContext != null) return;
    if (_drawerProjection?.kind == kind) {
      // Back eligibility also depends on physical removal, not just on the
      // earlier dismissal intent. Publish this last rendering transition.
      setState(() => _drawerProjection = null);
    }
    _scheduleDrawerProjection();
  }

  Widget _observedDrawer(PandoraChatDrawerKind kind, Widget child) {
    final owner = _chatKey;
    final presentation = owner.currentState?.presentationController;
    final keyboardVisible = presentation?.value.keyboardVisible ?? false;
    final drawerKeyboard = presentation?.drawerOwnsKeyboard ?? false;
    final foreground = presentation?.value.surface;
    return _DrawerPresence(
      key: _presenceKey(kind),
      onMounted: () {
        if (identical(owner, _chatKey)) _onDrawerMounted(kind);
      },
      onUnmounted: () => _onDrawerUnmounted(kind),
      // A late IME frame withholds the drawer immediately, while its actual
      // closing animation/removal still supplies the completion receipt.
      child: FocusScope(
        node: _drawerFocus,
        child: Visibility(
          visible: (!keyboardVisible || drawerKeyboard) &&
              foreground != PandoraChatSurface.picker &&
              foreground != PandoraChatSurface.context,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: Padding(
            // Scaffold resizes its body for IME, but not its modal drawers.
            padding: EdgeInsets.only(
                bottom: drawerKeyboard
                    ? presentation?.value.keyboardInset ?? 0
                    : 0),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coreGateway = widget.coreGateway ?? SupabasePandoraCoreGateway();
    _enterpriseGateway =
        widget.enterpriseGateway ?? SupabasePandoraEnterpriseGateway();
    final membership = widget.memberWorkspace;
    if (membership == null && widget.startPage == PandoraStartPage.home) {
      _index = 9;
      _chatVisible = false;
      _visited
        ..clear()
        ..add(9);
    }
    if (membership != null) {
      try {
        final entry = widget.initialEntry;
        if ((membership.requiresOperatorEntry && entry == null) ||
            (entry != null &&
                (entry.organizationId != membership.organizationId ||
                    entry.adapter != membership.adapter ||
                    !entry.expiresAt.isAfter(DateTime.now())))) {
          throw const PandoraCoreFailure('ACCESS_DENIED',
              'Administrator entry needs a verified access receipt.');
        }
        _assertAdapter(membership.adapter, membership.organizationId,
            membership.propertyId);
        _clientEntry = entry;
        _clientRuntime = (widget.clientRuntimeFactory ??
            PandoraClientRuntime.create)(membership.organizationId);
        final workspace = _clientProfile(membership.organizationId,
            membership.displayName, membership.adapter);
        final selection = EnterpriseWorkspaceSelection(
            workspace: workspace, section: workspace.sections.first);
        _activeWorkspaceSelection = selection;
        _activeEnterpriseContext = _clientContext(selection);
        _chatVisible = false;
        if (entry != null) _scheduleEntryValidation(entry);
      } on PandoraCoreFailure catch (error) {
        _scopeInitializationFailure = error;
      } catch (_) {
        _scopeInitializationFailure = const PandoraCoreFailure(
            'UNAVAILABLE', 'Pandora could not open this workspace. Retry.');
      }
    }
    unawaited(OwnerAnalytics.shared.capture(OwnerAnalyticsEvent.appOpened));
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: _index == 9 ? 'pandora_home' : 'pandora_chat',
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_historyLoaded) {
      _historyLoaded = true;
      unawaited(_refreshHistory());
    }
  }

  Future<void> _refreshHistory() async {
    if (_historyLoading || _scopeInitializationFailure != null) return;
    final intelligence = _activeDependencies.intelligence;
    if (intelligence == null) return;
    final epoch = _scopeEpoch;
    setState(() => _historyLoading = true);
    try {
      final threads = await intelligence.recentThreads();
      if (!mounted || epoch != _scopeEpoch) return;
      setState(() => _threads = threads);
    } on PandoraIntelligenceException {
      // Chat remains usable when history is temporarily unavailable.
    } finally {
      if (mounted && epoch == _scopeEpoch) {
        setState(() => _historyLoading = false);
      }
    }
  }

  void _select(int value) {
    if (_inClientWorkspace && value != 0) {
      if (value == 9) _selectClientHome();
      return;
    }
    if (value < 0 || value >= _destinations.length) return;
    // A drawer destination replaces secondary owner pages. Chat expansion uses
    // separate visibility methods and retains the current business route.
    _ownerNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    FocusManager.instance.primaryFocus?.unfocus();
    _dismissDrawers();
    if (value != 0) {
      _chatKey.currentState?.minimizeHistory();
      if (_chatVisible) setState(() => _chatVisible = false);
    }
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
      _surfaceSelectedObject = _coreContexts[value] ?? const <String, String>{};
    });
    final screen = switch (value) {
      0 => 'pandora_chat',
      1 => 'projects',
      2 => 'needs_you',
      3 => 'more',
      4 => 'activity',
      5 => 'live_connections',
      6 => 'saved_evidence',
      7 => 'verify_safety',
      8 => 'operations_room',
      9 => 'enterprise_home',
      10 => 'vision_intelligence',
      11 => 'provider_ecosystem',
      12 => 'core_clients',
      13 => 'core_business',
      14 => 'core_platform',
      15 => 'core_administration',
      _ => 'pandora_chat',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  void _openConversationHistory() {
    FocusManager.instance.primaryFocus?.unfocus();
    _dismissDrawers();
    if (!_chatVisible) setState(() => _chatVisible = true);
    _chatKey.currentState?.showHistory();
  }

  void _newChat() {
    _dismissDrawers();
    final chat = _chatKey.currentState;
    if (chat == null) return;
    if (!_chatVisible) setState(() => _chatVisible = true);
    chat.newChat();
    chat.showHistory();
    unawaited(_refreshHistory());
  }

  Future<void> _openThread(PandoraIntelligenceThread thread) async {
    _dismissDrawers();
    final chat = _chatKey.currentState;
    if (chat == null) return;
    if (!_chatVisible) setState(() => _chatVisible = true);
    chat.showHistory();
    await chat.loadThread(thread.id);
  }

  Future<T?> _presentThreadSheet<T>(WidgetBuilder builder,
      {int? expectedIntent}) {
    final chat = _chatKey.currentState;
    if (chat == null) return Future<T?>.value();
    return chat.presentContextRoute(
      ModalBottomSheetRoute<T>(
        builder: builder,
        isScrollControlled: false,
        useSafeArea: true,
        showDragHandle: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        capturedThemes: InheritedTheme.capture(
            from: context, to: Navigator.of(context).context),
      ),
      expectedIntent: expectedIntent,
    );
  }

  Future<T?> _presentThreadDialog<T>(WidgetBuilder builder) {
    final chat = _chatKey.currentState;
    if (chat == null) return Future<T?>.value();
    return chat.presentContextRoute(
      DialogRoute<T>(context: context, builder: builder, useSafeArea: true),
    );
  }

  Future<void> _manageThread(PandoraIntelligenceThread thread) async {
    final epoch = _scopeEpoch;
    final action = await _presentThreadSheet<_ThreadAction>(
      (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.of(sheetContext).pop(_ThreadAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Move to project'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ThreadAction.project),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ThreadAction.archive),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              textColor: PandoraV2Colors.danger,
              iconColor: PandoraV2Colors.danger,
              onTap: () => Navigator.of(sheetContext).pop(_ThreadAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || epoch != _scopeEpoch || action == null) return;
    switch (action) {
      case _ThreadAction.rename:
        await _renameThread(thread);
        break;
      case _ThreadAction.project:
        await _moveThreadToProject(thread);
        break;
      case _ThreadAction.archive:
        await _archiveThread(thread);
        break;
      case _ThreadAction.delete:
        await _deleteThread(thread);
        break;
    }
  }

  Future<void> _renameThread(PandoraIntelligenceThread thread) async {
    final epoch = _scopeEpoch;
    final intelligence = _activeDependencies.intelligence;
    if (intelligence == null) return;
    final controller = TextEditingController(text: thread.title);
    final title = await _presentThreadDialog<String>(
      (dialogContext) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'Conversation name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted ||
        epoch != _scopeEpoch ||
        title == null ||
        title.isEmpty ||
        title == thread.title) {
      return;
    }
    await _runThreadMutation(
      () => intelligence.renameThread(thread.id, title),
      success: 'Conversation renamed.',
      expectedEpoch: epoch,
    );
  }

  Future<void> _archiveThread(PandoraIntelligenceThread thread) async {
    final intelligence = _activeDependencies.intelligence;
    if (intelligence == null) return;
    await _runThreadMutation(
      () => intelligence.archiveThread(thread.id),
      success: 'Conversation archived.',
    );
  }

  Future<void> _deleteThread(PandoraIntelligenceThread thread) async {
    final epoch = _scopeEpoch;
    final intelligence = _activeDependencies.intelligence;
    if (intelligence == null) return;
    final confirmed = await _presentThreadDialog<bool>(
          (dialogContext) => AlertDialog(
            title: const Text('Delete conversation?'),
            content: Text(
                'Delete “${thread.title}” and its saved messages? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || epoch != _scopeEpoch || !confirmed) return;
    await _runThreadMutation(
      () => intelligence.deleteThread(thread.id),
      success: 'Conversation deleted.',
      expectedEpoch: epoch,
    );
  }

  Future<void> _moveThreadToProject(PandoraIntelligenceThread thread) async {
    final epoch = _scopeEpoch;
    final chat = _chatKey.currentState;
    final intelligence = _activeDependencies.intelligence;
    if (chat == null || intelligence == null) return;
    final repository = _activeDependencies.repository;
    final presentation = chat.presentationController;
    final opening = presentation.showContext();
    final intent = presentation.value.intentRevision;
    bool stillOwnsIntent() =>
        mounted &&
        epoch == _scopeEpoch &&
        identical(chat, _chatKey.currentState) &&
        presentation.value.intentRevision == intent &&
        presentation.value.surface == PandoraChatSurface.context;
    try {
      if (!await opening || !stillOwnsIntent()) return;
      final projectSnapshot = await repository.projects(allowCached: true);
      if (!stillOwnsIntent()) return;
      final selected = await _presentThreadSheet<String>(
        (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              const ListTile(
                title: Text('Move conversation to project'),
                subtitle: Text(
                    'Choose a persistent project context or remove the association.'),
              ),
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: const Text('No project'),
                onTap: () => Navigator.of(sheetContext).pop(''),
              ),
              for (final project in projectSnapshot.data)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  trailing: thread.projectId == project.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(project.id),
                ),
            ],
          ),
        ),
        expectedIntent: intent,
      );
      if (!mounted || epoch != _scopeEpoch || selected == null) return;
      await _runThreadMutation(
        () => intelligence.associateThreadWithProject(
          thread.id,
          selected.isEmpty ? null : selected,
        ),
        success: selected.isEmpty
            ? 'Project association removed.'
            : 'Conversation moved to project.',
        expectedEpoch: epoch,
      );
    } on PandoraIntelligenceException catch (error) {
      if (stillOwnsIntent()) _showThreadMessage(error.message);
    } on Exception {
      if (stillOwnsIntent()) {
        _showThreadMessage(
            'Pandora could not load projects for this conversation.');
      }
    } finally {
      if (stillOwnsIntent()) presentation.closeSurface();
    }
  }

  Future<void> _runThreadMutation(
    Future<void> Function() mutation, {
    required String success,
    int? expectedEpoch,
  }) async {
    final epoch = expectedEpoch ?? _scopeEpoch;
    if (!mounted || epoch != _scopeEpoch) return;
    final intelligence = _activeDependencies.intelligence;
    if (intelligence == null) return;
    try {
      await mutation();
      if (!mounted || epoch != _scopeEpoch) return;
      await _refreshHistory();
      if (mounted && epoch == _scopeEpoch) _showThreadMessage(success);
    } on PandoraIntelligenceException catch (error) {
      if (mounted && epoch == _scopeEpoch) _showThreadMessage(error.message);
    }
  }

  void _showThreadMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _sessionWorkspaceProfileKey() {
    final value = _activeDependencies.auth.currentSession?.workspaceProfile;
    return switch (value) {
      'dan' => 'dan',
      'secretary' => 'secretary',
      'atty_batalla' => 'atty_batalla',
      _ => 'atty_batalla',
    };
  }

  String _activeWorkspaceProfileKey() {
    final selected = _activeEnterpriseContext?['selectedObject'];
    if (selected is Map) {
      final value = selected['workspaceProfile'];
      if (value == 'dan' || value == 'secretary' || value == 'atty_batalla') {
        return value as String;
      }
    }
    return _sessionWorkspaceProfileKey();
  }

  void _assertAdapter(
      String adapter, String organizationId, String? propertyId) {
    if (adapter == 'enterprise_core_v1') return;
    if (adapter == 'plp_v1' &&
        organizationId == PandoraConfig.plpOrganizationId &&
        propertyId == 'ada9befb-b821-4ae6-86bf-a6d93376815b') return;
    throw const PandoraCoreFailure('WORKSPACE_SETUP_REQUIRED',
        'This workspace adapter could not be verified.');
  }

  EnterpriseWorkspaceProfile _clientProfile(
      String organizationId, String displayName, String adapter) {
    if (adapter == 'plp_v1')
      return enterpriseWorkspaces
          .firstWhere((item) => item.key == 'plp-boracay');
    return EnterpriseWorkspaceProfile(
        key: 'client-$organizationId',
        name: displayName,
        subtitle: 'Enterprise workspace',
        initials: displayName.trim().isEmpty ? 'P' : displayName.trim()[0],
        icon: Icons.business_outlined,
        logoAsset: '',
        accent: const Color(0xFF88AEDA),
        sections: const [
          EnterpriseWorkspaceSection(
              'Overview', 'enterprise_overview', 'overview',
              icon: Icons.home_outlined),
          EnterpriseWorkspaceSection('Work', 'enterprise_workflows', 'work',
              icon: Icons.task_alt_rounded),
          EnterpriseWorkspaceSection(
              'Documents', 'enterprise_data', 'documents',
              icon: Icons.description_outlined),
          EnterpriseWorkspaceSection('Activity', 'enterprise_logs', 'activity',
              icon: Icons.history_rounded),
          EnterpriseWorkspaceSection('People', 'enterprise_security', 'people',
              icon: Icons.group_outlined),
        ]);
  }

  Map<String, Object?> _clientContext(EnterpriseWorkspaceSelection selection) {
    final organizationId = _workspaceOrganizationId!;
    final entry = _clientEntry;
    final section = entry == null && _workspaceAdapter == 'plp_v1'
        ? (const {'work', 'documents', 'activity', 'people'}
                .contains(selection.section.routeSlug)
            ? selection.section.routeSlug
            : 'overview')
        : selection.section.routeSlug;
    final selected = <String, Object?>{
      'organizationId': organizationId,
      'workspaceMode': entry == null ? 'member' : 'administrator',
      'adapterKey': entry == null ? 'enterprise_core_v1' : _workspaceAdapter,
      'section': section,
      if (entry != null) 'entryId': entry.entryId,
    };
    if (_workspaceAdapter == 'plp_v1' && entry != null) {
      selected.addAll({'workspaceSlug': 'plp-boracay', 'assistant': 'alfred'});
      return {
        ...selection.enterpriseContext,
        'selectedObject': selected,
        'organization': {
          'id': organizationId,
          'propertyId': _workspacePropertyId,
          'propertySlug': 'plp-boracay',
        }
      };
    }
    return {
      'surface': selection.section.surface,
      'route': '/enterprise/workspace/$organizationId/$section',
      'identityScope': 'enterprise_workspace',
      'capabilities': const <String>[],
      'selectedObject': selected,
      'organization': {'id': organizationId},
    };
  }

  void _scheduleEntryValidation(PandoraClientEntry entry) {
    _clientExpiry?.cancel();
    _clientExpiry = Timer(entry.expiresAt.difference(DateTime.now()),
        () => unawaited(_returnToPandora(expired: true)));
    _clientValidation?.cancel();
    _clientValidation = Timer.periodic(
        const Duration(seconds: 30), (_) => unawaited(_validateClientEntry()));
  }

  void _openWorkspace(EnterpriseWorkspaceSelection selection) {
    if (selection.workspace.key != 'pandora-marketing-growth' &&
        !_inClientWorkspace) {
      _showThreadMessage('Open this customer from Clients to verify access.');
      return;
    }
    final nextContext = _inClientWorkspace
        ? _clientContext(selection)
        : selection.enterpriseContext;
    if (selection.workspace.key == 'batalla-associates') {
      final selected = Map<String, Object?>.from(
        nextContext['selectedObject']! as Map,
      );
      selected['workspaceProfile'] = _sessionWorkspaceProfileKey();
      nextContext['selectedObject'] = selected;
    }
    setState(() {
      _chatVisible = false;
      _activeEnterpriseContext = nextContext;
      _activeWorkspaceSelection = selection;
      _surfaceSelectedObject = const <String, String>{};
      _roots.remove(0);
      _visited.add(0);
    });
    _select(0);
    _chatKey.currentState?.minimizeHistory();
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'enterprise_workspace_' +
            selection.workspace.key +
            '_' +
            selection.section.routeSlug,
      ),
    );
  }

  void _bindEnterpriseContext(Map<String, Object?> context) {
    if (!mounted) return;
    final organization = context['organization'];
    if (_inClientWorkspace &&
        organization is Map &&
        organization['id']?.toString() != _workspaceOrganizationId) {
      _showThreadMessage('The page context does not match this client.');
      return;
    }
    setState(() {
      _activeEnterpriseContext = Map<String, Object?>.from(context);
      if (_inClientWorkspace && _activeWorkspaceSelection != null) {
        final scopedContext = _clientContext(_activeWorkspaceSelection!);
        _activeEnterpriseContext!['selectedObject'] =
            scopedContext['selectedObject'];
        if (_clientEntry == null) {
          _activeEnterpriseContext!['route'] = scopedContext['route'];
          _activeEnterpriseContext!['surface'] = scopedContext['surface'];
          _activeEnterpriseContext!['identityScope'] =
              scopedContext['identityScope'];
        }
      }
      _surfaceSelectedObject = const <String, String>{};
    });
  }

  void _bindSelectedObject(Map<String, String> selected) {
    if (!mounted) return;
    setState(() => _surfaceSelectedObject = Map<String, String>.from(selected));
  }

  Future<String?> _submitSharedPrompt(
    String prompt, {
    Map<String, String>? selectedObject,
  }) async {
    final epoch = _scopeEpoch;
    if (selectedObject != null) _bindSelectedObject(selectedObject);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || epoch != _scopeEpoch) return null;
    final chat = _chatKey.currentState;
    if (chat == null) return null;
    if (!_chatVisible) setState(() => _chatVisible = true);
    chat.showHistory();
    return chat.submitExternalPrompt(prompt, requestFocus: false);
  }

  void _showSharedConversation() {
    if (!_chatVisible) setState(() => _chatVisible = true);
    _chatKey.currentState?.showHistory();
  }

  Future<void> _openSharedThread(String threadId) async {
    final chat = _chatKey.currentState;
    if (chat == null) return;
    if (!_chatVisible) setState(() => _chatVisible = true);
    chat.showHistory();
    await chat.loadThread(threadId);
  }

  void _reportSharedFailure(
    String code, {
    Map<String, String>? selectedObject,
  }) {
    if (selectedObject != null) _bindSelectedObject(selectedObject);
    _chatKey.currentState?.showExternalFailureMessage(
      pandoraNaturalFailureMessage(code),
    );
  }

  Map<String, Object?>? _conversationContextForCurrentSurface() {
    if (_inClientWorkspace && _activeEnterpriseContext != null) {
      return Map<String, Object?>.from(_activeEnterpriseContext!);
    }
    if (const <int>{2, 9, 12, 13, 14, 15}.contains(_index) ||
        (_index == 0 && _activeEnterpriseContext == null)) {
      final section = switch (_index) {
        12 => 'clients',
        13 => 'business',
        14 => 'platform',
        15 => 'administration',
        _ => 'home',
      };
      return <String, Object?>{
        'surface': 'enterprise_settings',
        'route': '/enterprise/core/$section',
        'identityScope': 'pandora_organization',
        'capabilities': const <String>[],
        'selectedObject': <String, String>{
          'coreSection': section,
          'coreMode': 'owner',
          ..._surfaceSelectedObject
        },
      };
    }
    if (_index != 0 || _activeEnterpriseContext == null) return null;
    final context = Map<String, Object?>.from(_activeEnterpriseContext!);
    final selected = context['selectedObject'];
    context['selectedObject'] = <String, String>{
      if (selected is Map)
        for (final entry in selected.entries)
          entry.key.toString(): entry.value.toString(),
      ..._surfaceSelectedObject,
    };
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
    final scope = context['identityScope']?.toString().trim();
    if (!allowedSurfaces.contains(surface) ||
        route == null ||
        !route.startsWith('/enterprise/') ||
        !allowedScopes.contains(scope)) {
      return null;
    }
    return context;
  }

  Widget _root(int index) => _roots.putIfAbsent(
        index,
        () => switch (index) {
          0 => _scopeInitializationFailure != null
              ? Center(child: Text(_scopeInitializationFailure!.message))
              : _inClientWorkspace && _workspaceAdapter == 'enterprise_core_v1'
                  ? PandoraEnterpriseWorkspaceScreen(
                      gateway: _enterpriseGateway,
                      organizationId: _workspaceOrganizationId!,
                      entryId: _clientEntry?.entryId,
                      section: _activeWorkspaceSelection?.section.routeSlug ??
                          'overview',
                      onNavigate: (section) {
                        final selection = _activeWorkspaceSelection;
                        if (selection == null) return;
                        final match = selection.workspace.sections
                            .where((item) => item.routeSlug == section);
                        if (match.isNotEmpty)
                          _openWorkspace(EnterpriseWorkspaceSelection(
                              workspace: selection.workspace,
                              section: match.first));
                      },
                      onPendingWorkChanged: (pending) =>
                          _enterpriseMutationPending = pending,
                    )
                  : _activeWorkspaceSelection?.section.routeSlug ==
                          'tax-compliance'
                      ? TaxComplianceScreen(
                          workspaceKey:
                              _activeWorkspaceSelection!.workspace.key,
                          workspaceName:
                              _activeWorkspaceSelection!.workspace.name,
                          organizationId: _workspaceOrganizationId,
                          enterpriseContext: _activeEnterpriseContext ??
                              _activeWorkspaceSelection!.enterpriseContext,
                          onHome: () => _select(9),
                        )
                      : _activeWorkspaceSelection?.workspace.key ==
                              'pandora-marketing-growth'
                          ? MarketingGrowthWorkspaceScreen(
                              initialRouteSlug:
                                  _activeWorkspaceSelection!.section.routeSlug,
                              enterpriseContext: _activeEnterpriseContext ??
                                  _activeWorkspaceSelection!.enterpriseContext,
                              onHome: () => _select(9),
                              onApprovals: () => _select(2),
                            )
                          : _activeWorkspaceSelection?.workspace.key ==
                                  'batalla-associates'
                              ? BatallaWorkspaceScreen(
                                  initialRouteSlug: _activeWorkspaceSelection!
                                      .section.routeSlug,
                                  profileKey: _activeWorkspaceProfileKey(),
                                  onBackToWorkspaces: () => _select(9),
                                )
                              : _activeWorkspaceSelection?.workspace.key ==
                                      'plp-boracay'
                                  ? PlpEnterpriseShell(
                                      organizationId: _workspaceOrganizationId,
                                      propertyId: _workspacePropertyId,
                                      embeddedRouteSlug:
                                          _activeWorkspaceSelection!
                                              .section.routeSlug,
                                    )
                                  : _activeWorkspaceSelection?.workspace.key ==
                                          '1064-euro-fish-traders'
                                      ? EurofishEnterpriseShell(
                                          embedded: true,
                                          initialRouteSlug:
                                              _activeWorkspaceSelection!
                                                  .section.routeSlug,
                                        )
                                      : _activeWorkspaceSelection
                                                  ?.workspace.key ==
                                              'bok'
                                          ? BokWorkspaceScreen(
                                              workspace:
                                                  _activeWorkspaceSelection!
                                                      .workspace,
                                              section:
                                                  _activeWorkspaceSelection!
                                                      .section,
                                            )
                                          : const SizedBox.expand(),
          1 => const ProjectsScreen(),
          2 => _coreScreen('home', initialAction: 'needs_you'),
          3 => const MoreScreen(),
          4 => const ActivityScreen(),
          5 => PluginsScreen(onOpenProviderCatalog: () => _select(11)),
          6 => const OfflineEvidenceScreen(),
          7 => const SimpleSafetyScreen(),
          8 => PandoraOperationsRoomScreen(
              onHome: () => _select(9),
              globalConversation: true,
            ),
          9 => _coreScreen('home'),
          12 => _coreScreen('clients'),
          13 => _coreScreen('business'),
          14 => _coreScreen('platform'),
          15 => _coreScreen('administration'),
          10 => EnterpriseVisionScreen(),
          11 => ProviderEcosystemScreen(
              onOpenConnections: () => _select(5),
            ),
          _ => const SizedBox.expand(),
        },
      );

  Widget _coreScreen(String section,
      {String? organizationId, String? initialAction}) {
    final routeIndex = initialAction == 'needs_you'
        ? 2
        : switch (section) {
            'clients' => 12,
            'business' => 13,
            'platform' => 14,
            'administration' => 15,
            _ => 9,
          };
    final token = Object();
    _coreContextTokens[routeIndex] = token;
    _coreContexts[routeIndex] = {
      'coreSection': organizationId == null ? section : 'client',
      if (organizationId != null) 'organizationId': organizationId,
    };
    return PandoraCoreScreen(
      gateway: _coreGateway,
      section: section,
      organizationId: organizationId,
      initialAction: initialAction,
      onHome: () => _select(9),
      onNavigate: _navigateCore,
      onEnterClient: _enterClient,
      onContextChanged: (value) {
        if (!mounted ||
            _inClientWorkspace ||
            !identical(_coreContextTokens[routeIndex], token)) return;
        final scoped = {
          for (final entry in value.entries) entry.key: entry.value.toString()
        };
        _coreContexts[routeIndex] = scoped;
        if (_index == routeIndex)
          setState(() => _surfaceSelectedObject = scoped);
      },
    );
  }

  void _navigateCore(String destination) {
    final index = switch (destination) {
      'clients' => 12,
      'business' => 13,
      'platform' => 14,
      'administration' => 15,
      'needs_you' => 2,
      'operations' => 8,
      'connections' => 5,
      'capabilities' => 11,
      'safety' => 7,
      'activity' => 4,
      _ => 9,
    };
    _select(index);
  }

  void _handleCoreNavigation(PandoraIntelligenceHandoff handoff) {
    if (handoff.kind != 'core_navigation') return;
    if (_inClientWorkspace) {
      if (handoff.action == 'return_owner' && widget.memberWorkspace == null)
        unawaited(_returnToPandora());
      return;
    }
    final section = handoff.section;
    final index = switch (section) {
      'clients' => 12,
      'business' => 13,
      'platform' => 14,
      'administration' => 15,
      _ => null,
    };
    if (index == null) return;
    final organizationId = handoff.organizationId;
    if (organizationId != null &&
        !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
            .hasMatch(organizationId)) {
      return;
    }
    final action = const {
      'create_client',
      'manage_users',
      'prepare_proposal',
      'inspect'
    }.contains(handoff.action)
        ? handoff.action
        : null;
    setState(() {
      _roots[index] = _coreScreen(section!,
          organizationId: organizationId, initialAction: action);
    });
    _select(index);
    setState(() => _surfaceSelectedObject = {
          'coreSection': organizationId == null ? section! : 'client',
          if (organizationId != null) 'organizationId': organizationId,
        });
  }

  bool get _canChangeScope =>
      !_switchingScope &&
      !_enterpriseMutationPending &&
      !(_chatKey.currentState?.hasPendingScopeWork ?? false);

  Future<void> _enterClient(PandoraCoreRecord client) async {
    if (!_canChangeScope) {
      throw const PandoraCoreFailure(
        'ACTION_PENDING',
        'Finish or reconcile the current action before changing client.',
      );
    }
    final organizationId = coreText(client['organization_id'], '');
    if (organizationId.isEmpty || client['can_enter'] != true) {
      throw const PandoraCoreFailure(
          'ACCESS_DENIED', 'Client workspace entry is not authorized.');
    }
    var reason = '';
    final selectedReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            'Enter ${coreText(client['display_name'], 'client workspace')}'),
        content: TextField(
          onChanged: (value) => reason = value,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Reason for administrator access',
            hintText: 'For example, investigate a support request',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reason.trim();
              if (value.length >= 3) Navigator.pop(dialogContext, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted || selectedReason == null) return;
    if (!_canChangeScope) {
      throw const PandoraCoreFailure('ACTION_PENDING',
          'Resolve the current action before changing client.');
    }
    _switchingScope = true;
    final epoch = _scopeEpoch;
    PandoraClientRuntime? nextRuntime;
    try {
      PandoraCoreRecord raw;
      try {
        raw = await _coreGateway.enterClient(organizationId,
            reason: selectedReason);
      } on PandoraCoreFailure catch (error) {
        if (!error.requiresStepUp || !mounted) rethrow;
        final verified = await verifyCoreIdentity(
            context, PandoraDependencies.of(context).auth);
        if (!verified || !mounted) rethrow;
        raw = await _coreGateway.enterClient(organizationId,
            reason: selectedReason);
      }
      if (!mounted || epoch != _scopeEpoch) return;
      final entry = PandoraClientEntry.verify(raw,
          requestedOrganizationId: organizationId);
      _assertAdapter(entry.adapter, entry.organizationId, entry.propertyId);
      nextRuntime = (widget.clientRuntimeFactory ??
          PandoraClientRuntime.create)(entry.organizationId);
      await PandoraLocalAi.instance
          .resetConversation()
          .timeout(const Duration(seconds: 3));
      if (!mounted || epoch != _scopeEpoch) {
        nextRuntime.dispose();
        nextRuntime = null;
        return;
      }
      final previous = _clientRuntime;
      final workspace = _clientProfile(
          entry.organizationId, entry.displayName, entry.adapter);
      final selection = EnterpriseWorkspaceSelection(
          workspace: workspace, section: workspace.sections.first);
      setState(() {
        _scopeEpoch++;
        _clientRuntime = nextRuntime;
        _clientEntry = entry;
        _chatKey = GlobalKey<AskPandoraScreenState>();
        _roots.clear();
        _coreContexts.clear();
        _coreContextTokens.clear();
        _visited
          ..clear()
          ..add(0);
        _threads = const [];
        _historyLoaded = false;
        _historyLoading = false;
        _chatVisible = false;
        _index = 0;
        _surfaceSelectedObject = const {};
        _activeWorkspaceSelection = selection;
        _activeEnterpriseContext = _clientContext(selection);
      });
      nextRuntime = null;
      _scheduleEntryValidation(entry);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
        if (mounted) unawaited(_refreshHistory());
      });
    } catch (_) {
      nextRuntime?.dispose();
      rethrow;
    } finally {
      _switchingScope = false;
    }
  }

  Future<void> _returnToPandora({bool expired = false}) async {
    if (!_inClientWorkspace) return;
    if (!expired && !_canChangeScope) {
      _showThreadMessage(
          'Finish or reconcile the current client action before returning.');
      return;
    }
    setState(() => _switchingScope = true);
    final previous = _clientRuntime;
    final closingEntry = _clientEntry;
    try {
      await PandoraLocalAi.instance
          .resetConversation()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      if (!expired) {
        _switchingScope = false;
        _showThreadMessage('Conversation context could not be cleared. Retry.');
        return;
      }
    }
    if (!mounted) return;
    if (widget.memberWorkspace != null) {
      _scopeEpoch++;
      _clientExpiry?.cancel();
      _clientValidation?.cancel();
      final entry = _clientEntry;
      final gateway = _coreGateway;
      if (entry != null && gateway is PandoraCoreEntryGateway) {
        unawaited((gateway as PandoraCoreEntryGateway)
            .leaveClient(entry.entryId)
            .catchError((Object _) {}));
      }
      widget.onLeaveMemberWorkspace?.call();
      return;
    }
    _clientExpiry?.cancel();
    _clientValidation?.cancel();
    final gateway = _coreGateway;
    if (gateway is PandoraCoreEntryGateway && closingEntry != null) {
      unawaited((gateway as PandoraCoreEntryGateway)
          .leaveClient(closingEntry.entryId)
          .catchError((Object _) {}));
    }
    setState(() {
      _scopeEpoch++;
      _clientRuntime = null;
      _clientEntry = null;
      _chatKey = GlobalKey<AskPandoraScreenState>();
      _roots.clear();
      _coreContexts.clear();
      _coreContextTokens.clear();
      _visited
        ..clear()
        ..add(9);
      _threads = const [];
      _historyLoaded = false;
      _historyLoading = false;
      _chatVisible = false;
      _index = 9;
      _activeEnterpriseContext = null;
      _activeWorkspaceSelection = null;
      _surfaceSelectedObject = const {};
      _switchingScope = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous?.dispose();
      if (mounted) {
        unawaited(_refreshHistory());
        if (expired) {
          _showThreadMessage(
              'Client administrator access expired. You are back in Pandora.');
        }
      }
    });
  }

  Future<void> _validateClientEntry() async {
    final entry = _clientEntry;
    if (entry == null || _entryValidationInFlight) return;
    _entryValidationInFlight = true;
    final epoch = _scopeEpoch;
    try {
      final gateway = _coreGateway;
      final valid = gateway is PandoraCoreEntryGateway &&
          await (gateway as PandoraCoreEntryGateway)
              .validateEntry(entry.entryId, entry.organizationId);
      if (mounted && epoch == _scopeEpoch && !valid) {
        await _returnToPandora(expired: true);
      }
    } catch (_) {
      if (mounted && epoch == _scopeEpoch) {
        await _returnToPandora(expired: true);
      }
    } finally {
      _entryValidationInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _clientEntry != null) {
      unawaited(_validateClientEntry());
    }
  }

  void _selectClientHome() {
    final selection = _activeWorkspaceSelection;
    if (!_inClientWorkspace || selection == null) return;
    _openWorkspace(EnterpriseWorkspaceSelection(
      workspace: selection.workspace,
      section: selection.workspace.sections.first,
    ));
  }

  Widget _clientBanner() => Material(
        key: const ValueKey('core-client-context-banner'),
        color: const Color(0xFF202A34),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  _clientEntry != null
                      ? 'Viewing $_workspaceName as Pandora Administrator'
                      : _workspaceName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('core-return-pandora'),
                onPressed: _switchingScope
                    ? null
                    : () => unawaited(_returnToPandora()),
                child: Text(
                    widget.memberWorkspace == null
                        ? 'Return to Pandora'
                        : 'Workspaces',
                    style: const TextStyle(fontSize: 11)),
              ),
            ]),
          ),
        ),
      );

  Widget _clientSidePanel() {
    final selection = _activeWorkspaceSelection;
    return Material(
      color: const Color(0xFA000000),
      child: SafeArea(
        child: ListView(
          controller: _drawerScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Text(_workspaceName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Pandora'),
              selected: _chatVisible,
              onTap: _openConversationHistory,
            ),
            if (selection != null)
              for (final section in selection.workspace.sections)
                ListTile(
                  leading: Icon(section.icon),
                  title: Text(section.label),
                  selected: !_chatVisible &&
                      selection.section.routeSlug == section.routeSlug,
                  onTap: () => _openWorkspace(EnterpriseWorkspaceSelection(
                      workspace: selection.workspace, section: section)),
                ),
            const Divider(),
            if (widget.memberWorkspace != null)
              ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () => unawaited(widget.onMemberSignOut?.call() ??
                      _activeDependencies.auth.signOut())),
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: Text(widget.memberWorkspace == null
                  ? 'Return to Pandora'
                  : 'My workspaces'),
              onTap: () => unawaited(_returnToPandora()),
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _theme(ThemeData base) {
    // This shell always uses the locked dark palette. Copying a light ambient
    // theme retains its resolved text/button/icon colours on the dark canvas.
    final dark = PandoraTheme.graphite;
    const scheme = ColorScheme.dark(
      primary: PandoraV2Colors.ink,
      onPrimary: Colors.black,
      primaryContainer: PandoraV2Colors.soft,
      onPrimaryContainer: PandoraV2Colors.ink,
      secondary: PandoraV2Colors.ink,
      onSecondary: Colors.black,
      surface: PandoraV2Colors.surface,
      onSurface: PandoraV2Colors.ink,
      onSurfaceVariant: PandoraV2Colors.muted,
      surfaceContainerLowest: PandoraV2Colors.canvas,
      surfaceContainerLow: PandoraV2Colors.canvas,
      surfaceContainer: PandoraV2Colors.surface,
      surfaceContainerHigh: PandoraV2Colors.soft,
      surfaceContainerHighest: PandoraV2Colors.soft,
      surfaceTint: Colors.transparent,
      error: PandoraV2Colors.danger,
      onError: Colors.black,
      outline: PandoraV2Colors.line,
      outlineVariant: PandoraV2Colors.line,
    );
    final actionForeground = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled)
          ? PandoraV2Colors.muted
          : PandoraV2Colors.ink,
    );
    return dark.copyWith(
      platform: base.platform,
      visualDensity: base.visualDensity,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PandoraV2Colors.canvas,
      canvasColor: PandoraV2Colors.canvas,
      extensions: <ThemeExtension<dynamic>>[
        PandoraPalette.graphite.copyWith(
          canvas: PandoraV2Colors.canvas,
          subtleSurface: PandoraV2Colors.soft,
          strongSurface: PandoraV2Colors.surface,
          outlineSoft: PandoraV2Colors.line,
        ),
      ],
      textTheme: dark.textTheme.apply(
        bodyColor: PandoraV2Colors.ink,
        displayColor: PandoraV2Colors.ink,
      ),
      iconTheme: dark.iconTheme.copyWith(color: PandoraV2Colors.ink),
      primaryIconTheme:
          dark.primaryIconTheme.copyWith(color: PandoraV2Colors.ink),
      disabledColor: PandoraV2Colors.muted,
      textButtonTheme: TextButtonThemeData(
        style: dark.textButtonTheme.style?.copyWith(
          foregroundColor: actionForeground,
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) =>
              states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.hovered)
                  ? PandoraV2Colors.ink.withValues(alpha: .12)
                  : null),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: dark.iconButtonTheme.style
            ?.copyWith(foregroundColor: actionForeground),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: dark.outlinedButtonTheme.style?.copyWith(
          foregroundColor: actionForeground,
          side: const WidgetStatePropertyAll(
              BorderSide(color: PandoraV2Colors.line)),
        ),
      ),
      cardTheme: dark.cardTheme.copyWith(color: PandoraV2Colors.surface),
      dialogTheme:
          dark.dialogTheme.copyWith(backgroundColor: PandoraV2Colors.surface),
      popupMenuTheme:
          dark.popupMenuTheme.copyWith(color: PandoraV2Colors.surface),
      appBarTheme: const AppBarTheme(
        backgroundColor: PandoraV2Colors.canvas,
        foregroundColor: PandoraV2Colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: PandoraV2Colors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PandoraV2Colors.surface,
        hintStyle: const TextStyle(color: PandoraV2Colors.muted),
        labelStyle: const TextStyle(color: PandoraV2Colors.muted),
        floatingLabelStyle: const TextStyle(color: PandoraV2Colors.ink),
        prefixIconColor: PandoraV2Colors.muted,
        suffixIconColor: PandoraV2Colors.muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.ink, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.danger),
        ),
      ),
    );
  }

  Widget _presentRoot(int index) {
    final root = _root(index);
    // PLP content owns its porcelain appearance; the shared composer remains
    // a sibling under the Core theme, with no tenant or navigation change.
    final presented = root is PlpEnterpriseShell
        ? Theme(
            key: const ValueKey('pandora-plp-content-theme'),
            data: PandoraTheme.porcelain,
            child: root,
          )
        : root;
    return PandoraCoreRouteVisibility(
      active: index == _index && !_chatVisible,
      child: presented,
    );
  }

  Widget _sidePanel() => _inClientWorkspace
      ? _clientSidePanel()
      : _PandoraSidePanel(
          scrollController: _drawerScrollController,
          destinations: _destinations,
          selectedIndex: _chatVisible ? 0 : _index,
          onSelected: (value) {
            if (value == 0) {
              _openConversationHistory();
              return;
            }
            _select(value);
          },
        );

  Widget _recentChatsPanel() => _PandoraRecentChatsPanel(
        scrollController: _recentChatsScrollController,
        threads: _threads,
        historyLoading: _historyLoading,
        onNewChat: _newChat,
        onOpenThread: _openThread,
        onManageThread: _manageThread,
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: _theme(Theme.of(context)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _scheduleDrawerProjection();
            if (_scopeInitializationFailure != null) {
              return Scaffold(
                  body: SafeArea(
                      child: Center(
                          child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_scopeInitializationFailure!.message),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: widget.onLeaveMemberWorkspace,
                      child: const Text('My workspaces')),
                ]),
              ))));
            }
            final body = IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  _visited.contains(i) || i == _index
                      ? _presentRoot(i)
                      : const SizedBox.shrink(),
              ],
            );

            Widget businessBody = body;
            if (!_inClientWorkspace) {
              final canPopOwnerContent =
                  !_chatVisible && !_presentationOwnsBack;
              businessBody = NavigatorPopHandler(
                key: const ValueKey('pandora-owner-content-navigator'),
                enabled: canPopOwnerContent,
                onPopWithResult: (_) {
                  if (!canPopOwnerContent ||
                      _chatVisible ||
                      _presentationOwnsBack) {
                    return;
                  }
                  unawaited(_ownerNavigatorKey.currentState?.maybePop() ??
                      Future<bool>.value(false));
                },
                child: Navigator(
                  key: _ownerNavigatorKey,
                  pages: [
                    MaterialPage<void>(
                      key: ValueKey('owner-surface-$_scopeEpoch'),
                      child: body,
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              );
            }
            final chatScopeEpoch = _scopeEpoch;
            Widget activeChat = PandoraConversationLayer(
              key: const ValueKey<String>('pandora-global-active-chat-shell'),
              composerExtent: _chatKey
                  .currentState?.presentationController.value.composerExtent,
              businessWorkspace: Offstage(
                offstage: _chatVisible,
                child: PandoraSharedConversationScope(
                  submitPrompt: _submitSharedPrompt,
                  openThread: _openSharedThread,
                  showConversation: _showSharedConversation,
                  bindEnterpriseContext: _bindEnterpriseContext,
                  bindSelectedObject: _bindSelectedObject,
                  reportFailure: _reportSharedFailure,
                  child: businessBody,
                ),
              ),
              conversation: AskPandoraScreen(
                key: _chatKey,
                onSearchChats: _openRecentChats,
                onMore: () => _select(3),
                onHome: () => _select(9),
                enterpriseContext: _conversationContextForCurrentSurface(),
                shellOverlay: true,
                initialHistoryExpanded: _chatVisible,
                onCoreNavigate: (handoff) {
                  if (mounted && chatScopeEpoch == _scopeEpoch) {
                    _handleCoreNavigation(handoff);
                  }
                },
                onHistoryVisibilityChanged: (visible) {
                  if (mounted &&
                      chatScopeEpoch == _scopeEpoch &&
                      _chatVisible != visible) {
                    setState(() => _chatVisible = visible);
                  }
                },
                onPresentationChanged: (state) {
                  if (mounted && chatScopeEpoch == _scopeEpoch) {
                    _handleChatPresentation(state);
                  }
                },
              ),
            );

            final canReturnFromOwnerChat = _canReturnFromOwnerChat;
            activeChat = PopScope<void>(
              canPop: !canReturnFromOwnerChat,
              onPopInvokedWithResult: (didPop, _) {
                // Multiple PopScopes see the same Back. Dismissing the IME
                // must not make history eligible for this already-fired event.
                if (didPop ||
                    !canReturnFromOwnerChat ||
                    !_canReturnFromOwnerChat) {
                  return;
                }
                FocusManager.instance.primaryFocus?.unfocus();
                _chatKey.currentState?.minimizeHistory();
              },
              child: activeChat,
            );

            final clientRuntime = _clientRuntime;
            if (clientRuntime != null) {
              activeChat = clientRuntime.wrap(NavigatorPopHandler(
                onPopWithResult: (_) => unawaited(
                    _clientNavigatorKey.currentState?.maybePop() ??
                        Future<bool>.value(false)),
                child: Navigator(
                  key: _clientNavigatorKey,
                  pages: [
                    MaterialPage<void>(
                        key: ValueKey('client-surface-$_scopeEpoch'),
                        child: activeChat)
                  ],
                  onDidRemovePage: (_) {},
                ),
              ));
            }
            if (_inClientWorkspace) {
              activeChat = Column(children: [
                _clientBanner(),
                Expanded(
                    child: AbsorbPointer(
                        absorbing: _switchingScope, child: activeChat)),
              ]);
            }

            if (constraints.maxWidth >= 900) {
              return Scaffold(
                key: _scaffoldKey,
                backgroundColor: PandoraV2Colors.canvas,
                drawerScrimColor: const Color(0xD9000000),
                onEndDrawerChanged: (open) =>
                    _onDrawerChanged(PandoraChatDrawerKind.recent, open),
                endDrawerEnableOpenDragGesture: false,
                endDrawer: _observedDrawer(
                    PandoraChatDrawerKind.recent,
                    Drawer(
                      key:
                          const ValueKey<String>('pandora-recent-chats-drawer'),
                      width: 340,
                      backgroundColor: const Color(0xFA000000),
                      surfaceTintColor: Colors.transparent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                      ),
                      child: SafeArea(child: _recentChatsPanel()),
                    )),
                body: Row(
                  children: [
                    SizedBox(width: 264, child: SafeArea(child: _sidePanel())),
                    const VerticalDivider(
                        width: 1, color: PandoraV2Colors.line),
                    Expanded(
                      child: PandoraNavigationScope(
                        openDrawer: null,
                        child: activeChat,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: PandoraV2Colors.canvas,
              onDrawerChanged: (open) =>
                  _onDrawerChanged(PandoraChatDrawerKind.primary, open),
              onEndDrawerChanged: (open) =>
                  _onDrawerChanged(PandoraChatDrawerKind.recent, open),
              drawerEnableOpenDragGesture: !(_chatKey.currentState
                          ?.presentationController.value.keyboardVisible ??
                      false) &&
                  !(_chatKey.currentState?.presentationController.value
                          .transitioning ??
                      false) &&
                  (_chatKey.currentState?.presentationController.value
                              .surface ??
                          PandoraChatSurface.none) ==
                      PandoraChatSurface.none,
              endDrawerEnableOpenDragGesture: false,
              drawerEdgeDragWidth: 32,
              drawerScrimColor: const Color(0xD9000000),
              drawer: _observedDrawer(
                  PandoraChatDrawerKind.primary,
                  Drawer(
                    key: const ValueKey<String>(
                        'pandora-primary-navigation-drawer'),
                    width: 304,
                    backgroundColor: const Color(0xFA000000),
                    surfaceTintColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: SafeArea(child: _sidePanel()),
                  )),
              endDrawer: _observedDrawer(
                  PandoraChatDrawerKind.recent,
                  Drawer(
                    key: const ValueKey<String>('pandora-recent-chats-drawer'),
                    width: 340,
                    backgroundColor: const Color(0xFA000000),
                    surfaceTintColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        bottomLeft: Radius.circular(24),
                      ),
                    ),
                    child: SafeArea(child: _recentChatsPanel()),
                  )),
              body: PandoraNavigationScope(
                openDrawer: _openDrawer,
                child: activeChat,
              ),
            );
          },
        ),
      );
}

/// A rendering receipt for the one physical modal drawer. Desired kind and
/// lifetime are owned by PandoraChatPresentationController.
class _DrawerProjection {
  _DrawerProjection({
    required this.controller,
    required this.kind,
    required this.intentRevision,
    required this.resetScrollOnMount,
  });

  final PandoraChatPresentationController controller;
  final PandoraChatDrawerKind kind;
  int intentRevision;
  bool resetScrollOnMount;
  bool closing = false;
}

/// Scaffold callbacks signal animation start. Widget removal proves the old
/// drawer has actually left the viewport, allowing the next modal surface in.
class _DrawerPresence extends StatefulWidget {
  const _DrawerPresence({
    super.key,
    required this.onMounted,
    required this.onUnmounted,
    required this.child,
  });

  final VoidCallback onMounted;
  final VoidCallback onUnmounted;
  final Widget child;

  @override
  State<_DrawerPresence> createState() => _DrawerPresenceState();
}

class _DrawerPresenceState extends State<_DrawerPresence> {
  @override
  void initState() {
    super.initState();
    final onMounted = widget.onMounted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onMounted();
    });
  }

  @override
  void dispose() {
    final onUnmounted = widget.onUnmounted;
    WidgetsBinding.instance.addPostFrameCallback((_) => onUnmounted());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PandoraSidePanel extends StatelessWidget {
  const _PandoraSidePanel({
    required this.destinations,
    required this.scrollController,
    required this.selectedIndex,
    required this.onSelected,
  });

  final ScrollController scrollController;
  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFA000000),
        child: PandoraNavigationLayout(
          controller: scrollController,
          scrollKey: const ValueKey<String>('pandora-side-panel-scroll'),
          bodyPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          header: const Padding(
            key: ValueKey<String>('pandora-side-panel-top-overlay'),
            padding: EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                PandoraMark(size: 28),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Pandora',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerSection(
                label: 'Pandora',
                indices: const <int>[9, 0, 2],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Work',
                indices: const <int>[1, 12, 13, 4, 6],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              ExpansionTile(
                key: const ValueKey<String>('pandora-advanced-navigation'),
                initiallyExpanded:
                    const <int>[8, 10, 11, 5, 14, 15].contains(selectedIndex),
                title: const Text('Advanced'),
                subtitle: const Text('Connections and administration'),
                children: [
                  _DrawerSection(
                    label: 'Tools',
                    indices: const <int>[10, 8, 11, 5],
                    destinations: destinations,
                    selectedIndex: selectedIndex,
                    onSelected: onSelected,
                  ),
                  _DrawerSection(
                    label: 'Administration',
                    indices: const <int>[14, 15],
                    destinations: destinations,
                    selectedIndex: selectedIndex,
                    onSelected: onSelected,
                    showDivider: false,
                  ),
                ],
              ),
              _DrawerSection(
                label: 'Security',
                indices: const <int>[7],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Account',
                indices: const <int>[3],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
                showDivider: false,
              ),
            ],
          ),
          footer: const SizedBox.shrink(),
        ),
      );
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.label,
    required this.indices,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.showDivider = true,
  });

  final String label;
  final List<int> indices;
  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          for (final index in indices)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                selected: index == selectedIndex,
                selectedColor: PandoraV2Colors.ink,
                iconColor: PandoraV2Colors.muted,
                textColor: PandoraV2Colors.ink,
                selectedTileColor: PandoraV2Colors.soft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  index == selectedIndex
                      ? destinations[index].selectedIcon
                      : destinations[index].icon,
                  size: 22,
                ),
                title: Text(
                  destinations[index].label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: index == selectedIndex
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                onTap: () => onSelected(index),
              ),
            ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: PandoraV2Colors.line),
            ),
        ],
      );
}

class _PandoraRecentChatsPanel extends StatefulWidget {
  const _PandoraRecentChatsPanel({
    required this.scrollController,
    required this.threads,
    required this.historyLoading,
    required this.onNewChat,
    required this.onOpenThread,
    required this.onManageThread,
  });

  final ScrollController scrollController;
  final List<PandoraIntelligenceThread> threads;
  final bool historyLoading;
  final VoidCallback onNewChat;
  final ValueChanged<PandoraIntelligenceThread> onOpenThread;
  final ValueChanged<PandoraIntelligenceThread> onManageThread;

  @override
  State<_PandoraRecentChatsPanel> createState() =>
      _PandoraRecentChatsPanelState();
}

class _PandoraRecentChatsPanelState extends State<_PandoraRecentChatsPanel> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.toLowerCase();
    final threads = widget.threads
        .where(
          (thread) =>
              needle.isEmpty || thread.title.toLowerCase().contains(needle),
        )
        .take(30)
        .toList(growable: false);
    return Material(
      key: const ValueKey<String>('pandora-recent-chats-panel'),
      color: const Color(0xFA000000),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent chats',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: widget.onNewChat,
                  icon: const Icon(Icons.edit_square, size: 21),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const Divider(height: 1, color: PandoraV2Colors.line),
          Expanded(
            child: widget.historyLoading && widget.threads.isEmpty
                ? const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : threads.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No conversations found.',
                            style: TextStyle(
                              color: PandoraV2Colors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                        itemCount: threads.length,
                        itemBuilder: (context, index) {
                          final thread = threads[index];
                          return ListTile(
                            key: ValueKey<String>(
                              'pandora-thread-${thread.id}',
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(10, 4, 4, 4),
                            title: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                thread.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PandoraV2Colors.ink,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4, right: 10),
                              child: Text(
                                '${_chatRelativeTime(thread.lastMessageAt)} · ${_chatStatusLabel(thread.status)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PandoraV2Colors.muted,
                                  fontSize: 11,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            trailing: SizedBox.square(
                              dimension: 48,
                              child: IconButton(
                                tooltip: 'Conversation options',
                                padding: EdgeInsets.zero,
                                onPressed: () => widget.onManageThread(thread),
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                            onTap: () => widget.onOpenThread(thread),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

String _chatRelativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

String _chatStatusLabel(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'active') return 'Active';
  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

enum _ThreadAction { rename, project, archive, delete }

class _ChatDestination {
  const _ChatDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
