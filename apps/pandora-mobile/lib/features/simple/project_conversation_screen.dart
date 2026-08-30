import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/widgets/pandora_mark.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

enum ProjectConversationMode { create, iteration }

typedef ProjectConversationBuildCallback = void Function(BuildContext context);

class ProjectConversationScreen extends StatefulWidget {
  const ProjectConversationScreen({
    super.key,
    required this.project,
    required this.onBuildConfirmed,
    this.initialIntentText,
    this.initialSourceIntentId,
    this.mode = ProjectConversationMode.create,
  });

  final CustomerProject project;
  final String? initialIntentText;
  final String? initialSourceIntentId;
  final ProjectConversationMode mode;
  final ProjectConversationBuildCallback onBuildConfirmed;

  @override
  State<ProjectConversationScreen> createState() =>
      _ProjectConversationScreenState();
}

class _ProjectConversationScreenState extends State<ProjectConversationScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  final _keys = IdempotencyKeyFactory();
  Timer? _refreshTimer;
  List<OwnerProjectConversationTurn> _history =
      const <OwnerProjectConversationTurn>[];
  OwnerProjectUnderstanding _understanding =
      const OwnerProjectUnderstanding.waiting();
  String? _activeSourceIntentId;
  String? _pendingMessageKey;
  String? _pendingMessageText;
  String? _error;
  var _started = false;
  var _refreshing = false;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeSourceIntentId = widget.initialSourceIntentId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_refresh());
    _scheduleRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) {
      if (mounted) {
        setState(() {
          _error = 'Pandora cannot refresh this conversation right now.';
        });
      }
      return;
    }

    _refreshing = true;
    try {
      final history = await experience.conversationHistory(
        projectId: widget.project.id,
      );
      var understanding = _understanding;
      final sourceIntentId = _activeSourceIntentId;
      if (sourceIntentId != null &&
          understanding.state == OwnerProjectUnderstandingState.waiting) {
        understanding = await experience.understanding(
          projectId: widget.project.id,
          expectedSourceIntentId: sourceIntentId,
        );
      }
      if (!mounted) return;
      setState(() {
        _history = history;
        _understanding = understanding;
        _error = null;
      });
      if (understanding.state != OwnerProjectUnderstandingState.waiting) {
        _refreshTimer?.cancel();
      }
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      _refreshing = false;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_activeSourceIntentId == null ||
        _understanding.state != OwnerProjectUnderstandingState.waiting) {
      return;
    }
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _sendMessage() async {
    final text = _composer.text.trim();
    if (text.length < 2) {
      setState(() => _error = 'Tell Pandora what you want to change.');
      return;
    }
    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) {
      setState(() => _error = 'Pandora cannot save that message right now.');
      return;
    }

    if (_pendingMessageText != text) {
      _pendingMessageText = text;
      _pendingMessageKey = _keys.create('project-conversation-message');
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final intentId = await experience.submitIntent(
        projectId: widget.project.id,
        intentText: text,
        intentKind: _history.isEmpty ? 'create' : 'change',
        idempotencyKey: _pendingMessageKey,
      );
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _activeSourceIntentId = intentId;
        _understanding = const OwnerProjectUnderstanding.waiting();
        _pendingMessageKey = null;
        _pendingMessageText = null;
      });
      await _refresh();
      _scheduleRefresh();
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _buildConfirmed() {
    if (!_understanding.isReady) return;
    widget.onBuildConfirmed(context);
  }

  @override
  Widget build(BuildContext context) {
    final activeSourceIntentId = _activeSourceIntentId;
    final waiting =
        activeSourceIntentId != null &&
        _understanding.state == OwnerProjectUnderstandingState.waiting;
    final rejected =
        activeSourceIntentId != null &&
        _understanding.state == OwnerProjectUnderstandingState.rejected;
    final ready = activeSourceIntentId != null && _understanding.isReady;

    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: 'Pandora',
        subtitle: widget.project.name,
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen()),
        ),
        onAvatar: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.project.name,
            style: const TextStyle(
              color: PandoraSimpleColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Build it with Pandora. Keep talking until the plan feels right.',
            style: pandoraSimpleMutedText,
          ),
          const SizedBox(height: 22),
          if (_history.isEmpty &&
              (widget.initialIntentText?.trim().isNotEmpty ?? false))
            _UserMessageBubble(text: widget.initialIntentText!.trim()),
          for (final turn in _history) ...[
            _UserMessageBubble(text: turn.intentText),
            if (turn.intentId != activeSourceIntentId &&
                turn.assistantSummary != null)
              _PandoraMessageBubble(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn.assistantSummary!,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 15.5,
                        height: 1.42,
                      ),
                    ),
                    if (turn.projectType != null) ...[
                      const SizedBox(height: 9),
                      _MiniLabel(text: turn.projectType!),
                    ],
                  ],
                ),
              ),
          ],
          if (_history.isEmpty && activeSourceIntentId == null)
            const _PandoraMessageBubble(
              child: Text(
                'Tell me what you want to change or improve. I’ll update the project plan before anything is built.',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 15.5,
                  height: 1.42,
                ),
              ),
            ),
          if (waiting)
            const _PandoraMessageBubble(child: _UnderstandingIndicator()),
          if (rejected)
            const _PandoraMessageBubble(
              child: Text(
                'I need a little more direction before I can turn that into a reliable build plan. Tell me what result matters most and I’ll try again.',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 15.5,
                  height: 1.42,
                ),
              ),
            ),
          if (ready)
            _PandoraMessageBubble(
              child: _PrototypeReply(
                understanding: _understanding,
                fallbackType: widget.project.buildKind.label,
                buildLabel: widget.mode == ProjectConversationMode.iteration
                    ? 'Build updated preview'
                    : 'Build this',
                onBuild: _buildConfirmed,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PandoraSimpleColors.deepRed,
                fontSize: 13.5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _ConversationComposer(
            controller: _composer,
            sending: _sending,
            onSend: _sendMessage,
          ),
          const SizedBox(height: 8),
          const Text(
            'Nothing is built or published until you confirm it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PandoraSimpleColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final compact = _compactMessage(text);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(left: 42, bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: PandoraSimpleColors.ink,
          borderRadius: BorderRadius.circular(20)
              .copyWith(bottomRight: const Radius.circular(6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compact,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                height: 1.42,
              ),
            ),
            if (compact.length != text.trim().length) ...[
              const SizedBox(height: 7),
              const Text(
                'Full request saved to this project',
                style: TextStyle(
                  color: Color(0xFFBEBEBE),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PandoraMessageBubble extends StatelessWidget {
  const _PandoraMessageBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 660),
      margin: const EdgeInsets.only(right: 28, bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: PandoraSimpleColors.surface,
        borderRadius: BorderRadius.circular(20)
            .copyWith(bottomLeft: const Radius.circular(6)),
        border: Border.all(color: PandoraSimpleColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              PandoraMark(size: 27, color: PandoraSimpleColors.red),
              SizedBox(width: 8),
              Text(
                'Pandora',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

class _UnderstandingIndicator extends StatelessWidget {
  const _UnderstandingIndicator();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: PandoraSimpleColors.red,
        ),
      ),
      SizedBox(width: 11),
      Expanded(
        child: Text(
          'I’m understanding what you want and turning it into a buildable prototype…',
          style: TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 15.5,
            height: 1.42,
          ),
        ),
      ),
    ],
  );
}

class _PrototypeReply extends StatelessWidget {
  const _PrototypeReply({
    required this.understanding,
    required this.fallbackType,
    required this.buildLabel,
    required this.onBuild,
  });

  final OwnerProjectUnderstanding understanding;
  final String fallbackType;
  final String buildLabel;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final projectType = understanding.projectType ?? fallbackType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'I understand. Here’s the prototype I’m going to build.',
          style: TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAFA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF0D1D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PrototypeField(label: 'Project', value: projectType),
              if (understanding.businessSummary != null)
                _PrototypeField(
                  label: 'What it will do',
                  value: understanding.businessSummary!,
                ),
              if (understanding.targetUsers != null)
                _PrototypeField(
                  label: 'For',
                  value: understanding.targetUsers!,
                ),
              if (understanding.requirements.isNotEmpty) ...[
                const Text(
                  'Key experience',
                  style: TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                for (final item in understanding.requirements.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          color: PandoraSimpleColors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              color: PandoraSimpleColors.ink,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (understanding.objectives.isNotEmpty)
                _PrototypeField(
                  label: 'Business goal',
                  value: understanding.objectives.first,
                  last: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'Reply with any change you want, or build this version.',
          style: TextStyle(
            color: PandoraSimpleColors.muted,
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 13),
        PandoraPrimaryButton(
          label: buildLabel,
          icon: Icons.auto_awesome_rounded,
          onPressed: onBuild,
          expanded: true,
        ),
      ],
    );
  }
}

class _PrototypeField extends StatelessWidget {
  const _PrototypeField({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PandoraSimpleColors.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            height: 1.38,
          ),
        ),
      ],
    ),
  );
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: PandoraSimpleColors.blush,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: PandoraSimpleColors.deepRed,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ConversationComposer extends StatelessWidget {
  const _ConversationComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) => Material(
    color: PandoraSimpleColors.surface,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
      decoration: BoxDecoration(
        border: Border.all(color: PandoraSimpleColors.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Tell Pandora what to change…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 44,
            child: IconButton.filled(
              onPressed: sending ? null : () => unawaited(onSend()),
              style: IconButton.styleFrom(
                backgroundColor: PandoraSimpleColors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: PandoraSimpleColors.line,
              ),
              icon: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    ),
  );
}

String _compactMessage(String value) {
  final text = value.trim();
  const limit = 900;
  if (text.length <= limit) return text;
  return '${text.substring(0, limit).trimRight()}…';
}
