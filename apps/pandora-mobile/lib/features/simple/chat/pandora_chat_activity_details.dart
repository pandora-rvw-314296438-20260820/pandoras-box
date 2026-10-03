part of '../ask_pandora_screen.dart';

extension _PandoraActivityDetails on AskPandoraScreenState {
  bool _canControl(PandoraChatAttemptToken token) {
    if (!_current(token) ||
        _routes[token.attemptId] != _ChatExecutionRoute.cloud) {
      return false;
    }
    final turn = _chat.state.turn(token.turnId)!;
    return !turn.attempt!.cancellationRequested &&
        turn.reply.isEmpty &&
        (turn.phase == PandoraChatPhase.accepted ||
            turn.phase == PandoraChatPhase.processing);
  }

  Future<void> _showActivityDetails(PandoraChatTurn turn) async {
    final token = turn.attempt?.token;
    final jobId = turn.attempt?.activityJobId;
    final intelligence = _dependencies.intelligence;
    if (token == null || jobId == null || intelligence == null) return;
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PandoraSimpleColors.surface,
      builder: (_) => _ChatActivityDetails(
        chat: _chat,
        token: token,
        jobId: jobId,
        events: intelligence.watchChatActivity(jobId),
        canControl: () => _canControl(token),
        onControl: (type, instruction) async {
          if (!_canControl(token)) return false;
          final requestId =
              '${token.attemptId}:control:${DateTime.now().microsecondsSinceEpoch}';
          await intelligence.controlActivityJob(
              jobId: jobId,
              requestId: requestId,
              type: type,
              instruction: instruction);
          return _sameAttempt(token);
        },
      ),
    );
    await presentContextRoute(route);
  }
}

class _ChatActivityDetails extends StatefulWidget {
  const _ChatActivityDetails(
      {required this.chat,
      required this.token,
      required this.jobId,
      required this.events,
      required this.canControl,
      required this.onControl});
  final PandoraChatController chat;
  final PandoraChatAttemptToken token;
  final String jobId;
  final Stream<Map<String, dynamic>> events;
  final bool Function() canControl;
  final Future<bool> Function(PandoraActivityControlType, String) onControl;
  @override
  State<_ChatActivityDetails> createState() => _ChatActivityDetailsState();
}

class _ChatActivityDetailsState extends State<_ChatActivityDetails> {
  final PandoraActivityTimelineController _timeline =
      PandoraActivityTimelineController();
  final TextEditingController _instruction = TextEditingController();
  bool _submittingControl = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _timeline.addListener(_changed);
    widget.chat.addListener(_changed);
    unawaited(_timeline.bind(jobId: widget.jobId, stream: widget.events));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chat.removeListener(_changed);
    _timeline.removeListener(_changed);
    _timeline.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _control(PandoraActivityControlType type) async {
    final text = _instruction.text.trim();
    if (_submittingControl || text.isEmpty || !widget.canControl()) return;
    setState(() {
      _submittingControl = true;
      _feedback = null;
    });
    try {
      final recorded = await widget.onControl(type, text);
      if (mounted) {
        setState(() {
          _feedback = recorded
              ? 'Your update was sent.'
              : 'This response has already moved on. Send a new message to continue.';
          _instruction.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _feedback =
            'The update could not be confirmed. Check Activity before sending it again.');
      }
    } finally {
      if (mounted) setState(() => _submittingControl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final canControl = widget.canControl();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, media.viewInsets.bottom + media.padding.bottom + 20),
      child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const Text('Activity',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (_timeline.events.isEmpty)
              Text(_timeline.publicError ?? 'Activity details are loading…')
            else
              PandoraActivityTimelineView(
                  key: const ValueKey<String>('ask-pandora-activity-theatre'),
                  events: _timeline.events),
            const SizedBox(height: 20),
            if (canControl) ...[
              const Text('Update this request before its response starts.'),
              TextField(
                  key: const ValueKey<String>('pandora-chat-control-input'),
                  controller: _instruction,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                      labelText: 'Instruction', counterText: '')),
              Wrap(spacing: 8, children: [
                TextButton(
                    key: const ValueKey<String>('pandora-chat-add-constraint'),
                    onPressed: _submittingControl
                        ? null
                        : () => _control(PandoraActivityControlType.constraint),
                    child: const Text('Add a constraint')),
                TextButton(
                    key:
                        const ValueKey<String>('pandora-chat-change-direction'),
                    onPressed: _submittingControl
                        ? null
                        : () => _control(PandoraActivityControlType.redirect),
                    child: const Text('Change direction')),
              ]),
            ] else
              const Text('Send a new message to continue or change direction.'),
            if (_feedback != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_feedback!)),
          ])),
    );
  }
}
