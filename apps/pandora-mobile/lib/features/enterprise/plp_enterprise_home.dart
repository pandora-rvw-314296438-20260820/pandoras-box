import 'package:flutter/material.dart';

import 'plp_resort_workspace.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onRefresh,
    this.onOpenSection,
    this.onOpenModule,
    this.onOpenRecord,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onOpenSection;
  final ValueChanged<String>? onOpenModule;
  final void Function(String kind, Map<String, Object?> record)? onOpenRecord;

  @override
  Widget build(BuildContext context) => PlpResortWorkspaceScreen(
        key: const ValueKey('plp-enterprise-home'),
        section: plpResortSectionById('today')!,
        bootstrap: bootstrap,
        onOpenNavigation: onOpenNavigation ?? () {},
        onRefresh: onRefresh,
        onOpenSection: onOpenSection,
        onOpenModule: onOpenModule,
        onOpenRecord: onOpenRecord,
      );
}
