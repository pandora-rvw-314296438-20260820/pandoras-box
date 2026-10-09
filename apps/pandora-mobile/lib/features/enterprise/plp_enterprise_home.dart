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
    this.onOpenSourceSettings,
    this.lockedSections = const <String>{},
    this.unlockNotice,
    this.onUnlock,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onOpenSection;
  final ValueChanged<String>? onOpenModule;
  final void Function(String kind, Map<String, Object?> record)? onOpenRecord;
  final VoidCallback? onOpenSourceSettings;
  final Set<String> lockedSections;
  final String? unlockNotice;
  final VoidCallback? onUnlock;

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
        onOpenSourceSettings: onOpenSourceSettings,
        lockedSections: lockedSections,
        unlockNotice: unlockNotice,
        onUnlock: onUnlock,
      );
}
