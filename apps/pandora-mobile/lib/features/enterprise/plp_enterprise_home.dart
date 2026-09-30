import 'package:flutter/material.dart';

import 'plp_resort_workspace.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onRefresh,
    required this.onAskAlfred,
    this.onOpenSection,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final VoidCallback onAskAlfred;
  final ValueChanged<String>? onOpenSection;

  @override
  Widget build(BuildContext context) => PlpResortWorkspaceScreen(
        key: const ValueKey('plp-enterprise-home'),
        section: plpResortSectionById('today')!,
        bootstrap: bootstrap,
        onOpenNavigation: onOpenNavigation ?? () {},
        onRefresh: onRefresh,
        onAskPandora: (_) => onAskAlfred(),
        onOpenSection: onOpenSection,
      );
}
