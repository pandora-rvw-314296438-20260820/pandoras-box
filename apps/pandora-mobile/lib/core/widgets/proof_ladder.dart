import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../models/pandora_models.dart';

class ProofLadder extends StatelessWidget {
  const ProofLadder({super.key, required this.stages, this.compact = false});

  final List<EvidenceStageStatus> stages;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final known = <EvidenceStage, EvidenceClaimState>{
      for (final status in stages)
        if (status.stage != null) status.stage!: status.state,
    };
    final summary = EvidenceStage.values
        .map(
          (stage) =>
              '${stage.label}: ${(known[stage] ?? EvidenceClaimState.notChecked).label}',
        )
        .join('. ');
    return Semantics(
      label: 'Proof stages. $summary.',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: PandoraSpacing.xs,
          runSpacing: PandoraSpacing.xs,
          children: [
            for (final stage in EvidenceStage.values)
              _ProofStep(
                stage: stage,
                state: known[stage] ?? EvidenceClaimState.notChecked,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProofStep extends StatelessWidget {
  const _ProofStep({
    required this.stage,
    required this.state,
    required this.compact,
  });

  final EvidenceStage stage;
  final EvidenceClaimState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (state) {
      EvidenceClaimState.verified => (
          palette.verified,
          palette.onVerified,
          Icons.check_rounded,
        ),
      EvidenceClaimState.failed => (
          palette.critical,
          palette.onCritical,
          Icons.close_rounded,
        ),
      EvidenceClaimState.notChecked => (
          palette.subtleSurface,
          scheme.onSurfaceVariant,
          Icons.circle_outlined,
        ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? PandoraSpacing.xs : PandoraSpacing.sm,
        vertical: PandoraSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PandoraRadius.control),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: PandoraSpacing.xxs),
          Flexible(
            child: Text(
              stage.label,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
