import 'package:flutter/material.dart';

/// Shared app-level composition seam for the business workspace and the single
/// persistent Pandora conversation. The conversation overlay owns only its
/// visible hit targets, so the business page stays interactive everywhere the
/// conversation is minimized.
class PandoraConversationLayer extends StatelessWidget {
  const PandoraConversationLayer({
    super.key,
    required this.businessWorkspace,
    required this.conversation,
    this.composerExtent,
  });

  /// Resting shell composer height before the device safe-area inset.
  /// Business surfaces reserve this exact vertical lane so their final controls
  /// can scroll fully above Pandora instead of rendering underneath it.
  static const double compactComposerHeight = 80;

  final Widget businessWorkspace;
  final Widget conversation;
  final double? composerExtent;

  @override
  Widget build(BuildContext context) {
    final safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;
    final measured = composerExtent;
    final businessBottomInset = measured != null && measured > 0
        ? measured
        : compactComposerHeight + safeAreaBottom;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Padding(
            key: const ValueKey<String>('pandora-business-composer-clearance'),
            padding: EdgeInsets.only(bottom: businessBottomInset),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: businessWorkspace,
            ),
          ),
        ),
        Positioned.fill(child: conversation),
      ],
    );
  }
}
