
import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import 'build_preview_flow.dart';
import 'pandora_simple_ui.dart';

class AskPandoraScreen extends StatefulWidget {
  const AskPandoraScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

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
    _objective.selection = TextSelection.collapsed(offset: _objective.text.length);
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

  String _message(String objective) => [
        'Owner request: $objective',
        if (_attachment != null) _attachment!.promptBlock,
        'Infer the correct Pandora workflow from the owner request.',
        'Preserve Pandora governance, verification, approvals, and rollback controls.',
      ].join('\n\n');

  Future<void> _submit() async {
    final objective = _objective.text.trim();
    if (objective.isEmpty) {
      setState(() => _error = 'Message Pandora first.');
      _objectiveFocus.requestFocus();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    _submissionKey ??= _keys.create('simple-intake');
    try {
      final receipt = await PandoraDependencies.of(context)
          .repository
          .ask(message: _message(objective), idempotencyKey: _submissionKey);
      if (!mounted) return;
      final reply = receipt.reply.trim().isEmpty
          ? 'I received that. I am opening the governed build flow now.'
          : receipt.reply.trim();
      setState(() {
        _messages.add(_ChatMessage.user(objective));
        _messages.add(_ChatMessage.pandora(reply));
        _objective.clear();
        _attachment = null;
        _submissionKey = null;
        _outcomeUnknown = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BuildProgressScreen(receipt: receipt, request: objective),
        ),
      );
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = error.outcomeMayBeUnknown;
        if (error.outcomeMayBeUnknown) {
          _error =
              '${error.message} Pandora will not retry this write. Check Activity before sending another request.';
        } else {
          _error = error.message;
          _submissionKey = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = true;
        _error =
            'Pandora could not confirm whether the request was received. It will not retry the write. Check Activity first.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      _error = null;
      _outcomeUnknown = false;
      _submissionKey = null;
    });
    _objectiveFocus.requestFocus();
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
                child: _messages.isEmpty
                    ? _EmptyConversation(
                        suggestions: _suggestions,
                        onSuggestion: _useSuggestion,
                        disabled: _outcomeUnknown || _submitting,
                      )
                    : _Conversation(messages: _messages),
              ),
              _Composer(
                controller: _objective,
                focusNode: _objectiveFocus,
                attachment: _attachment,
                error: _error,
                submitting: _submitting,
                disabled: _outcomeUnknown,
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
                onAttach: _attach,
                onDictate: _dictate,
                onSubmit: _submit,
                onRemoveAttachment: () => setState(() => _attachment = null),
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
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 52),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PandoraMark(size: 64),
                const SizedBox(height: 20),
                const Text(
                  'What can I help you build?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Describe the result in your own words. Pandora will handle the technical work behind it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                for (final suggestion in suggestions) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: disabled ? null : () => onSuggestion(suggestion),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PandoraSimpleColors.ink,
                        alignment: Alignment.centerLeft,
                        backgroundColor: PandoraSimpleColors.surface,
                        side: const BorderSide(color: PandoraSimpleColors.line),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(suggestion)),
                          const Icon(Icons.arrow_upward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ),
      );
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.messages});

  final List<_ChatMessage> messages;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final message = messages[index];
          if (message.isUser) {
            return Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDECEA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 15.5,
                        height: 1.4,
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
                child: PandoraMark(size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 15.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.attachment,
    required this.error,
    required this.submitting,
    required this.disabled,
    required this.onChanged,
    required this.onAttach,
    required this.onDictate,
    required this.onSubmit,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PandoraTextAttachment? attachment;
  final String? error;
  final bool submitting;
  final bool disabled;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final VoidCallback onDictate;
  final VoidCallback onSubmit;
  final VoidCallback onRemoveAttachment;

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFB42318),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (attachment != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.description_outlined, size: 17),
                    label: Text(attachment!.name),
                    onDeleted: submitting || disabled ? null : onRemoveAttachment,
                  ),
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
                          IconButton(
                            tooltip: 'Attach text file',
                            onPressed: disabled || submitting ? null : onAttach,
                            icon: const Icon(Icons.add_rounded),
                            color: PandoraSimpleColors.ink,
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
                                backgroundColor: PandoraSimpleColors.ink,
                                disabledBackgroundColor: const Color(0xFFE4E3E0),
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

class _ChatMessage {
  const _ChatMessage._(this.text, this.isUser);

  const _ChatMessage.user(String text) : this._(text, true);
  const _ChatMessage.pandora(String text) : this._(text, false);

  final String text;
  final bool isUser;
}
