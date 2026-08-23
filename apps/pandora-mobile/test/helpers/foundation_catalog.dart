import 'package:flutter/material.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/widgets/content_state.dart';
import 'package:pandora_mobile/core/widgets/freshness_label.dart';
import 'package:pandora_mobile/core/widgets/pandora_mark.dart';
import 'package:pandora_mobile/core/widgets/pandora_surface.dart';
import 'package:pandora_mobile/core/widgets/proof_ladder.dart';
import 'package:pandora_mobile/core/widgets/status_badge.dart';

class FoundationCatalog extends StatelessWidget {
  const FoundationCatalog({super.key});

  static const stages = <EvidenceStageStatus>[
    EvidenceStageStatus(
      stage: EvidenceStage.documented,
      state: EvidenceClaimState.verified,
      rawStage: 'documented',
      rawState: 'verified',
    ),
    EvidenceStageStatus(
      stage: EvidenceStage.implemented,
      state: EvidenceClaimState.verified,
      rawStage: 'implemented',
      rawState: 'verified',
    ),
    EvidenceStageStatus(
      stage: EvidenceStage.tested,
      state: EvidenceClaimState.failed,
      rawStage: 'tested',
      rawState: 'failed',
    ),
    EvidenceStageStatus(
      stage: EvidenceStage.deployed,
      state: EvidenceClaimState.notChecked,
      rawStage: 'deployed',
      rawState: 'not_checked',
    ),
    EvidenceStageStatus(
      stage: EvidenceStage.productionVerified,
      state: EvidenceClaimState.notChecked,
      rawStage: 'productionVerified',
      rawState: 'not_checked',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Foundation'),
          actions: [
            IconButton(
              tooltip: 'Refresh foundation',
              onPressed: () {},
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PandoraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: PandoraMark(size: 72)),
                const SizedBox(height: PandoraSpacing.md),
                PandoraSurface(
                  title: 'Owner briefing',
                  subtitle:
                      'Plain language, verified state, one safe next step.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Wrap(
                        spacing: PandoraSpacing.xs,
                        runSpacing: PandoraSpacing.xs,
                        children: [
                          StatusBadge(
                            label: 'Protected',
                            tone: PandoraStatusTone.verified,
                          ),
                          StatusBadge(
                            label: 'Needs attention',
                            tone: PandoraStatusTone.attention,
                          ),
                          StatusBadge(
                            label: 'Blocked',
                            tone: PandoraStatusTone.critical,
                          ),
                        ],
                      ),
                      const SizedBox(height: PandoraSpacing.md),
                      const ProofLadder(stages: stages),
                      const SizedBox(height: PandoraSpacing.md),
                      FreshnessLabel(
                        freshness: FreshnessInfo(
                          state: FreshnessState.fresh,
                          lastVerifiedAt: DateTime.utc(2026, 8, 14),
                        ),
                        now: DateTime.utc(2026, 8, 14, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PandoraSpacing.md),
                ErrorContent(
                  title: 'Could not refresh',
                  message: 'Your last verified information is still visible.',
                  onRetry: () {},
                ),
              ],
            ),
          ),
        ),
      );
}
