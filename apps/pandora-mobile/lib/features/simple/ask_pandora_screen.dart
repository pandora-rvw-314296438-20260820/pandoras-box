import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'build_preview_flow.dart';
import 'pandora_simple_ui.dart';

enum _RequestKind {
  build(
    'Build a new system',
    'Website, app, portal or internal tool',
    Icons.grid_view_rounded,
    PandoraSimpleColors.red,
    PandoraSimpleColors.blush,
  ),
  improve(
    'Improve something live',
    'Change, repair or upgrade an existing system',
    Icons.trending_up_rounded,
    PandoraSimpleColors.blue,
    PandoraSimpleColors.blueWash,
  ),
  automate(
    'Automate a workflow',
    'Remove repetitive manual coordination',
    Icons.hub_outlined,
    PandoraSimpleColors.green,
    PandoraSimpleColors.greenWash,
  ),
  businessQuestion(
    'Ask about my business',
    'Get answers from verified business context',
    Icons.chat_bubble_outline_rounded,
    PandoraSimpleColors.purple,
    PandoraSimpleColors.purpleWash,
  );

  const _RequestKind(
    this.label,
    this.description,
    this.icon,
    this.foreground,
    this.background,
  );

  final String label;
  final String description;
  final IconData icon;
  final Color foreground;
  final Color background;
}

class AskPandoraScreen extends StatefulWidget {
  const AskPandoraScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  State<AskPandoraScreen> createState() => _AskPandoraScreenState();
}

class _AskPandoraScreenState extends State<AskPandoraScreen> {
  static const _suggestions = <String>[
    'Build online booking',
    'Automate follow-ups',
    'Improve my website',
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
      setState(() {
        _recent.remove(objective);
        _recent.insert(0, objective);
        if (_recent.length > 4) _recent.removeLast();
        _submissionKey = null;
        _outcomeUnknown = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BuildProgressScreen(receipt: receipt, request: objective),
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

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Ask Pandora',
          subtitle: 'Tell Pandora what your business needs.',
          onNotifications: () => Navigator.of(
            context,
          ).push(
              MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen())),
          onAvatar: () => Navigator.of(
            context,
          ).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraSimpleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PandoraIconBadge(
                          icon: Icons.auto_awesome_rounded, size: 52),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What should Pandora accomplish?',
                              style: TextStyle(
                                color: PandoraSimpleColors.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.25,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Describe the business result. Pandora will handle the technical work.',
                              style: PandoraSimpleMutedText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFECC8CE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                          child: Text(
                            'For example:',
                            style: TextStyle(
                              color: PandoraSimpleColors.deepRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextField(
                          key: const ValueKey<String>('ask-pandora-objective'),
                          controller: _objective,
                          focusNode: _objectiveFocus,
                          readOnly: _outcomeUnknown,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 4000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText:
                                'Build an online booking system for my aircon service business.',
                            filled: false,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.fromLTRB(18, 8, 18, 8),
                          ),
                          style: const TextStyle(
                            color: PandoraSimpleColors.ink,
                            fontSize: 17,
                            height: 1.35,
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Voice input',
                                onPressed: _outcomeUnknown || _submitting
                                    ? null
                                    : _dictate,
                                icon: const Icon(Icons.mic_none_rounded),
                                color: PandoraSimpleColors.red,
                              ),
                              IconButton(
                                tooltip: 'Attach text file',
                                onPressed: _outcomeUnknown || _submitting
                                    ? null
                                    : _attach,
                                icon: const Icon(Icons.attach_file_rounded),
                                color: PandoraSimpleColors.red,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_attachment != null) ...[
                    const SizedBox(height: 10),
                    InputChip(
                      avatar: const Icon(Icons.description_outlined, size: 18),
                      label: Text(_attachment!.name),
                      onDeleted: _outcomeUnknown || _submitting
                          ? null
                          : () => setState(() => _attachment = null),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final helper = const Text(
                        'You can type, speak, attach a document, or share a screenshot.',
                        style:
                            TextStyle(color: Color(0xFF8B8985), fontSize: 12.5),
                      );
                      final submit = PandoraPrimaryButton(
                        key: const ValueKey<String>('ask-pandora-submit'),
                        label: _submitting ? 'Sending safely…' : 'Continue',
                        loading: _submitting,
                        onPressed:
                            _outcomeUnknown || _submitting ? null : _submit,
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            helper,
                            const SizedBox(height: 12),
                            submit
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: helper),
                          const SizedBox(width: 12),
                          submit,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Try asking',
                    style: TextStyle(
                      color: PandoraSimpleColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final suggestion in _suggestions)
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: _outcomeUnknown || _submitting
                              ? null
                              : () => _useSuggestion(suggestion),
                          backgroundColor: const Color(0xFFF9F8F6),
                          side:
                              const BorderSide(color: PandoraSimpleColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              PandoraSimpleCard(
                shadow: false,
                backgroundColor: const Color(0xFFFFF4F5),
                borderColor: const Color(0xFFF0C3CA),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: PandoraSimpleColors.deepRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: PandoraSimpleColors.deepRed,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            const PandoraSectionTitle(title: 'Choose how to start'),
            const Text(
              'Pandora will adapt the process to your goal.',
              style: PandoraSimpleMutedText,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final count = width >= 610 ? 2 : 1;
                final itemWidth = (width - ((count - 1) * 14)) / count;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final kind in _RequestKind.values)
                      SizedBox(
                        width: itemWidth,
                        child: _RequestKindCard(
                          kind: kind,
                          selected: _kind == kind,
                          onTap: _outcomeUnknown || _submitting
                              ? null
                              : () => setState(() => _kind = kind),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            PandoraSectionTitle(
              title: 'Recent requests',
              actionLabel: _recent.isEmpty ? null : 'View all',
              onAction: _recent.isEmpty
                  ? null
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All recent requests are shown here.'),
                        ),
                      ),
            ),
            _RecentRequests(
              requests: _recent,
              onSelect: _useSuggestion,
              disabled: _outcomeUnknown || _submitting,
            ),
            const SizedBox(height: 24),
            const PandoraSectionTitle(title: 'Pandora already understands'),
            PandoraSimpleCard(
              shadow: false,
              backgroundColor: const Color(0xFFFFFAFA),
              borderColor: const Color(0xFFF0D3D7),
              child: FutureBuilder<RepositorySnapshot<HomeSummary>>(
                future: _contextFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator(
                      color: PandoraSimpleColors.red,
                    );
                  }
                  final home = snapshot.data?.data;
                  final ready = home?.freshness.isFresh == true;
                  return Row(
                    children: [
                      const PandoraIconBadge(
                        icon: Icons.article_outlined,
                        size: 46,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ready
                                  ? 'Your business context is ready'
                                  : 'Business context needs verification',
                              style: const TextStyle(
                                color: PandoraSimpleColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              home == null
                                  ? 'Pandora could not verify context right now.'
                                  : 'Brand, systems, preferences and verified decisions',
                              style: PandoraSimpleMutedText,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ready
                                  ? 'Fresh governed context is available to Pandora'
                                  : 'Requests still fail closed at the server boundary',
                              style: TextStyle(
                                color: ready
                                    ? PandoraSimpleColors.green
                                    : PandoraSimpleColors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      PandoraSecondaryButton(
                        label: 'Review memory',
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Memory review opens through Pandora’s governed context view.',
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _RequestKindCard extends StatelessWidget {
  const _RequestKindCard({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final _RequestKind kind;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        onTap: onTap,
        shadow: false,
        borderColor:
            selected ? PandoraSimpleColors.red : PandoraSimpleColors.line,
        child: Row(
          children: [
            PandoraIconBadge(
              icon: kind.icon,
              foreground: kind.foreground,
              background: kind.background,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    kind.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PandoraSimpleMutedText,
                  ),
                ],
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? PandoraSimpleColors.red
                    : PandoraSimpleColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      );
}

class _RecentRequests extends StatelessWidget {
  const _RecentRequests({
    required this.requests,
    required this.onSelect,
    required this.disabled,
  });

  final List<String> requests;
  final ValueChanged<String> onSelect;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const PandoraEmptyTruth(
        title: 'No recent request on this device',
        message: 'A request appears here after Pandora accepts it.',
      );
    }
    return PandoraSimpleCard(
      padding: EdgeInsets.zero,
      shadow: false,
      child: Column(
        children: [
          for (var index = 0; index < requests.length; index++) ...[
            InkWell(
              onTap: disabled ? null : () => onSelect(requests[index]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    PandoraIconBadge(
                      icon: index.isEven
                          ? Icons.grid_view_rounded
                          : Icons.hub_outlined,
                      foreground: index.isEven
                          ? PandoraSimpleColors.purple
                          : PandoraSimpleColors.red,
                      background: index.isEven
                          ? PandoraSimpleColors.purpleWash
                          : PandoraSimpleColors.blush,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requests[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PandoraSimpleColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Accepted by Pandora on this device',
                            style: PandoraSimpleMutedText,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Open',
                      style: TextStyle(
                        color: PandoraSimpleColors.deepRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: PandoraSimpleColors.deepRed,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (index != requests.length - 1)
              const Divider(height: 1, color: PandoraSimpleColors.line),
          ],
        ],
      ),
    );
  }
}
