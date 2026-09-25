
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/pandora_mark.dart';
import '../../core/widgets/pandora_navigation.dart';

class EnterpriseWorkspaceSection {
  const EnterpriseWorkspaceSection(
    this.label,
    this.surface,
    this.routeSlug, {
    this.icon = Icons.chevron_right_rounded,
  });

  final String label;
  final String surface;
  final String routeSlug;
  final IconData icon;
}

class EnterpriseWorkspaceProfile {
  const EnterpriseWorkspaceProfile({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.initials,
    required this.icon,
    required this.logoAsset,
    required this.accent,
    required this.sections,
  });

  final String key;
  final String name;
  final String subtitle;
  final String initials;
  final IconData icon;
  final String logoAsset;
  final Color accent;
  final List<EnterpriseWorkspaceSection> sections;
}

class EnterpriseWorkspaceSelection {
  const EnterpriseWorkspaceSelection({
    required this.workspace,
    required this.section,
  });

  final EnterpriseWorkspaceProfile workspace;
  final EnterpriseWorkspaceSection section;

  Map<String, Object?> get enterpriseContext => <String, Object?>{
        'surface': section.surface,
        'route': '/enterprise/workspaces/' +
            workspace.key +
            '/' +
            section.routeSlug,
        'capabilities': const <String>[],
        'identityScope': 'enterprise_workspace',
        'selectedObject': <String, String>{
          'workspaceKey': workspace.key,
          'workspaceName': workspace.name,
          'workspaceType': workspace.subtitle,
          'section': section.label,
        },
      };
}

const enterpriseWorkspaces = <EnterpriseWorkspaceProfile>[
  EnterpriseWorkspaceProfile(
    key: 'plp-boracay',
    name: 'PLP Boracay',
    subtitle: 'Luxury Resort',
    initials: 'PLP',
    icon: Icons.hotel_rounded,
    logoAsset: 'assets/workspaces/plp.webp',
    accent: Color(0xFFD5A16E),
    sections: <EnterpriseWorkspaceSection>[
      EnterpriseWorkspaceSection('Home', 'enterprise_overview', 'home',
          icon: Icons.home_rounded),
      EnterpriseWorkspaceSection('Overview', 'enterprise_overview', 'overview',
          icon: Icons.dashboard_rounded),
      EnterpriseWorkspaceSection(
          'Tax & Compliance', 'enterprise_tax', 'tax-compliance',
          icon: Icons.account_balance_rounded),
      EnterpriseWorkspaceSection(
          'Operations', 'enterprise_workflows', 'operations',
          icon: Icons.event_note_rounded),
      EnterpriseWorkspaceSection('Guests', 'enterprise_data', 'guests',
          icon: Icons.people_alt_rounded),
      EnterpriseWorkspaceSection(
          'Sales & Revenue', 'enterprise_analytics', 'sales-revenue',
          icon: Icons.payments_rounded),
      EnterpriseWorkspaceSection(
          'Team & Access', 'enterprise_security', 'team-access',
          icon: Icons.group_rounded),
      EnterpriseWorkspaceSection(
          'Needs You', 'enterprise_workflows', 'needs-you',
          icon: Icons.priority_high_rounded),
      EnterpriseWorkspaceSection('Activity', 'enterprise_logs', 'activity',
          icon: Icons.history_rounded),
      EnterpriseWorkspaceSection('Settings', 'enterprise_settings', 'settings',
          icon: Icons.settings_rounded),
      EnterpriseWorkspaceSection(
          'System / Developer', 'enterprise_code', 'system-developer',
          icon: Icons.code_rounded),
    ],
  ),
  EnterpriseWorkspaceProfile(
    key: '1064-euro-fish-traders',
    name: '1064 euro-fish traders',
    subtitle: 'Import/Export',
    initials: '1064',
    icon: Icons.set_meal_rounded,
    logoAsset: 'assets/workspaces/eurofish.webp',
    accent: Color(0xFF6AA9FF),
    sections: <EnterpriseWorkspaceSection>[
      EnterpriseWorkspaceSection('Home', 'enterprise_overview', 'home',
          icon: Icons.home_rounded),
      EnterpriseWorkspaceSection('Overview', 'enterprise_overview', 'overview',
          icon: Icons.dashboard_rounded),
      EnterpriseWorkspaceSection(
          'Tax & Compliance', 'enterprise_tax', 'tax-compliance',
          icon: Icons.account_balance_rounded),
      EnterpriseWorkspaceSection(
          'Orders & Shipments', 'enterprise_workflows', 'orders-shipments',
          icon: Icons.inventory_2_rounded),
      EnterpriseWorkspaceSection(
          'Suppliers & Buyers', 'enterprise_data', 'suppliers-buyers',
          icon: Icons.handshake_rounded),
      EnterpriseWorkspaceSection(
          'Inventory & Products', 'enterprise_data', 'inventory-products',
          icon: Icons.inventory_rounded),
      EnterpriseWorkspaceSection(
          'Logistics & Customs', 'enterprise_workflows', 'logistics-customs',
          icon: Icons.local_shipping_rounded),
      EnterpriseWorkspaceSection(
          'Sales & Finance', 'enterprise_analytics', 'sales-finance',
          icon: Icons.payments_rounded),
      EnterpriseWorkspaceSection(
          'Documents & Compliance', 'enterprise_security', 'documents-compliance',
          icon: Icons.fact_check_rounded),
      EnterpriseWorkspaceSection(
          'Team & Access', 'enterprise_security', 'team-access',
          icon: Icons.group_rounded),
      EnterpriseWorkspaceSection('Activity', 'enterprise_logs', 'activity',
          icon: Icons.history_rounded),
      EnterpriseWorkspaceSection('Settings', 'enterprise_settings', 'settings',
          icon: Icons.settings_rounded),
      EnterpriseWorkspaceSection(
          'System / Developer', 'enterprise_code', 'system-developer',
          icon: Icons.code_rounded),
    ],
  ),

  EnterpriseWorkspaceProfile(
    key: 'batalla-associates',
    name: 'Batalla & Associates',
    subtitle: 'Law & Business Offices',
    initials: 'B&A',
    icon: Icons.balance_rounded,
    logoAsset: 'assets/workspaces/batalla.webp',
    accent: Color(0xFFD5A24F),
    sections: <EnterpriseWorkspaceSection>[
      EnterpriseWorkspaceSection('Home', 'enterprise_overview', 'home',
          icon: Icons.home_rounded),
      EnterpriseWorkspaceSection('Today', 'enterprise_overview', 'today',
          icon: Icons.today_rounded),
      EnterpriseWorkspaceSection(
          'Tax & Compliance', 'enterprise_tax', 'tax-compliance',
          icon: Icons.account_balance_rounded),
      EnterpriseWorkspaceSection('Matters', 'enterprise_data', 'matters',
          icon: Icons.gavel_rounded),
      EnterpriseWorkspaceSection(
          'Clients & Intake', 'enterprise_workflows', 'clients-intake',
          icon: Icons.person_add_alt_1_rounded),
      EnterpriseWorkspaceSection(
          'Hearings & Calendar', 'enterprise_workflows', 'hearings-calendar',
          icon: Icons.calendar_month_rounded),
      EnterpriseWorkspaceSection(
          'Reviews & Decisions', 'enterprise_workflows', 'reviews-decisions',
          icon: Icons.fact_check_rounded),
      EnterpriseWorkspaceSection(
          'Documents & Evidence', 'enterprise_data', 'documents-evidence',
          icon: Icons.description_rounded),
      EnterpriseWorkspaceSection(
          'Paper Files', 'enterprise_data', 'paper-files',
          icon: Icons.folder_copy_rounded),
      EnterpriseWorkspaceSection(
          'Scan & File', 'enterprise_workflows', 'scan-file',
          icon: Icons.document_scanner_rounded),
      EnterpriseWorkspaceSection(
          'Calls & Communications', 'enterprise_workflows',
          'calls-communications',
          icon: Icons.call_rounded),
      EnterpriseWorkspaceSection(
          'Print Center', 'enterprise_workflows', 'print-center',
          icon: Icons.print_rounded),
      EnterpriseWorkspaceSection(
          'Billing & Finance', 'enterprise_analytics', 'billing-finance',
          icon: Icons.receipt_long_rounded),
      EnterpriseWorkspaceSection(
          'Reports', 'enterprise_analytics', 'reports',
          icon: Icons.assessment_rounded),
      EnterpriseWorkspaceSection(
          'Team & Access', 'enterprise_security', 'team-access',
          icon: Icons.group_rounded),
      EnterpriseWorkspaceSection(
          'Activity & Audit', 'enterprise_logs', 'activity-audit',
          icon: Icons.history_rounded),
      EnterpriseWorkspaceSection(
          'Settings', 'enterprise_settings', 'settings',
          icon: Icons.settings_rounded),
      EnterpriseWorkspaceSection(
          'System / Developer', 'enterprise_code', 'system-developer',
          icon: Icons.code_rounded),
    ],
  ),
  EnterpriseWorkspaceProfile(
    key: 'bok',
    name: 'BOK',
    subtitle: 'Food & Hospitality Group',
    initials: 'BOK',
    icon: Icons.restaurant_rounded,
    logoAsset: 'assets/workspaces/bok.webp',
    accent: Color(0xFFD1B874),
    sections: <EnterpriseWorkspaceSection>[
      EnterpriseWorkspaceSection('Home', 'enterprise_overview', 'home',
          icon: Icons.home_rounded),
      EnterpriseWorkspaceSection('Overview', 'enterprise_overview', 'overview',
          icon: Icons.dashboard_rounded),
      EnterpriseWorkspaceSection(
          'Tax & Compliance', 'enterprise_tax', 'tax-compliance',
          icon: Icons.account_balance_rounded),
      EnterpriseWorkspaceSection(
          'Restaurants & Branches', 'enterprise_data', 'restaurants-branches',
          icon: Icons.storefront_rounded),
      EnterpriseWorkspaceSection(
          'Orders & Bookings', 'enterprise_workflows', 'orders-bookings',
          icon: Icons.receipt_rounded),
      EnterpriseWorkspaceSection(
          'Menus & Availability', 'enterprise_data', 'menus-availability',
          icon: Icons.restaurant_menu_rounded),
      EnterpriseWorkspaceSection(
          'Delivery & Logistics', 'enterprise_workflows', 'delivery-logistics',
          icon: Icons.delivery_dining_rounded),
      EnterpriseWorkspaceSection(
          'Customers & Promotions', 'enterprise_marketing', 'customers-promotions',
          icon: Icons.campaign_rounded),
      EnterpriseWorkspaceSection(
          'Sales & Finance', 'enterprise_analytics', 'sales-finance',
          icon: Icons.payments_rounded),
      EnterpriseWorkspaceSection(
          'Team & Access', 'enterprise_security', 'team-access',
          icon: Icons.group_rounded),
      EnterpriseWorkspaceSection('Activity', 'enterprise_logs', 'activity',
          icon: Icons.history_rounded),
      EnterpriseWorkspaceSection('Settings', 'enterprise_settings', 'settings',
          icon: Icons.settings_rounded),
      EnterpriseWorkspaceSection(
          'System / Developer', 'enterprise_code', 'system-developer',
          icon: Icons.code_rounded),
    ],
  ),
];

enum _WorkspaceAction { openHome, showSections }
enum _HomeAction { activity, more }

class EnterpriseWorkspaceHome extends StatefulWidget {
  const EnterpriseWorkspaceHome({
    super.key,
    required this.onOpen,
    this.onSearchChats,
    this.onActivity,
    this.onMore,
  });

  final ValueChanged<EnterpriseWorkspaceSelection> onOpen;
  final VoidCallback? onSearchChats;
  final VoidCallback? onActivity;
  final VoidCallback? onMore;

  @override
  State<EnterpriseWorkspaceHome> createState() => _EnterpriseWorkspaceHomeState();
}

class _EnterpriseWorkspaceHomeState extends State<EnterpriseWorkspaceHome> {
  String? _expandedKey;
  int _expansionGeneration = 0;
  final _scrollController = ScrollController();
  final _headerKeys = <String, GlobalKey>{
    for (final workspace in enterpriseWorkspaces) workspace.key: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle(EnterpriseWorkspaceProfile workspace) {
    FocusManager.instance.primaryFocus?.unfocus();
    final generation = ++_expansionGeneration;
    setState(() {
      _expandedKey = _expandedKey == workspace.key ? null : workspace.key;
    });
    // Reveal the selected header after the accordion's new geometry is laid
    // out. Keep all four headers mounted so a collapse above cannot lose the
    // target in a lazily recycled list. No guessed animation-delay timer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _expansionGeneration) return;
      final headerContext = _headerKeys[workspace.key]?.currentContext;
      if (headerContext == null) return;
      unawaited(Scrollable.ensureVisible(
        headerContext,
        alignment: 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ));
    });
  }

  void _open(EnterpriseWorkspaceProfile workspace, EnterpriseWorkspaceSection section) {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onOpen(EnterpriseWorkspaceSelection(workspace: workspace, section: section));
  }

  Widget _header(BuildContext context, VoidCallback? openDrawer) {
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxWidth >= 480 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.4;
      return Padding(
        key: const ValueKey<String>('workspace-home-header'),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            if (openDrawer != null)
              PandoraMenuButton(
                key: const ValueKey<String>('workspace-home-navigation'),
                onPressed: openDrawer,
              ),
            Expanded(
              child: InkWell(
                key: const ValueKey<String>('workspace-home-brand'),
                onTap: openDrawer,
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  children: [
                    PandoraMark(size: roomy ? 40 : 32),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Pandora',
                          key: ValueKey<String>('workspace-home-title'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onSearchChats != null)
              IconButton(
                key: const ValueKey<String>('workspace-home-search'),
                tooltip: 'Search chats',
                color: Colors.white,
                onPressed: widget.onSearchChats,
                icon: const Icon(Icons.search_rounded, size: 24),
              ),
            if (roomy && widget.onActivity != null)
              IconButton(
                key: const ValueKey<String>('workspace-home-activity'),
                tooltip: 'Activity',
                color: Colors.white,
                onPressed: widget.onActivity,
                icon: const Icon(Icons.timelapse_rounded, size: 24),
              ),
            if (roomy && widget.onMore != null)
              IconButton(
                key: const ValueKey<String>('workspace-home-more'),
                tooltip: 'Settings & More',
                color: Colors.white,
                onPressed: widget.onMore,
                icon: const Icon(Icons.more_vert_rounded, size: 24),
              )
            else if (!roomy && (widget.onActivity != null || widget.onMore != null))
              PopupMenuButton<_HomeAction>(
                key: const ValueKey<String>('workspace-home-more'),
                tooltip: 'Activity and settings',
                color: const Color(0xFF171C22),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                onSelected: (action) {
                  switch (action) {
                    case _HomeAction.activity:
                      widget.onActivity?.call();
                      break;
                    case _HomeAction.more:
                      widget.onMore?.call();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (widget.onActivity != null)
                    const PopupMenuItem(
                      value: _HomeAction.activity,
                      child: Text('Activity', style: TextStyle(color: Colors.white)),
                    ),
                  if (widget.onMore != null)
                    const PopupMenuItem(
                      value: _HomeAction.more,
                      child: Text('Settings & More', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final openDrawer = PandoraNavigationScope.maybeOf(context)?.openDrawer;
    return Material(
      color: const Color(0xFF07111B),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF092039), Color(0xFF07111B), Color(0xFF15100D)],
            stops: [0, .56, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, openDrawer),
              const Divider(height: 1, color: Color(0x33FFFFFF)),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey<String>('enterprise-workspace-list'),
                  controller: _scrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  child: Column(
                    children: [
                      for (final workspace in enterpriseWorkspaces)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WorkspaceCard(
                            key: ValueKey<String>('workspace-card-' + workspace.key),
                            headerKey: _headerKeys[workspace.key]!,
                            workspace: workspace,
                            expanded: _expandedKey == workspace.key,
                            onToggle: () => _toggle(workspace),
                            onOpen: (section) => _open(workspace, section),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    super.key,
    required this.headerKey,
    required this.workspace,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final GlobalKey headerKey;
  final EnterpriseWorkspaceProfile workspace;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<EnterpriseWorkspaceSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final home = workspace.sections.first;
    final tax = workspace.sections.firstWhere((section) => section.routeSlug == 'tax-compliance');
    return Material(
      color: const Color(0xC90B0E12),
      borderRadius: BorderRadius.circular(25),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0x29FFFFFF)),
        ),
        child: Column(
          children: [
            Row(
              key: headerKey,
              children: [
                Expanded(
                  child: Semantics(
                    expanded: expanded,
                    child: InkWell(
                      key: ValueKey<String>('workspace-expand-' + workspace.key),
                      onTap: onToggle,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                        child: Row(
                          children: [
                            _WorkspaceLogo(workspace: workspace),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(workspace.name, style: const TextStyle(
                                    color: Colors.white, fontSize: 18, height: 1.18,
                                    fontWeight: FontWeight.w700, letterSpacing: -.25,
                                  )),
                                  const SizedBox(height: 4),
                                  Text(workspace.subtitle, style: const TextStyle(
                                    color: Color(0xFFB8B8BB), fontSize: 14, height: 1.2,
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                color: Colors.white, size: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<_WorkspaceAction>(
                  key: ValueKey<String>('workspace-more-' + workspace.key),
                  tooltip: 'Workspace options',
                  color: const Color(0xFF171C22),
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (action) {
                    switch (action) {
                      case _WorkspaceAction.openHome:
                        onOpen(home);
                        break;
                      case _WorkspaceAction.showSections:
                        onToggle();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: _WorkspaceAction.openHome,
                        child: Text('Open workspace', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(value: _WorkspaceAction.showSections,
                        child: Text(expanded ? 'Hide sections' : 'Show sections',
                            style: const TextStyle(color: Colors.white))),
                  ],
                ),
              ],
            ),
            // This directory is not a tenant-scoped metrics surface. Do not
            // repeat one organization-wide readiness result across businesses.
            if (!expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Material(
                  color: const Color(0x14D5A16E),
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    key: ValueKey<String>('workspace-tax-quick-' + workspace.key),
                    minLeadingWidth: 22,
                    horizontalTitleGap: 10,
                    leading: Icon(Icons.account_balance_rounded, color: workspace.accent, size: 22),
                    title: const Text('Tax & Compliance', style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700,
                    )),
                    trailing: const Icon(Icons.arrow_forward_rounded, color: Color(0xFFD8D8DA), size: 20),
                    onTap: () => onOpen(tax),
                  ),
                ),
              ),
            if (expanded) ...[
              const Divider(height: 1, color: Color(0x29FFFFFF)),
              for (final section in workspace.sections)
                ListTile(
                  key: ValueKey<String>(workspace.key + '-' + section.routeSlug),
                  contentPadding: const EdgeInsets.fromLTRB(20, 4, 14, 4),
                  minLeadingWidth: 24,
                  horizontalTitleGap: 12,
                  leading: Icon(section.icon, color: const Color(0xFFD8D8DA), size: 21),
                  title: Text(section.label, style: const TextStyle(
                    color: Color(0xFFF0F0F2), fontSize: 15, fontWeight: FontWeight.w600,
                  )),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF8D8F93), size: 14),
                  onTap: () => onOpen(section),
                ),
              const SizedBox(height: 7),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceLogo extends StatelessWidget {
  const _WorkspaceLogo({required this.workspace});
  final EnterpriseWorkspaceProfile workspace;

  @override
  Widget build(BuildContext context) => Container(
    width: 48, height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF0A111B),
      border: Border.all(color: workspace.accent, width: 1.4),
    ),
    child: ClipOval(
      child: Image.asset(
        workspace.logoAsset,
        fit: BoxFit.cover,
        cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context)).ceil(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Center(child: Text(workspace.initials,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
      ),
    ),
  );
}
