
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
      EnterpriseWorkspaceSection('Overview', 'enterprise_overview', 'overview',
          icon: Icons.dashboard_rounded),
      EnterpriseWorkspaceSection(
          'Matters & Cases', 'enterprise_workflows', 'matters-cases',
          icon: Icons.gavel_rounded),
      EnterpriseWorkspaceSection(
          'Clients & Contacts', 'enterprise_data', 'clients-contacts',
          icon: Icons.contacts_rounded),
      EnterpriseWorkspaceSection(
          'Documents & Drafts', 'enterprise_data', 'documents-drafts',
          icon: Icons.description_rounded),
      EnterpriseWorkspaceSection(
          'Calendar & Deadlines', 'enterprise_workflows', 'calendar-deadlines',
          icon: Icons.calendar_month_rounded),
      EnterpriseWorkspaceSection(
          'Billing & Finance', 'enterprise_analytics', 'billing-finance',
          icon: Icons.receipt_long_rounded),
      EnterpriseWorkspaceSection(
          'Research & Knowledge', 'enterprise_data', 'research-knowledge',
          icon: Icons.menu_book_rounded),
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

enum _WorkspaceAction { openHome, openOverview }

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
  State<EnterpriseWorkspaceHome> createState() =>
      _EnterpriseWorkspaceHomeState();
}

class _EnterpriseWorkspaceHomeState extends State<EnterpriseWorkspaceHome> {
  String? _expandedKey;

  void _toggle(EnterpriseWorkspaceProfile workspace) {
    setState(() {
      _expandedKey = _expandedKey == workspace.key ? null : workspace.key;
    });
  }

  void _open(
    EnterpriseWorkspaceProfile workspace,
    EnterpriseWorkspaceSection section,
  ) {
    widget.onOpen(
      EnterpriseWorkspaceSelection(workspace: workspace, section: section),
    );
  }

  @override
  Widget build(BuildContext context) {
    final openDrawer = PandoraNavigationScope.maybeOf(context)?.openDrawer;
    return Material(
      color: const Color(0xFF07111B),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF092039),
                  Color(0xFF07111B),
                  Color(0xFF15100D),
                ],
                stops: <double>[0, .56, 1],
              ),
            ),
          ),
          const Positioned(
            right: -120,
            bottom: 80,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x14B56E38),
                ),
                child: SizedBox(width: 360, height: 360),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: const ValueKey<String>('workspace-home-brand'),
                          onTap: openDrawer,
                          borderRadius: BorderRadius.circular(18),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PandoraMark(size: 48),
                              SizedBox(width: 14),
                              Text(
                                'Pandora',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.7,
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
                          onPressed: widget.onSearchChats,
                          icon: const Icon(Icons.search_rounded, size: 28),
                        ),
                      if (widget.onActivity != null)
                        IconButton(
                          key: const ValueKey<String>('workspace-home-activity'),
                          tooltip: 'Activity',
                          onPressed: widget.onActivity,
                          icon: const Icon(Icons.timelapse_rounded, size: 26),
                        ),
                      if (widget.onMore != null)
                        IconButton(
                          key: const ValueKey<String>('workspace-home-more'),
                          tooltip: 'More',
                          onPressed: widget.onMore,
                          icon: const Icon(Icons.more_vert_rounded, size: 27),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x33FFFFFF)),
                Expanded(
                  child: ListView.separated(
                    key: const ValueKey<String>('enterprise-workspace-list'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    itemCount: enterpriseWorkspaces.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final workspace = enterpriseWorkspaces[index];
                      return _WorkspaceCard(
                        workspace: workspace,
                        expanded: _expandedKey == workspace.key,
                        onToggle: () => _toggle(workspace),
                        onOpen: (section) => _open(workspace, section),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspace,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final EnterpriseWorkspaceProfile workspace;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<EnterpriseWorkspaceSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final home = workspace.sections.first;
    final overview = workspace.sections.length > 1
        ? workspace.sections[1]
        : workspace.sections.first;
    return Material(
      key: ValueKey<String>('workspace-card-' + workspace.key),
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
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 8, 13),
                child: Row(
                  children: [
                    _WorkspaceLogo(workspace: workspace),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workspace.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              height: 1.08,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            workspace.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB8B8BB),
                              fontSize: 15,
                              height: 1.12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey<String>(
                          'workspace-expand-' + workspace.key),
                      tooltip: expanded ? 'Collapse workspace' : 'Open workspace',
                      onPressed: onToggle,
                      icon: AnimatedRotation(
                        turns: expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    PopupMenuButton<_WorkspaceAction>(
                      key: ValueKey<String>(
                          'workspace-more-' + workspace.key),
                      tooltip: 'Workspace options',
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _WorkspaceAction.openHome:
                            onOpen(home);
                            break;
                          case _WorkspaceAction.openOverview:
                            onOpen(overview);
                            break;
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _WorkspaceAction.openHome,
                          child: Text('Open workspace'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceAction.openOverview,
                          child: Text('Open overview'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: expanded
                  ? Column(
                      children: [
                        const Divider(height: 1, color: Color(0x29FFFFFF)),
                        for (final section in workspace.sections)
                          ListTile(
                            key: ValueKey<String>(
                                workspace.key + '-' + section.routeSlug),
                            contentPadding:
                                const EdgeInsets.fromLTRB(20, 1, 14, 1),
                            leading: Icon(
                              section.icon,
                              color: const Color(0xFFD8D8DA),
                              size: 21,
                            ),
                            title: Text(
                              section.label,
                              style: const TextStyle(
                                color: Color(0xFFF0F0F2),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF8D8F93),
                              size: 14,
                            ),
                            onTap: () => onOpen(section),
                          ),
                        const SizedBox(height: 7),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
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
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0A111B),
          border: Border.all(color: workspace.accent, width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: workspace.accent.withValues(alpha: .16),
              blurRadius: 16,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            workspace.logoAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                workspace.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
}
