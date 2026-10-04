part of '../ask_pandora_screen.dart';

enum _AttachmentAction {
  camera,
  photos,
  files,
  model,
  reasoning,
  characters,
  services,
  project
}

extension _PandoraContextActions on AskPandoraScreenState {
  Future<void> _showAttachmentActions() async {
    final owner = _chat;
    final draft = owner.captureDraftToken();
    final selected = await presentContextRoute<_AttachmentAction>(
        ModalBottomSheetRoute<_AttachmentAction>(
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PandoraSimpleColors.surface,
      builder: (routeContext) {
        Widget item(_AttachmentAction action, String suffix, String label,
                IconData icon, {String? identifier}) =>
            Semantics(
                identifier: identifier,
                child: _ComposerMenuItem(
                    key: ValueKey<String>('ask-pandora-menu-$suffix'),
                    label: label,
                    icon: icon,
                    onPressed: () => Navigator.of(routeContext).pop(action)));
        final preference = owner.state.preferences;
        final depthLabel = switch (preference.reasoningMode) {
          'fast' => 'Fast',
          'deep' => 'Deep',
          _ => 'Balanced',
        };
        return SafeArea(
            top: false,
            child: Semantics(
                identifier: 'pandora.chat.menu-surface',
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: 'Pandora menu',
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.only(left: 24, right: 12),
                      child: Row(children: [
                        const Expanded(
                            child: Text('Pandora menu',
                                style: TextStyle(
                                    color: PandoraSimpleColors.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600))),
                        Semantics(
                            identifier: 'pandora.chat.menu.close',
                            child: IconButton(
                                tooltip: 'Close Pandora menu',
                                onPressed: () =>
                                    Navigator.of(routeContext).pop(),
                                icon: const Icon(Icons.close_rounded))),
                      ])),
                  Flexible(
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                    item(_AttachmentAction.camera, 'camera', 'Camera',
                        Icons.camera_alt_outlined),
                    item(_AttachmentAction.photos, 'photos', 'Photos',
                        Icons.photo_outlined),
                    item(_AttachmentAction.files, 'files', 'Files',
                        Icons.insert_drive_file_outlined),
                    if (!_isCommonWorkspace &&
                        _dependencies.intelligence != null) ...[
                      item(_AttachmentAction.model, 'model',
                          'Model · ${preference.label}', Icons.tune_rounded,
                          identifier: 'pandora.chat.model-options'),
                      item(
                          _AttachmentAction.reasoning,
                          'reasoning',
                          'Response depth · $depthLabel',
                          Icons.psychology_alt_outlined,
                          identifier: 'pandora.chat.reasoning-options-entry'),
                    ],
                    if (widget.allowCharacterContext)
                      item(_AttachmentAction.characters, 'characters',
                          'Characters', Icons.face_retouching_natural_outlined),
                    item(_AttachmentAction.services, 'services', 'Services',
                        Icons.extension_outlined),
                    if (widget.allowProjectContext)
                      item(_AttachmentAction.project, 'project-context',
                          'Project context', Icons.workspaces_outline),
                  ]))),
                ])));
      },
    ));
    if (!mounted ||
        !identical(_controller, owner) ||
        !owner.matchesDraft(draft)) {
      return;
    }
    switch (selected) {
      case _AttachmentAction.camera:
        await _pickImage(camera: true);
      case _AttachmentAction.photos:
        await _pickImage(camera: false);
      case _AttachmentAction.files:
        await _attach();
      case _AttachmentAction.model:
      case _AttachmentAction.reasoning:
        // The contained picker places Response depth near its top. Both menu
        // entry points use that overview, never the end of the model catalog.
        // presentContextRoute has already awaited the old route's dismissal.
        await _pickModel();
      case _AttachmentAction.characters:
        await _pickCharacterContext();
      case _AttachmentAction.services:
        await _pickServiceContext();
      case _AttachmentAction.project:
        await _pickProjectContext();
      case null:
        break;
    }
  }

  bool _contextIntentCurrent(int intent, PandoraChatDraftToken draft) =>
      mounted &&
      _chat.matchesDraft(draft) &&
      _presentation.value.intentRevision == intent &&
      _presentation.value.surface == PandoraChatSurface.context;

  Future<T?> _contextSheet<T>(
      Widget child, int intent, PandoraChatDraftToken draft) async {
    if (!_contextIntentCurrent(intent, draft)) return null;
    final navigator = Navigator.of(context);
    final route = ModalBottomSheetRoute<T>(
        builder: (_) => child,
        isScrollControlled: false,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: PandoraSimpleColors.surface,
        capturedThemes:
            InheritedTheme.capture(from: context, to: navigator.context));
    return _presentContextRoute(route,
        expectedIntent: intent, closeOnComplete: false);
  }

  Future<void> _attach() async {
    final draft = _chat.captureDraftToken();
    final attachment = await PandoraNativeIo.pickTextAttachment();
    if (!mounted || !_chat.matchesDraft(draft)) return;
    if (attachment == null) {
      _notice('Choose a TXT, Markdown, CSV, or JSON file up to 32 KB.');
      return;
    }
    _refresh(() => _attachment = attachment);
  }

  Future<void> _pickImage({required bool camera}) async {
    final draft = _chat.captureDraftToken();
    final image = camera
        ? await PandoraNativeIo.takePhoto()
        : await PandoraNativeIo.pickPhoto();
    if (!mounted || !_chat.matchesDraft(draft)) return;
    if (image == null) {
      _notice(camera
          ? 'No camera image was attached.'
          : 'No supported photo was attached.');
      return;
    }
    _refresh(() => _imageAttachment = image);
  }

  Future<void> _pickCharacterContext() async {
    final draft = _chat.captureDraftToken();
    final opening = _presentation.showContext();
    final intent = _presentation.value.intentRevision;
    if (!await opening || !_contextIntentCurrent(intent, draft)) return;
    final selected = await _contextSheet<PandoraCharacterProfile>(
        const _CharacterContextSheet(), intent, draft);
    if (!_contextIntentCurrent(intent, draft)) return;
    if (selected != null) {
      _refresh(() {
        _characterContext = selected;
        _characterSessionId = null;
        _serviceContext = null;
      });
    }
    _presentation.closeSurface();
    if (selected != null) _objectiveFocus.requestFocus();
  }

  void _removeCharacterContext() => _refresh(() {
        _characterContext = null;
        _characterSessionId = null;
      });

  Future<void> _pickServiceContext() async {
    final intelligence = _dependencies.intelligence;
    if (intelligence == null) return;
    final draft = _chat.captureDraftToken();
    final opening = _presentation.showContext();
    final intent = _presentation.value.intentRevision;
    try {
      final registry = await intelligence.capabilityRegistry();
      if (!await opening || !_contextIntentCurrent(intent, draft)) return;
      final selected = await _contextSheet<PandoraCapabilityProvider>(
          _ServiceContextSheet(providers: registry.providers), intent, draft);
      if (!_contextIntentCurrent(intent, draft)) return;
      _presentation.closeSurface();
      if (selected == null) return;
      _refresh(() => _serviceContext = selected);
      final prefix = '${selected.label}: ';
      if (!_chat.state.draft.text
          .toLowerCase()
          .startsWith(prefix.toLowerCase())) {
        _chat.applyDraftResult(draft, '$prefix${_chat.state.draft.text}',
            append: false);
      }
      _objectiveFocus.requestFocus();
    } catch (_) {
      if (_contextIntentCurrent(intent, draft)) {
        _presentation.closeSurface();
        _notice('Services could not be loaded. Try again.');
      }
    }
  }

  void _removeServiceContext() {
    final selected = _serviceContext;
    if (selected == null) return;
    final prefix = '${selected.label}: ';
    if (_chat.state.draft.text.toLowerCase().startsWith(prefix.toLowerCase())) {
      _chat.setDraft(_chat.state.draft.text.substring(prefix.length));
    }
    _refresh(() => _serviceContext = null);
  }

  Future<void> _pickProjectContext() async {
    final intelligence = _dependencies.intelligence;
    if (intelligence == null) return;
    final draft = _chat.captureDraftToken();
    final threadId = _chat.state.threadId;
    final opening = _presentation.showContext();
    final intent = _presentation.value.intentRevision;
    try {
      final projects = await intelligence.projectContexts();
      if (!await opening || !_contextIntentCurrent(intent, draft)) return;
      final selected = await _contextSheet<PandoraProjectContext>(
          _ProjectContextSheet(projects: projects), intent, draft);
      if (!_contextIntentCurrent(intent, draft)) return;
      _presentation.closeSurface();
      if (selected == null) return;
      final selectedIntent = _presentation.value.intentRevision;
      if (threadId != null) {
        await intelligence.associateThreadWithProject(threadId, selected.id);
      }
      if (!mounted ||
          !_chat.matchesDraft(draft) ||
          _presentation.value.intentRevision != selectedIntent) {
        return;
      }
      _refresh(() => _projectContext = selected);
      _objectiveFocus.requestFocus();
    } catch (_) {
      if (_contextIntentCurrent(intent, draft)) {
        _presentation.closeSurface();
        _notice('Project context could not be updated. Try again.');
      }
    }
  }

  Future<void> _removeProjectContext() async {
    final intelligence = _dependencies.intelligence;
    final draft = _chat.captureDraftToken();
    final threadId = _chat.state.threadId;
    try {
      if (intelligence != null && threadId != null) {
        await intelligence.associateThreadWithProject(threadId, null);
      }
      if (mounted && _chat.matchesDraft(draft)) {
        _refresh(() => _projectContext = null);
      }
    } catch (_) {
      if (mounted && _chat.matchesDraft(draft)) {
        _notice('Project context could not be updated. Try again.');
      }
    }
  }
}
