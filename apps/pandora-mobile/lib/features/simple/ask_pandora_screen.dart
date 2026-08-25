import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import 'build_preview_flow.dart';

enum _RequestKind {
  build('Build', Icons.add_box_outlined),
  improve('Improve', Icons.auto_fix_high_outlined),
  automate('Automate', Icons.bolt_outlined),
  businessQuestion('Business question', Icons.query_stats_outlined);

  const _RequestKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AskPandoraScreen extends StatefulWidget {
  const AskPandoraScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  State<AskPandoraScreen> createState() => _AskPandoraScreenState();
}

class _AskPandoraScreenState extends State<AskPandoraScreen> {
  static const _suggestions = <String>[
    'Build a premium booking system customers can use on mobile.',
    'Improve my existing site so more visitors become customers.',
    'Automate the repetitive work my team does every day.',
    'Tell me what needs my attention across the business.',
  ];

  final TextEditingController _objective = TextEditingController();
  final FocusNode _objectiveFocus = FocusNode();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  final List<String> _recent = <String>[];
  _RequestKind _kind = _RequestKind.build;
  PandoraTextAttachment? _attachment;
  Future<RepositorySnapshot<HomeSummary>>? _contextFuture;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _contextFuture ??= PandoraDependencies.of(context).repository.home();
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

  String _message(String objective) => [
        'Request type: ${_kind.label}',
        'Owner request: $objective',
        if (_attachment != null) _attachment!.promptBlock,
        'Preserve Pandora governance, verification, approvals, and rollback controls.',
      ].join('\n\n');

  Future<void> _submit() async {
    final objective = _objective.text.trim();
    if (objective.isEmpty) {
      setState(() => _error = 'Tell Pandora the result you want.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    _submissionKey ??= _keys.create('simple-intake');
    try {
      final receipt = await PandoraDependencies.of(context).repository.ask(
            message: _message(objective),
            idempotencyKey: _submissionKey,
          );
      if (!mounted) return;
      setState(() {
        _recent.remove(objective);
        _recent.insert(0, objective);
        if (_recent.length > 4) _recent.removeLast();
        _submissionKey = null;
        _outcomeUnknown = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BuildProgressScreen(
            receipt: receipt,
            request: objective,
          ),
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

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Ask Pandora',
        subtitle: 'Business intent in. Governed working result out.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What do you want Pandora to do?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: PandoraSpacing.xs),
                  Text(
                    'Describe the result. Pandora resolves the technical steps, checks risk, and shows you what needs a decision.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final kind in _RequestKind.values)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: PandoraSpacing.xs,
                            ),
                            child: ChoiceChip(
                              selected: _kind == kind,
                              avatar: Icon(kind.icon, size: 18),
                              label: Text(kind.label),
                              onSelected: _outcomeUnknown || _submitting
                                  ? null
                                  : (_) => setState(() => _kind = kind),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                  TextField(
                    key: const ValueKey<String>('ask-pandora-objective'),
                    controller: _objective,
                    focusNode: _objectiveFocus,
                    readOnly: _outcomeUnknown,
                    minLines: 4,
                    maxLines: 9,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'For example: Build a booking system customers can use from their phone.',
                    ),
                  ),
                  if (_attachment != null) ...[
                    const SizedBox(height: PandoraSpacing.xs),
                    InputChip(
                      avatar: const Icon(Icons.description_outlined, size: 18),
                      label: Text(_attachment!.name),
                      onDeleted: _outcomeUnknown || _submitting
                          ? null
                          : () => setState(() => _attachment = null),
                    ),
                  ],
                  const SizedBox(height: PandoraSpacing.xs),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Voice input',
                        onPressed:
                            _outcomeUnknown || _submitting ? null : _dictate,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
                      const SizedBox(width: PandoraSpacing.xs),
                      IconButton.filledTonal(
                        tooltip: 'Attach text file',
                        onPressed:
                            _outcomeUnknown || _submitting ? null : _attach,
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        key: const ValueKey<String>('ask-pandora-submit'),
                        onPressed:
                            _outcomeUnknown || _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                        label: Text(_submitting ? 'Sending safely…' : 'Send'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: PandoraSpacing.sm),
              Container(
                padding: const EdgeInsets.all(PandoraSpacing.md),
                decoration: BoxDecoration(
                  color: context.pandoraPalette.subtleSurface,
                  borderRadius: PandoraRadius.controlBorder,
                  border: Border.all(color: context.pandoraPalette.outlineSoft),
                ),
                child: Text(_error!),
              ),
            ],
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Suggested requests',
              subtitle: 'Tap one to edit it before sending.',
              child: Column(
                children: [
                  for (final suggestion in _suggestions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.north_east_rounded),
                      title: Text(suggestion),
                      onTap: _outcomeUnknown || _submitting
                          ? null
                          : () {
                              _objective.text = suggestion;
                              _objective.selection = TextSelection.collapsed(
                                offset: suggestion.length,
                              );
                              _objectiveFocus.requestFocus();
                            },
                    ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Memory & context',
              subtitle:
                  'Governed context is resolved server-side; credentials never enter the APK.',
              child: FutureBuilder<RepositorySnapshot<HomeSummary>>(
                future: _contextFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (!snapshot.hasData) {
                    return const Text(
                      'Context state could not be verified. Requests still fail closed at the server boundary.',
                    );
                  }
                  final home = snapshot.data!.data;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      home.freshness.isFresh
                          ? Icons.memory_rounded
                          : Icons.history_toggle_off_rounded,
                    ),
                    title: Text(home.healthLabel),
                    subtitle: Text(
                      home.freshness.isFresh
                          ? 'Fresh governed context is available.'
                          : 'Context freshness is not verified.',
                    ),
                  );
                },
              ),
            ),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: PandoraSpacing.md),
              PandoraSurface(
                title: 'Recent requests',
                child: Column(
                  children: [
                    for (final request in _recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(request),
                        onTap: _outcomeUnknown || _submitting
                            ? null
                            : () {
                                _objective.text = request;
                                _objective.selection = TextSelection.collapsed(
                                  offset: request.length,
                                );
                              },
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}
