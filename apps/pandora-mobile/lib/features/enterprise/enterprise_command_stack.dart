import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/activity/pandora_activity_presentation_policy.dart';
import '../../core/activity/pandora_activity_projection.dart';
import '../../core/activity/pandora_activity_timeline_controller.dart';
import '../../core/activity/pandora_activity_timeline_view.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/network/idempotency_key.dart';
import '../simple/pandora_v2_ui.dart';
import 'enterprise_command_bus.dart';
import 'enterprise_page_context.dart';

class EnterpriseCommandStack extends StatefulWidget {
  const EnterpriseCommandStack({
    super.key,
    required this.child,
    this.onVerifiedResult,
  });

  final Widget child;
  final ValueChanged<PandoraActivityProjection>? onVerifiedResult;

  @override
  State<EnterpriseCommandStack> createState() => _EnterpriseCommandStackState();
}

class _EnterpriseCommandStackState extends State<EnterpriseCommandStack> {
  final TextEditingController _controller = TextEditingController();
  final PandoraActivityTimelineController _activity =
      PandoraActivityTimelineController();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();

  String? _threadId;
  String? _error;
  String? _notifiedVerifiedResultEventId;
  bool _submitting = false;
  bool _receiptExpanded = false;

  @override
  void initState() {
    super.initState();
    _activity.addListener(_onActivityChanged);
    EnterpriseCommandDraftBus.shared.draft.addListener(_onDraftOffered);
  }

  void _onDraftOffered() {
    final value = EnterpriseCommandDraftBus.shared.draft.value;
    if (value == null || value.trim().isEmpty) return;
    _controller
      ..text = value.trim()
      ..selection = TextSelection.collapsed(offset: value.trim().length);
    EnterpriseCommandDraftBus.shared.consume();
    if (mounted) setState(() {});
  }

  void _onActivityChanged() {
    final latest = pandoraLatestPresentableActivity(_activity.events);
    if (latest?.state == PandoraActivityState.result &&
        latest!.eventId != _notifiedVerifiedResultEventId) {
      _notifiedVerifiedResultEventId = latest.eventId;
      widget.onVerifiedResult?.call(latest);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    EnterpriseCommandDraftBus.shared.draft.removeListener(_onDraftOffered);
    _activity.removeListener(_onActivityChanged);
    _activity.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final objective = value.trim();
    if (objective.isEmpty || _submitting) return;

    final dependencies = PandoraDependencies.of(context);
    final intelligence = dependencies.intelligence;
    if (intelligence == null) {
      setState(() => _error = 'Pandora intelligence is not connected.');
      return;
    }

    final pageContext = EnterprisePageContextScope.of(context);
    await _activity.clear();
    _notifiedVerifiedResultEventId = null;
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _receiptExpanded = false;
      _error = null;
    });
    try {
      final execution = await intelligence.startChatExecution(
        message: objective,
        requestId: _keys.create('enterprise-command'),
        threadId: _threadId,
        projectId: pageContext.projectId,
        enterpriseContext: pageContext.toWire(),
      );
      await _activity.bind(jobId: execution.jobId, stream: execution.events);
      final turn = await execution.turn;
      if (!mounted) return;
      setState(() {
        _threadId = turn.threadId;
        _controller.clear();
      });
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Pandora could not complete that command safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = pandoraLatestPresentableActivity(_activity.events);
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Column(
        key: const ValueKey<String>('enterprise-command-stack'),
        children: [
          Expanded(child: widget.child),
          if (latest != null || _error != null)
            Container(
              key: const ValueKey<String>('enterprise-activity-theatre'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              color: PandoraV2Colors.canvas,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (latest != null)
                    if (latest.state.isTerminal && !_receiptExpanded)
                      _EnterpriseTerminalReceipt(
                        activity: latest,
                        onViewResult: () =>
                            setState(() => _receiptExpanded = true),
                      )
                    else
                      PandoraActivityTimelineView(
                        events: <PandoraActivityProjection>[latest],
                      ),
                  if (_receiptExpanded && latest?.state.isTerminal == true)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _receiptExpanded = false),
                        child: const Text('Collapse result'),
                      ),
                    ),
                  if (_error != null) ...[
                    if (latest != null) const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      label: _error,
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: PandoraV2Colors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: PandoraV2IntentSurface(
              key: const ValueKey<String>('enterprise-command-bar'),
              controller: _controller,
              hintText: 'Ask Pandora about this page',
              onSubmit: _submit,
              enabled: !_submitting,
              submitTooltip: _submitting ? 'Command running' : 'Send command',
            ),
          ),
        ],
      ),
    );
  }
}

class _EnterpriseTerminalReceipt extends StatelessWidget {
  const _EnterpriseTerminalReceipt({
    required this.activity,
    required this.onViewResult,
  });

  final PandoraActivityProjection activity;
  final VoidCallback onViewResult;

  @override
  Widget build(BuildContext context) {
    final failed = activity.state == PandoraActivityState.failed;
    final cancelled = activity.state == PandoraActivityState.cancelled;
    final summary = activity.outcome?.summary.trim().isNotEmpty == true
        ? activity.outcome!.summary
        : activity.message;
    final icon = failed
        ? Icons.error_outline_rounded
        : cancelled
            ? Icons.cancel_outlined
            : Icons.check_circle_outline_rounded;
    final color = failed
        ? PandoraV2Colors.danger
        : cancelled
            ? PandoraV2Colors.warning
            : PandoraV2Colors.success;
    return Semantics(
      liveRegion: true,
      label: 'Command receipt. $summary',
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  summary,
                  style: const TextStyle(fontSize: 13.5, height: 1.3),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('enterprise-view-result'),
              onPressed: onViewResult,
              child: const Text('View result'),
            ),
          ],
        ),
      ),
    );
  }
}
