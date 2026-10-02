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
  });

  final Widget businessWorkspace;
  final Widget conversation;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: businessWorkspace),
          Positioned.fill(child: conversation),
        ],
      );
}
