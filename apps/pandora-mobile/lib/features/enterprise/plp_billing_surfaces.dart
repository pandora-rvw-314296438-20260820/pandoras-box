import 'package:flutter/material.dart';

import 'plp_editorial_surfaces.dart';
import 'plp_line_icons.dart';

// The PLP billing entry line used on Revenue. The billing page itself is a
// Rooms-style tile page (see plp_paypal_billing_screen.dart) built from
// PlpPageTitle, PlpNoticeBox and PlpCapabilityGrid.

/// A thin-ruled tappable line (Revenue billing entry).
class PlpBillingRuledLine extends StatelessWidget {
  const PlpBillingRuledLine({
    super.key,
    required this.lead,
    this.rest = '',
    this.onTap,
    this.bottomRule = true,
    this.height = 56,
    this.leadSize = 15,
    this.restSize = 13,
    this.chevron,
    this.semanticsLabel,
  });

  final String lead;
  final String rest;
  final VoidCallback? onTap;
  final bool bottomRule;
  final double height;
  final double leadSize;
  final double restSize;

  /// Defaults to showing the chevron only when tappable.
  final bool? chevron;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: onTap != null,
        label: semanticsLabel ?? '$lead$rest',
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                border: Border(
                  top: const BorderSide(color: plpLine),
                  bottom: bottomRule
                      ? const BorderSide(color: plpLine)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: lead,
                        style: TextStyle(color: plpInk, fontSize: leadSize),
                        children: [
                          if (rest.isNotEmpty)
                            TextSpan(
                              text: rest,
                              style: TextStyle(
                                color: plpMuted,
                                fontSize: restSize,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (chevron ?? onTap != null)
                    PlpLineIcon(
                      PlpLineGlyph.chevronRight,
                      color: onTap != null ? plpInk : plpMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
