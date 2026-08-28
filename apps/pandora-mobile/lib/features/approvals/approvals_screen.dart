import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/pandora_api_error.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/confirmation_sheet.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  ScreenController<List<ApprovalSummary>>? _controller;
  String? _decidingId;
  Timer? _expiryTimer;
  final Map<String, String> _decisionBlocks = <String, String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<ApprovalSummary>>(repository.approvals)
      ..addListener(_scheduleExpiryRefresh)
      ..load();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final expiries = (_controller?.data ?? const <ApprovalSummary>[])
        .map((approval) => approval.expiresAt)
        .whereType<DateTime>()
        .where((expiry) => expiry.isAfter(now))
        .toList(growable: false)
      ..sort();
    if (expiries.isEmpty) return;
    _expiryTimer = Timer(
      expiries.first.difference(now) + const Duration(milliseconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleExpiryRefresh();
      },
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _controller?.removeListener(_scheduleExpiryRefresh);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _decide(
    ApprovalSummary approval,
    ApprovalDecision decision,
  ) async {
    if (!approval.canDecideAt(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approval.decisionBlockReasonAt(DateTime.now()))),
      );
      await _controller?.refresh();
      return;
    }
    final isApprove = decision == ApprovalDecision.approve;
    final confirmed = await showPandoraConfirmation(
      context: context,
      title: isApprove ? 'Approve this plan?' : 'Reject this plan?',
      consequence: isApprove
          ? 'This records your approval. It does not execute the protected change.'
          : 'This records rejection and prevents this pending approval from continuing.',
      confirmLabel: isApprove ? 'Approve this plan' : 'Reject this plan',
      destructive: !isApprove,
    );
    if (confirmed != true || !mounted) return;
    if (!approval.canDecideAt(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That decision is no longer live. The queue will be refreshed.',
          ),
        ),
      );
      await _controller?.refresh();
      return;
    }
    setState(() => _decidingId = approval.id);
    try {
      final result = await PandoraDependencies.of(context)
          .repository
          .decideApproval(approvalId: approval.id, decision: decision);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.decision.toLowerCase().contains('approved')
                ? 'Approval recorded. Nothing was executed.'
                : 'Rejection recorded.',
          ),
        ),
      );
      await _controller?.refresh();
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      final isLocalDecisionDenial =
          error.code == 'APPROVAL_FORBIDDEN' || error.code == 'AAL2_REQUIRED';
      if (isLocalDecisionDenial) {
        setState(() {
          _decisionBlocks[approval.id] = error.code == 'AAL2_REQUIRED'
              ? 'Decision disabled — extra identity verification is required.'
              : 'Decision disabled — this owner cannot decide this approval.';
        });
      }
      final needsReconciliation = error.outcomeMayBeUnknown ||
          error.kind == PandoraApiErrorKind.conflict ||
          error.kind == PandoraApiErrorKind.notFound ||
          isLocalDecisionDenial;
      if (needsReconciliation) {
        await _controller?.refresh();
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needsReconciliation
                ? 'That approval may have changed. Pandora tried to refresh the queue; review its current state before deciding again.'
                : error.message,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _decidingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Approvals',
        subtitle:
            'Decide with target, risk, cost, proof, and recovery in view.',
        actions: [
          IconButton(
            tooltip: 'Refresh Approvals',
            onPressed: () => _controller?.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        onRefresh: () => _controller!.refresh(),
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, _) {
            final controller = _controller!;
            if (controller.isLoading && controller.data == null) {
              return const ContentSkeleton(lines: 6);
            }
            if (controller.error != null && controller.data == null) {
              return ErrorContent(
                title: 'Approvals could not load',
                message: _safeError(controller.error),
                onRetry: controller.load,
              );
            }
            final approvals = controller.data ?? const <ApprovalSummary>[];
            if (approvals.isEmpty) {
              return const OwnerBriefingHero(
                eyebrow: 'Approval queue',
                title: 'Nothing needs your decision',
                message:
                    'Pandora has no current owner approvals waiting. Protected work still remains governed.',
                icon: Icons.verified_user_outlined,
                tone: PandoraStatusTone.verified,
                statusLabel: 'Queue clear',
              );
            }
            final highRisk = approvals
                .where(
                  (approval) =>
                      approval.risk == ActionRisk.high ||
                      approval.risk == ActionRisk.critical,
                )
                .length;
            final reversible =
                approvals.where((approval) => approval.reversible).length;
            final expiringSoon = approvals.where(_expiresSoon).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OwnerBriefingHero(
                  eyebrow: 'Needs you',
                  title:
                      '${approvals.length} decision${approvals.length == 1 ? '' : 's'} waiting',
                  message:
                      'Approval records your decision. Execution remains a separate governed step.',
                  icon: Icons.approval_outlined,
                  tone: PandoraStatusTone.attention,
                  statusLabel: 'Approval never means execution',
                ),
                const SizedBox(height: PandoraSpacing.md),
                OwnerMetricGrid(
                  metrics: [
                    OwnerMetric(
                      label: 'High risk',
                      value: '$highRisk',
                      icon: Icons.warning_amber_rounded,
                      tone: highRisk > 0
                          ? PandoraStatusTone.critical
                          : PandoraStatusTone.neutral,
                    ),
                    OwnerMetric(
                      label: 'Reversible',
                      value: '$reversible',
                      icon: Icons.undo_rounded,
                      tone: PandoraStatusTone.verified,
                    ),
                    OwnerMetric(
                      label: 'Expiring soon',
                      value: '$expiringSoon',
                      icon: Icons.timer_outlined,
                      tone: expiringSoon > 0
                          ? PandoraStatusTone.attention
                          : PandoraStatusTone.neutral,
                    ),
                  ],
                ),
                if (controller.error != null) ...[
                  const SizedBox(height: PandoraSpacing.md),
                  ErrorContent(
                    title: 'Live approval state could not be revalidated',
                    message: controller.error!.message,
                    onRetry: controller.refresh,
                  ),
                ],
                const SizedBox(height: PandoraSpacing.xl),
                const OwnerSectionHeading(
                  title: 'Decision queue',
                  subtitle:
                      'Review the consequence and recovery before acting.',
                ),
                const SizedBox(height: PandoraSpacing.sm),
                for (var index = 0; index < approvals.length; index++) ...[
                  _ApprovalCard(
                    approval: approvals[index],
                    busy: _decidingId == approvals[index].id,
                    enabled: controller.error == null && !controller.isLoading,
                    decisionDisabledReason:
                        _decisionBlocks[approvals[index].id],
                    onApprove: () =>
                        _decide(approvals[index], ApprovalDecision.approve),
                    onReject: () =>
                        _decide(approvals[index], ApprovalDecision.reject),
                  ),
                  if (index != approvals.length - 1)
                    const SizedBox(height: PandoraSpacing.md),
                ],
              ],
            );
          },
        ),
      );
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.busy,
    required this.enabled,
    required this.decisionDisabledReason,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalSummary approval;
  final bool busy;
  final bool enabled;
  final String? decisionDisabledReason;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canDecide = approval.canDecideAt(now);
    final blockReason = decisionDisabledReason ??
        (canDecide ? '' : approval.decisionBlockReasonAt(now));
    final decisionEnabled = enabled && decisionDisabledReason == null;
    return PandoraSurface(
      title: approval.action,
      subtitle: approval.reason,
      trailing: StatusBadge(
        label: approval.risk.label,
        tone: statusToneFor(approval.risk.label),
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: PandoraSpacing.xs,
            runSpacing: PandoraSpacing.xs,
            children: [
              if (approval.projectId != null)
                StatusBadge(
                  label: approval.projectId!,
                  tone: PandoraStatusTone.informative,
                  compact: true,
                ),
              StatusBadge(
                label: 'Environment not verified',
                tone: PandoraStatusTone.attention,
                compact: true,
              ),
              StatusBadge(
                label: 'Cost impact not verified',
                tone: PandoraStatusTone.attention,
                compact: true,
              ),
              StatusBadge(
                label: approval.reversible
                    ? 'Recovery recorded'
                    : 'Recovery not verified',
                tone: approval.reversible
                    ? PandoraStatusTone.verified
                    : PandoraStatusTone.critical,
                compact: true,
              ),
              StatusBadge(
                label: approval.expiresAt == null
                    ? 'Expiry not verified'
                    : 'Expires ${ownerRelativeTime(approval.expiresAt)}',
                tone: approval.expiresAt == null || _expiresSoon(approval)
                    ? PandoraStatusTone.attention
                    : PandoraStatusTone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
          OwnerSignal(
            label: 'What changes',
            value: approval.change,
            icon: Icons.change_circle_outlined,
            tone: PandoraStatusTone.informative,
          ),
          const SizedBox(height: PandoraSpacing.xs),
          OwnerSignal(
            label: 'Recovery',
            value: approval.reversible
                ? approval.rollback ?? 'A recovery path is recorded.'
                : 'No verified recovery path is recorded.',
            icon: Icons.undo_rounded,
            tone: approval.reversible
                ? PandoraStatusTone.verified
                : PandoraStatusTone.critical,
          ),
          if (blockReason.isNotEmpty) ...[
            const SizedBox(height: PandoraSpacing.md),
            StatusBadge(label: blockReason, tone: PandoraStatusTone.critical),
          ],
          const SizedBox(height: PandoraSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showApprovalDetails(context, approval),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View details'),
            ),
          ),
          const SizedBox(height: PandoraSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final approve = FilledButton.icon(
                onPressed:
                    busy || !decisionEnabled || !canDecide ? null : onApprove,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Approve'),
              );
              final reject = OutlinedButton.icon(
                onPressed:
                    busy || !decisionEnabled || !canDecide ? null : onReject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject'),
              );
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    approve,
                    const SizedBox(height: PandoraSpacing.xs),
                    reject,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: approve),
                  const SizedBox(width: PandoraSpacing.xs),
                  Expanded(child: reject),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _showApprovalDetails(BuildContext context, ApprovalSummary approval) async {
  final safeChange = _sanitizeApprovalText(approval.change);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(approval.action, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: PandoraSpacing.sm),
          Text(approval.reason),
          const SizedBox(height: PandoraSpacing.lg),
          OwnerSignal(label: 'Risk', value: approval.risk.label, icon: Icons.warning_amber_rounded, tone: statusToneFor(approval.risk.label)),
          const SizedBox(height: PandoraSpacing.xs),
          OwnerSignal(label: 'Reversibility', value: approval.reversible ? 'Undo available' : 'Undo not verified', icon: Icons.undo_rounded, tone: approval.reversible ? PandoraStatusTone.verified : PandoraStatusTone.critical),
          const SizedBox(height: PandoraSpacing.xs),
          OwnerSignal(label: 'Rollback', value: approval.rollback ?? 'No verified rollback path is recorded.', icon: Icons.restore_rounded, tone: approval.rollback != null ? PandoraStatusTone.verified : PandoraStatusTone.critical),
          const SizedBox(height: PandoraSpacing.lg),
          Text('Sanitized change summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: PandoraSpacing.xs),
          SelectableText(safeChange),
          const SizedBox(height: PandoraSpacing.lg),
          const StatusBadge(label: 'Environment proof: not verified', tone: PandoraStatusTone.attention),
          const SizedBox(height: PandoraSpacing.xs),
          const StatusBadge(label: 'Cost proof: not verified', tone: PandoraStatusTone.attention),
          const SizedBox(height: PandoraSpacing.xs),
          StatusBadge(label: approval.expiresAt == null ? 'Expiry proof: not verified' : 'Expiry recorded', tone: approval.expiresAt == null ? PandoraStatusTone.attention : PandoraStatusTone.neutral),
        ]),
      ),
    ),
  );
}

String _sanitizeApprovalText(String input) {
  var value = input;
  value = value.replaceAll(RegExp(r'(token|secret|password|api[_ -]?key)\s*[:=]\s*[^\s,;]+', caseSensitive: false), r'$1=[redacted]');
  value = value.replaceAll(RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|sb_secret_[A-Za-z0-9_]{20,})\b'), '[redacted]');
  return value;
}

bool _expiresSoon(ApprovalSummary approval) {
  final expiresAt = approval.expiresAt;
  if (expiresAt == null) return true;
  final remaining = expiresAt.difference(DateTime.now());
  return !remaining.isNegative && remaining <= const Duration(hours: 24);
}

String _safeError(Object? error) {
  if (error is PandoraRepositoryException) return error.message;
  return 'Pandora could not verify the approval queue. Try again.';
}
