import 'package:flutter/material.dart';

import '../pandora_v2_ui.dart';
import 'live_build_code_view.dart';
import 'live_build_file_activity.dart';
import 'live_build_reducer.dart';

class LiveBuildTheatre extends StatelessWidget {
  const LiveBuildTheatre({
    super.key,
    required this.state,
    this.onFollowChanged,
  });

  final LiveBuildTheatreState state;
  final ValueChanged<bool>? onFollowChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface,
        border: Border.all(color: PandoraV2Colors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _iconFor(state.stage),
                size: 19,
                color: PandoraV2Colors.ink,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  state.statusLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (state.historyGapDueToRetention) ...[
            const SizedBox(height: 8),
            const Text(
              'Build continued while you were away.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (state.hasVisibleRealSource) ...[
            const SizedBox(height: 14),
            LiveBuildCodeView(
              state: state,
              onFollowChanged: onFollowChanged,
            ),
          ],
          if (state.files.isNotEmpty) ...[
            const SizedBox(height: 12),
            LiveBuildFileActivity(state: state),
          ],
        ],
      ),
    );
  }
}

IconData _iconFor(LiveBuildStage stage) {
  switch (stage) {
    case LiveBuildStage.problem:
      return Icons.error_outline_rounded;
    case LiveBuildStage.needsYou:
      return Icons.priority_high_rounded;
    case LiveBuildStage.previewReady:
    case LiveBuildStage.completed:
    case LiveBuildStage.sourceReady:
      return Icons.check_circle_outline_rounded;
    case LiveBuildStage.checking:
      return Icons.fact_check_outlined;
    case LiveBuildStage.correcting:
      return Icons.build_outlined;
    case LiveBuildStage.starting:
    case LiveBuildStage.writing:
    case LiveBuildStage.building:
      return Icons.code_rounded;
  }
}
