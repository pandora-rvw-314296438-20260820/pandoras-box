import 'package:flutter/material.dart';

import '../enterprise/plp_editorial_surfaces.dart';
import '../../core/widgets/pandora_navigation.dart';

/// Owner-panel frame. Uses the existing PLP header and canvas.
/// Does not change PLP widgets.
class PandoraBoxFrame extends StatelessWidget {
  const PandoraBoxFrame({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: plpCanvas,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: PandoraNavigationScope(
                openDrawer: null,
                child: PlpEditorialHeader(
                  title: title,
                  onOpenNavigation: () {},
                ),
              ),
            ),
            const Divider(height: 1, color: plpLine),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
