import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import '../../core/widgets/pandora_navigation.dart';
import 'pandora_simple_ui.dart';
import 'project_create_experience.dart';
import 'project_experience_v2.dart';

class AskPandoraScreen extends StatefulWidget {
  const AskPandoraScreen({
    super.key,
    this.initialPrompt,
    this.onHome,
    this.onProjects,
    this.onMore,
  });

  final String? initialPrompt;
  final VoidCallback? onHome;
  final VoidCallback? onProjects;
  final VoidCallback? onMore;

  @override
  State<AskPandoraScreen> createState() => AskPandoraScreenState();
}

class AskPandoraScreenState extends State<AskPandoraScreen> {
  static const _suggestions = <String>[
    'What can you do for me now?',
    'Check my GitHub for failing CI',
    'What needs my attention?',
  ];

  final TextEditingController _objective = TextEditingController();
  final FocusNode _objectiveFocus = FocusNode();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  PandoraTextAttachment? _attachment;
  PandoraImageAttachment? _imageAttachment;
  PandoraProjectContext? _projectContext;
  PandoraCapabilityProvider? _serviceContext;
  String? _threadId;
  String? _pendingMessage;
  bool _submitting = false;
  bool _loadingThread = false;
  bool _outcomeUnknown = false;
  String? _submissionKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPrompt?.trim();
    if (initial != null && initial.isNotEmpty) {
      _objective.text = initial;
      _objective.selection = TextSelection.collapsed(offset: initial.length);
    }
  }

  @override
  void dispose() {
    _objective.dispose();
    _objectiveFocus.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    final objective = _objective.text.trim();
    if (objective.isEmpty) {
      setState(() => _error = 'Message Pandora first.');
      _objectiveFocus.requestFocus();
      return;
    }
    setState(() {
      _submitting = true;
      _pendingMessage = objective;
      _error = null;
    });
    try {
      final dependencies = PandoraDependencies.of(context);
      final intelligence = dependencies.intelligence;
      if (intelligence == null) {
        // A Project is optional persistent context, never a prerequisite for
        // talking to Pandora or using a non-project capability. Fall back to
        // the general governed ask path instead of creating a Project.
        _submissionKey ??= _keys.create('simple-intake');
        final receipt = await dependencies.repository.ask(
          message: objective,
          idempotencyKey: _submissionKey,
        );
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage.user(objective));
          _messages.add(_ChatMessage.pandora(receipt.reply));
          _pendingMessage = null;
          _objective.clear();
          _attachment = null;
          _imageAttachment = null;
          _submissionKey = null;
        });
        return;
      }

      final turn = await intelligence.chat(
        message: objective,
        threadId: _threadId,
        projectId: _projectContext?.id,
        textAttachment: _attachment,
        imageAttachment: _imageAttachment,
      );
      if (!mounted) return;
      setState(() {
        _threadId = turn.threadId;
        _messages.add(_ChatMessage.user(objective));
        _messages.add(_ChatMessage.pandora(turn.reply));
        _pendingMessage = null;
        _objective.clear();
        _attachment = null;
        _imageAttachment = null;
        _outcomeUnknown = false;
      });

      final handoff = turn.handoff;
      if (handoff == null) return;
      final experience = dependencies.projectExperienceRepository;
      final handoffProjectId = handoff.projectId?.trim();
      if (experience != null &&
          (handoffProjectId == null || handoffProjectId.isEmpty)) {
        _submissionKey = null;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CreateProjectExperienceScreen(initialIntent: handoff.request),
          ),
        );
        return;
      }
      if (experience != null &&
          handoffProjectId != null &&
          handoffProjectId.isNotEmpty) {
        final snapshot = await experience.runtime(handoffProjectId);
        if (!mounted) return;
        _submissionKey = null;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectWorkspaceV2Screen(
              project: snapshot.project,
              initialChange: handoff.request,
            ),
          ),
        );
        return;
      }
      _submissionKey ??= _keys.create('intelligence-handoff');
      final receipt = await dependencies.repository.ask(
        message: handoff.request,
        projectId: handoff.projectId,
        idempotencyKey: _submissionKey,
      );
      if (!mounted) return;
      setState(() => _submissionKey = null);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage.pandora(receipt.reply));
        });
      }
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _submissionKey = null;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = error.outcomeMayBeUnknown;
        _error = error.outcomeMayBeUnknown
            ? '${error.message} Pandora will not retry this write. Check Activity before sending another request.'
            : error.message;
        if (!error.outcomeMayBeUnknown) _submissionKey = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora intelligence is temporarily unavailable.';
        _submissionKey = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _pendingMessage = null;
        });
      }
    }
  }

  void _useSuggestion(String value) {
    if (_outcomeUnknown || _submitting) return;
    _objective.text = value;
    _objective.selection = TextSelection.collapsed(offset: value.length);
    _objectiveFocus.requestFocus();
    setState(() => _error = null);
  }

  void newChat() {
    if (_submitting) return;
    setState(() {
      _messages.clear();
      _objective.clear();
      _attachment = null;
      _imageAttachment = null;
      _projectContext = null;
      _serviceContext = null;
      _threadId = null;
      _pendingMessage = null;
      _error = null;
      _outcomeUnknown = false;
      _submissionKey = null;
    });
    _objectiveFocus.requestFocus();
  }

  Future<void> loadThread(String threadId) async {
    if (_submitting || _loadingThread || threadId == _threadId) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    setState(() {
      _loadingThread = true;
      _error = null;
      _pendingMessage = null;
    });
    try {
      final history = await intelligence.messages(threadId);
      if (!mounted) return;
      setState(() {
        _threadId = threadId;
        _messages
          ..clear()
          ..addAll(
            history.map(
              (message) => message.isUser
                  ? _ChatMessage.user(message.content)
                  : _ChatMessage.pandora(message.content),
            ),
          );
        _objective.clear();
        _attachment = null;
        _imageAttachment = null;
        _outcomeUnknown = false;
        _submissionKey = null;
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PandoraSimpleColors.canvas,
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          _ChatHeader(onNewChat: newChat),
          const Divider(height: 1, color: PandoraSimpleColors.line),
          Expanded(
            child: _loadingThread
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PandoraSimpleColors.muted,
                    ),
                  )
                : _messages.isEmpty && _pendingMessage == null
                ? _EmptyConversation(
                    suggestions: _suggestions,
                    onSuggestion: _useSuggestion,
                    disabled: _outcomeUnknown || _submitting,
                  )
                : _Conversation(
                    messages: _messages,
                    pendingMessage: _pendingMessage,
                    thinking: _submitting,
                  ),
          ),
          _Composer(
            controller: _objective,
            focusNode: _objectiveFocus,
            attachment: _attachment,
            imageAttachment: _imageAttachment,
            projectContext: _projectContext,
            serviceContext: _serviceContext,
            error: _error,
            submitting: _submitting,
            disabled: _outcomeUnknown,
            onChanged: () {
              if (_error != null) setState(() => _error = null);
            },
            onCamera: () => _pickImage(camera: true),
            onPhotos: () => _pickImage(camera: false),
            onAttach: _attach,
            onServices: _pickServiceContext,
            onProjectContext: _pickProjectContext,
            onDictate: _dictate,
            onSubmit: _submit,
            onRemoveAttachment: () => setState(() => _attachment = null),
            onRemoveImage: () => setState(() => _imageAttachment = null),
            onRemoveServiceContext: _removeServiceContext,
            onRemoveProjectContext: _removeProjectContext,
          ),
        ],
      ),
    ),
  );
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.onNewChat});

  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) => PandoraPageHeader(
    title: 'Pandora',
    actions: [
      IconButton(
        tooltip: 'New chat',
        onPressed: onNewChat,
        icon: const Icon(Icons.edit_square),
        color: PandoraSimpleColors.ink,
      ),
    ],
  );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.suggestions,
    required this.onSuggestion,
    required this.disabled,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final bool disabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 42),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PandoraMark(size: 54, color: Colors.white),
            const SizedBox(height: 18),
            const Text(
              'What can I help with?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: -.35,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: const Text(
                'Ask a question, describe a change, or tell Pandora what you want to build.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                children: [
                  for (var index = 0; index < suggestions.length; index++) ...[
                    _ObsidianSuggestion(
                      label: suggestions[index],
                      enabled: !disabled,
                      onPressed: () => onSuggestion(suggestions[index]),
                    ),
                    if (index != suggestions.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ObsidianSuggestion extends StatelessWidget {
  const _ObsidianSuggestion({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x990F0F0F),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: PandoraSimpleColors.line),
    ),
    child: InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFFE2E2E2)
                      : PandoraSimpleColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: Color(0xFF555555),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.messages,
    required this.pendingMessage,
    required this.thinking,
  });

  final List<_ChatMessage> messages;
  final String? pendingMessage;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingMessage != null && pendingMessage!.isNotEmpty;
    final count = messages.length + (hasPending ? 1 : 0) + (thinking ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: count,
      itemBuilder: (context, index) {
        Widget child;
        if (index < messages.length) {
          child = _ChatBubble(message: messages[index]);
        } else if (hasPending && index == messages.length) {
          child = _ChatBubble(message: _ChatMessage.user(pendingMessage!));
        } else {
          child = const _PandoraThinkingBubble();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : 18),
          child: child,
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

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
          child: PandoraMark(size: 24, color: Colors.white),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: SelectableText(
            message.text,
            style: const TextStyle(
              color: PandoraSimpleColors.ink,
              fontSize: 15.5,
              height: 1.52,
            ),
          ),
        ),
      ],
    );
  }
}

class _PandoraThinkingBubble extends StatelessWidget {
  const _PandoraThinkingBubble();

  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      PandoraMark(size: 24, color: Colors.white),
      SizedBox(width: 11),
      SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: PandoraSimpleColors.muted,
        ),
      ),
      SizedBox(width: 9),
      Text(
        'Thinking…',
        style: TextStyle(color: PandoraSimpleColors.muted, fontSize: 14),
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
    required this.error,
    required this.submitting,
    required this.disabled,
    required this.onChanged,
    required this.onCamera,
    required this.onPhotos,
    required this.onAttach,
    required this.onServices,
    required this.onProjectContext,
    required this.onDictate,
    required this.onSubmit,
    required this.onRemoveAttachment,
    required this.onRemoveImage,
    required this.onRemoveServiceContext,
    required this.onRemoveProjectContext,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PandoraTextAttachment? attachment;
  final PandoraImageAttachment? imageAttachment;
  final PandoraProjectContext? projectContext;
  final PandoraCapabilityProvider? serviceContext;
  final String? error;
  final bool submitting;
  final bool disabled;
  final VoidCallback onChanged;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onAttach;
  final VoidCallback onServices;
  final VoidCallback onProjectContext;
  final VoidCallback onDictate;
  final VoidCallback onSubmit;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onRemoveImage;
  final VoidCallback onRemoveServiceContext;
  final VoidCallback onRemoveProjectContext;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      color: PandoraSimpleColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF7D5D1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFFB42318),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFF8F2D24),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (attachment != null ||
              imageAttachment != null ||
              projectContext != null ||
              serviceContext != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (attachment != null)
                  InputChip(
                    avatar: const Icon(Icons.description_outlined, size: 17),
                    label: Text(attachment!.name),
                    onDeleted: submitting || disabled
                        ? null
                        : onRemoveAttachment,
                  ),
                if (imageAttachment != null)
                  InputChip(
                    avatar: const Icon(Icons.image_outlined, size: 17),
                    label: Text(imageAttachment!.name),
                    onDeleted: submitting || disabled ? null : onRemoveImage,
                  ),
                if (serviceContext != null)
                  InputChip(
                    key: const ValueKey<String>('ask-pandora-service-context'),
                    avatar: const Icon(Icons.extension_outlined, size: 17),
                    label: Text(
                      '${serviceContext!.label} · ${serviceContext!.state}',
                    ),
                    onDeleted: submitting || disabled
                        ? null
                        : onRemoveServiceContext,
                  ),
                if (projectContext != null)
                  InputChip(
                    key: const ValueKey<String>('ask-pandora-project-context'),
                    avatar: const Icon(Icons.workspaces_outline, size: 17),
                    label: Text(projectContext!.name),
                    onDeleted: submitting || disabled
                        ? null
                        : onRemoveProjectContext,
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: PandoraSimpleColors.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: PandoraSimpleColors.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xB3000000),
                  blurRadius: 30,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 8, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey<String>('ask-pandora-objective'),
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: disabled,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message Pandora',
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                    ),
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 16,
                      height: 1.35,
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                  Row(
                    children: [
                      MenuAnchor(
                        alignmentOffset: const Offset(0, -8),
                        style: MenuStyle(
                          backgroundColor: const WidgetStatePropertyAll(
                            PandoraSimpleColors.surface,
                          ),
                          elevation: const WidgetStatePropertyAll(10),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 8),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(
                                color: PandoraSimpleColors.line,
                              ),
                            ),
                          ),
                        ),
                        menuChildren: [
                          _ComposerMenuItem(
                            key: const ValueKey<String>(
                              'ask-pandora-menu-camera',
                            ),
                            label: 'Camera',
                            icon: Icons.camera_alt_outlined,
                            onPressed: onCamera,
                          ),
                          _ComposerMenuItem(
                            key: const ValueKey<String>(
                              'ask-pandora-menu-photos',
                            ),
                            label: 'Photos',
                            icon: Icons.photo_outlined,
                            onPressed: onPhotos,
                          ),
                          _ComposerMenuItem(
                            key: const ValueKey<String>(
                              'ask-pandora-menu-files',
                            ),
                            label: 'Files',
                            icon: Icons.insert_drive_file_outlined,
                            onPressed: onAttach,
                          ),
                          _ComposerMenuItem(
                            key: const ValueKey<String>(
                              'ask-pandora-menu-services',
                            ),
                            label: 'Services',
                            icon: Icons.extension_outlined,
                            onPressed: onServices,
                          ),
                          _ComposerMenuItem(
                            key: const ValueKey<String>(
                              'ask-pandora-menu-project-context',
                            ),
                            label: 'Project context',
                            icon: Icons.workspaces_outline,
                            onPressed: onProjectContext,
                          ),
                        ],
                        builder: (context, controller, child) => IconButton(
                          key: const ValueKey<String>('ask-pandora-plus'),
                          tooltip: 'Open menu',
                          onPressed: disabled || submitting
                              ? null
                              : () {
                                  if (controller.isOpen) {
                                    controller.close();
                                  } else {
                                    controller.open();
                                  }
                                },
                          icon: const Icon(Icons.add_rounded),
                          color: PandoraSimpleColors.ink,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Voice input',
                        onPressed: disabled || submitting ? null : onDictate,
                        icon: const Icon(Icons.mic_none_rounded),
                        color: PandoraSimpleColors.ink,
                      ),
                      const Spacer(),
                      SizedBox.square(
                        dimension: 42,
                        child: FilledButton(
                          key: const ValueKey<String>('ask-pandora-submit'),
                          onPressed: disabled || submitting ? null : onSubmit,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF1F1F1F),
                            shape: const CircleBorder(),
                          ),
                          child: submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.black,
                                  size: 22,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pandora can make mistakes. Review important changes before publishing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PandoraSimpleColors.muted, fontSize: 10.5),
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
      foregroundColor: const WidgetStatePropertyAll(PandoraSimpleColors.ink),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
  );
}

class _ChatMessage {
  const _ChatMessage._(this.text, this.isUser);

  const _ChatMessage.user(String text) : this._(text, true);
  const _ChatMessage.pandora(String text) : this._(text, false);

  final String text;
  final bool isUser;
}
