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
  @override
  void initState() {
    super.initState();
    _activity.addListener(_onActivityChanged);
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
    return Column(
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
                  PandoraActivityTimelineView(
                    events: <PandoraActivityProjection>[latest],
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
    );
  }
}
