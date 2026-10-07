import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';
import '../enterprise/plp_editorial_surfaces.dart';

/// Owner panel frame. Uses the PLP canvas and type, and does not add a menu.
/// The shell already exposes the single Open navigation control.
class PandoraBoxFrame extends StatelessWidget {
  const PandoraBoxFrame({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: plpCanvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
              child: Row(
                children: [
                  if (PandoraNavigationScope.maybeOf(context)?.openDrawer !=
                      null) ...[
                    PandoraMenuButton(
                      onPressed: PandoraNavigationScope.maybeOf(context)!
                          .openDrawer!,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plpInk,
                        fontFamily: 'serif',
                        fontSize: 16,
                        letterSpacing: 2.6,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: plpLine),
            Expanded(child: child),
          ],
        ),
      );
}
