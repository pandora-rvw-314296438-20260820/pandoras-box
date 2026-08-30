import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/analytics/owner_analytics.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';
import 'exact_source_verification_card.dart';

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  static const _suggestions = <String>[
    'Repair Pandora command connectivity and verify the owner journey.',
    'Review every verified blocker and prepare the safest next action.',
    'Prepare the safest next Android release without promoting production.',
    'Check connected services and tell me what needs attention.',
  ];

  final _objective = TextEditingController();
  final _idempotencyKeys = IdempotencyKeyFactory();
  bool _submitting = false;
  bool _outcomeUnknown = false;
  String? _submissionKey;
  IntakeReceipt? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPrompt?.trim();
    if (initial != null && initial.isNotEmpty) {
      _objective.text = initial;
      _objective.selection = TextSelection.collapsed(offset: initial.length);
    }
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'ask_pandora',
      ),
    );
  }

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  void _useSuggestion(String value) {
    if (_outcomeUnknown || _submitting) return;
    _objective
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    setState(() {
      _error = null;
      _receipt = null;
      _submissionKey = null;
    });
  }

  Future<void> _submit() async {
    final objective = _objective.text.trim();
    if (objective.isEmpty) {
      setState(() => _error = 'Describe what you want Pandora to accomplish.');
      return;
    }
    final timer = Stopwatch()..start();
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.commandSubmitted,
        resultClass: 'governed_intake',
      ),
    );
    setState(() {
      _submitting = true;
      _error = null;
      _receipt = null;
    });
    _submissionKey ??= _idempotencyKeys.create('command');
    try {
      final receipt = await PandoraDependencies.of(context)
          .repository
          .ask(message: objective, idempotencyKey: _submissionKey);
      timer.stop();
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.commandSucceeded,
          duration: timer.elapsed,
          resultClass: 'accepted',
        ),
      );
      if (mounted) {
        setState(() {
          _receipt = receipt;
          _outcomeUnknown = false;
          _submissionKey = null;
        });
      }
    } on PandoraRepositoryException catch (error) {
      timer.stop();
      final resultClass = error.outcomeMayBeUnknown
          ? 'outcome_unknown'
          : error.code == 'PANDORA_UNAVAILABLE'
              ? 'service_unavailable'
              : 'rejected';
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.commandFailed,
          duration: timer.elapsed,
          resultClass: resultClass,
          errorCode: error.code,
        ),
      );
      if (mounted) {
        setState(() {
          _outcomeUnknown = error.outcomeMayBeUnknown;
          if (error.code == 'PANDORA_UNAVAILABLE') {
            _error =
                'Pandora cannot currently reach the governed command service. '
                'No successful command is being claimed. Check service health '
                'and retry after availability returns.';
          } else if (error.outcomeMayBeUnknown) {
            _error =
                '${error.message} This app will not retry the write. Check '
                'Activity and the governed plan before starting another request.';
          } else {
            _error = error.message;
          }
          if (!error.outcomeMayBeUnknown) _submissionKey = null;
        });
      }
    } catch (_) {
      timer.stop();
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.commandFailed,
          duration: timer.elapsed,
          resultClass: 'outcome_unknown',
          errorCode: 'UNEXPECTED_COMMAND_FAILURE',
        ),
      );
      if (mounted) {
        setState(() {
          _outcomeUnknown = true;
          _error =
              'Pandora could not confirm whether that request was received. '
              'This app will not retry the write. Check Activity and the '
              'governed plan before starting another request.';
        });
      }
    } finally {
      if (timer.isRunning) timer.stop();
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Ask Pandora',
        subtitle: 'State the outcome. Pandora governs the steps.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OwnerBriefingHero(
              eyebrow: 'Intent to result',
              title: 'Describe the outcome, not the infrastructure',
              message:
                  'Pandora resolves the project, explains the plan, executes safe work, verifies the result, and keeps protected changes behind approval gates.',
              icon: Icons.auto_awesome_rounded,
              tone: PandoraStatusTone.informative,
              statusLabel: 'Submission does not equal execution',
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'What should Pandora accomplish?',
              subtitle:
                  'Use ordinary language. Raw prompts are never sent to product analytics.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey<String>('command-objective'),
                    controller: _objective,
                    readOnly: _outcomeUnknown,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'For example: Repair Pandora command connectivity and verify the Android owner journey.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.sm),
                  FilledButton.icon(
                    key: const ValueKey<String>('command-submit'),
                    onPressed: _submitting || _outcomeUnknown ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      _submitting ? 'Submitting safely…' : 'Submit to Pandora',
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.xs),
                  Text(
                    'Build Credits: not estimated · Runtime Credits: not estimated · Risk and rollback are resolved before protected execution.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Common outcomes',
              subtitle: 'Tap one to edit it before submission.',
              child: Wrap(
                spacing: PandoraSpacing.xs,
                runSpacing: PandoraSpacing.xs,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.north_east_rounded, size: 17),
                      label: Text(suggestion),
                      onPressed: _outcomeUnknown || _submitting
                          ? null
                          : () => _useSuggestion(suggestion),
                    ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            const _GovernedFlow(),
            const SizedBox(height: PandoraSpacing.md),
            const ExactSourceVerificationCard(),
            if (_error != null) ...[
              const SizedBox(height: PandoraSpacing.md),
              PandoraSurface(
                title: 'Command not completed',
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: context.pandoraPalette.attention,
                ),
                child: Text(_error!),
              ),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: PandoraSpacing.md),
              _CommandReceiptCard(receipt: _receipt!),
            ],
          ],
        ),
      );
}

class _GovernedFlow extends StatelessWidget {
  const _GovernedFlow();

  @override
  Widget build(BuildContext context) => PandoraSurface(
        title: 'Outcome loop',
        child: Column(
          children: const [
            _FlowStep(
              number: '1',
              title: 'Understand',
              message:
                  'Resolve the objective, project, baseline, risk, and expected result.',
            ),
            Divider(),
            _FlowStep(
              number: '2',
              title: 'Plan and execute',
              message:
                  'Show scope, proof, cost class, approvals, and reversible work before execution.',
            ),
            Divider(),
            _FlowStep(
              number: '3',
              title: 'Verify the working result',
              message:
                  'Report what changed, tests, artifact or deployment, remaining gaps, cost, and rollback.',
            ),
          ],
        ),
      );
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({
    required this.number,
    required this.title,
    required this.message,
  });

  final String number;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 16, child: Text(number)),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: PandoraSpacing.xxs),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CommandReceiptCard extends StatelessWidget {
  const _CommandReceiptCard({required this.receipt});

  final IntakeReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final status = receipt.status;
    return PandoraSurface(
      title: 'Request accepted',
      leading: Icon(
        Icons.check_circle_outline_rounded,
        color: context.pandoraPalette.verified,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(receipt.reply),
          const SizedBox(height: PandoraSpacing.sm),
          const Text(
            'Accepted means Pandora recorded the intent. It does not claim that execution, deployment, or production verification has happened.',
          ),
          const SizedBox(height: PandoraSpacing.md),
          StatusBadge(
            label: receipt.needsApproval
                ? 'Owner approval required before protected work'
                : 'Accepted for governed planning',
            tone: receipt.needsApproval
                ? PandoraStatusTone.attention
                : PandoraStatusTone.informative,
          ),
          const SizedBox(height: PandoraSpacing.md),
          _StatusLine(label: 'What changed', value: status.whatChanged),
          _StatusLine(label: 'Where we are', value: status.whereWeAre),
          _StatusLine(label: 'What is done', value: status.whatIsDone),
          _StatusLine(label: 'Happening now', value: status.whatIsHappeningNow),
          if (status.whatIsStoppingUs != null)
            _StatusLine(label: 'Blocked by', value: status.whatIsStoppingUs!),
          _StatusLine(label: 'Next', value: status.whatIWillDoNext),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: PandoraSpacing.xxs),
            Text(value),
          ],
        ),
      );
}
