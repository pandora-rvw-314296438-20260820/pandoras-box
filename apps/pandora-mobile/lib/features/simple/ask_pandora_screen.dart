import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import 'build_preview_flow.dart';
import 'project_create_experience.dart';
import 'project_experience_v2.dart';
import 'pandora_simple_ui.dart';

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
  State<AskPandoraScreen> createState() => _AskPandoraScreenState();
}

class _AskPandoraScreenState extends State<AskPandoraScreen> {
  static const _suggestions = <String>[
    'Build an online booking system',
    'Improve my website',
    'Automate customer follow-ups',
  ];

  final TextEditingController _objective = TextEditingController();
  final FocusNode _objectiveFocus = FocusNode();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  PandoraTextAttachment? _attachment;
  PandoraImageAttachment? _imageAttachment;
  String? _threadId;
  String? _pendingMessage;
  bool _submitting = false;
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
    _objective.selection =
        TextSelection.collapsed(offset: _objective.text.length);
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
        if (dependencies.projectExperienceRepository != null) {
          if (!mounted) return;
          setState(() {
            _messages.add(_ChatMessage.user(objective));
            _pendingMessage = null;
            _objective.clear();
            _attachment = null;
            _imageAttachment = null;
            _submissionKey = null;
          });
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CreateProjectExperienceScreen(
                initialIntent: objective,
              ),
            ),
          );
          return;
        }
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
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                BuildProgressScreen(receipt: receipt, request: objective),
          ),
        );
        return;
      }

      final turn = await intelligence.chat(
        message: objective,
        threadId: _threadId,
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
            builder: (_) => CreateProjectExperienceScreen(
              initialIntent: handoff.request,
            ),
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
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BuildProgressScreen(receipt: receipt, request: objective),
        ),
      );
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

  void _newChat() {
    if (_submitting) return;
    setState(() {
      _messages.clear();
      _objective.clear();
      _attachment = null;
      _imageAttachment = null;
      _threadId = null;
      _pendingMessage = null;
      _error = null;
      _outcomeUnknown = false;
      _submissionKey = null;
    });
    _objectiveFocus.requestFocus();
  }

  Future<void> _pickImage({required bool camera}) async {
    final image = camera
        ? await PandoraNativeIo.takePhoto()
        : await PandoraNativeIo.pickPhoto();
    if (!mounted) return;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(camera
              ? 'No camera image was attached.'
              : 'No supported photo was attached.'),
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
              _ChatHeader(onNewChat: _newChat),
              const Divider(height: 1, color: PandoraSimpleColors.line),
              Expanded(
                child: _messages.isEmpty && _pendingMessage == null
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
                error: _error,
                submitting: _submitting,
                disabled: _outcomeUnknown,
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
                onHome: widget.onHome,
                onProjects: widget.onProjects,
                onMore: widget.onMore,
                onCamera: () => _pickImage(camera: true),
                onPhotos: () => _pickImage(camera: false),
                onAttach: _attach,
                onDictate: _dictate,
                onSubmit: _submit,
                onRemoveAttachment: () => setState(() => _attachment = null),
                onRemoveImage: () => setState(() => _imageAttachment = null),
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
  Widget build(BuildContext context) => SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const PandoraMark(size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pandora',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New chat',
                onPressed: onNewChat,
                icon: const Icon(Icons.edit_square),
                color: PandoraSimpleColors.ink,
              ),
            ],
          ),
        ),
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
                const PandoraMark(size: 42),
                const SizedBox(height: 18),
                const Text(
                  'What can I help with?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.45,
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
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in suggestions)
                      ActionChip(
                        onPressed:
                            disabled ? null : () => onSuggestion(suggestion),
                        backgroundColor: PandoraSimpleColors.surface,
                        side: const BorderSide(color: PandoraSimpleColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        label: Text(
                          suggestion,
                          style: const TextStyle(
                            color: PandoraSimpleColors.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
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
              color: const Color(0xFFF0EFED),
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
          child: PandoraMark(size: 24),
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
          PandoraMark(size: 24),
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
            style: TextStyle(
              color: PandoraSimpleColors.muted,
              fontSize: 14,
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
    required this.error,
    required this.submitting,
    required this.disabled,
    required this.onChanged,
    required this.onHome,
    required this.onProjects,
    required this.onMore,
    required this.onCamera,
    required this.onPhotos,
    required this.onAttach,
    required this.onDictate,
    required this.onSubmit,
    required this.onRemoveAttachment,
    required this.onRemoveImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PandoraTextAttachment? attachment;
  final PandoraImageAttachment? imageAttachment;
  final String? error;
  final bool submitting;
  final bool disabled;
  final VoidCallback onChanged;
  final VoidCallback? onHome;
  final VoidCallback? onProjects;
  final VoidCallback? onMore;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onAttach;
  final VoidCallback onDictate;
  final VoidCallback onSubmit;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onRemoveImage;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              if (attachment != null || imageAttachment != null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (attachment != null)
                      InputChip(
                        avatar:
                            const Icon(Icons.description_outlined, size: 17),
                        label: Text(attachment!.name),
                        onDeleted:
                            submitting || disabled ? null : onRemoveAttachment,
                      ),
                    if (imageAttachment != null)
                      InputChip(
                        avatar: const Icon(Icons.image_outlined, size: 17),
                        label: Text(imageAttachment!.name),
                        onDeleted:
                            submitting || disabled ? null : onRemoveImage,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  color: PandoraSimpleColors.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFD8D7D4)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C000000),
                      blurRadius: 14,
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
                                  'ask-pandora-menu-home',
                                ),
                                label: 'Home',
                                icon: Icons.home_outlined,
                                onPressed: onHome,
                              ),
                              _ComposerMenuItem(
                                key: const ValueKey<String>(
                                  'ask-pandora-menu-projects',
                                ),
                                label: 'Projects',
                                icon: Icons.folder_outlined,
                                onPressed: onProjects,
                              ),
                              _ComposerMenuItem(
                                key: const ValueKey<String>(
                                  'ask-pandora-menu-more',
                                ),
                                label: 'More',
                                icon: Icons.menu_rounded,
                                onPressed: onMore,
                              ),
                              const Divider(height: 12),
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
                            onPressed:
                                disabled || submitting ? null : onDictate,
                            icon: const Icon(Icons.mic_none_rounded),
                            color: PandoraSimpleColors.ink,
                          ),
                          const Spacer(),
                          SizedBox.square(
                            dimension: 42,
                            child: FilledButton(
                              key: const ValueKey<String>('ask-pandora-submit'),
                              onPressed:
                                  disabled || submitting ? null : onSubmit,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: PandoraSimpleColors.ink,
                                disabledBackgroundColor:
                                    const Color(0xFFE4E3E0),
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
                                      color: Colors.white,
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
                style: TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 10.5,
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
          foregroundColor: const WidgetStatePropertyAll(
            PandoraSimpleColors.ink,
          ),
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
