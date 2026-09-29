import 'package:flutter/material.dart';

import '../simple/ask_pandora_screen.dart';
import '../simple/pandora_v2_ui.dart';

class MarketingGrowthSection {
  const MarketingGrowthSection({
    required this.label,
    required this.slug,
    required this.surface,
    required this.icon,
  });

  final String label;
  final String slug;
  final String surface;
  final IconData icon;
}

const marketingGrowthSections = <MarketingGrowthSection>[
  MarketingGrowthSection(
    label: 'Overview',
    slug: 'overview',
    surface: 'growth_overview',
    icon: Icons.dashboard_rounded,
  ),
  MarketingGrowthSection(
    label: 'Campaigns',
    slug: 'campaigns',
    surface: 'growth_campaigns',
    icon: Icons.campaign_rounded,
  ),
  MarketingGrowthSection(
    label: 'Leads',
    slug: 'leads',
    surface: 'growth_leads',
    icon: Icons.people_alt_rounded,
  ),
  MarketingGrowthSection(
    label: 'Experiments',
    slug: 'experiments',
    surface: 'growth_experiments',
    icon: Icons.science_rounded,
  ),
  MarketingGrowthSection(
    label: 'Learning',
    slug: 'learning',
    surface: 'growth_learning',
    icon: Icons.psychology_alt_rounded,
  ),
  MarketingGrowthSection(
    label: 'Approvals',
    slug: 'approvals',
    surface: 'growth_approvals',
    icon: Icons.fact_check_rounded,
  ),
  MarketingGrowthSection(
    label: 'Activity',
    slug: 'activity',
    surface: 'growth_activity',
    icon: Icons.history_rounded,
  ),
  MarketingGrowthSection(
    label: 'Settings',
    slug: 'settings',
    surface: 'growth_settings',
    icon: Icons.settings_rounded,
  ),
];

Map<String, Object?> marketingGrowthEnterpriseContext(
  MarketingGrowthSection section,
) =>
    <String, Object?>{
      'surface': section.surface,
      'route': '/growth/${section.slug}',
      'capabilities': const <String>[],
      'identityScope': 'growth_workspace',
      'selectedObject': <String, String>{
        'workspaceKey': 'marketing-growth',
        'workspaceName': 'Marketing & Growth',
        'section': section.label,
        'sectionSlug': section.slug,
        'authority': 'read_only_until_explicit_approval',
      },
    };

class MarketingGrowthWorkspaceScreen extends StatefulWidget {
  const MarketingGrowthWorkspaceScreen({
    super.key,
    this.onHome,
    this.onSearchChats,
    this.onMore,
  });

  final VoidCallback? onHome;
  final VoidCallback? onSearchChats;
  final VoidCallback? onMore;

  @override
  State<MarketingGrowthWorkspaceScreen> createState() =>
      _MarketingGrowthWorkspaceScreenState();
}

class _MarketingGrowthWorkspaceScreenState
    extends State<MarketingGrowthWorkspaceScreen> {
  int _selectedIndex = 0;

  MarketingGrowthSection get _section =>
      marketingGrowthSections[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PandoraV2Colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF0B0D10),
                border: Border(
                  bottom: BorderSide(color: PandoraV2Colors.line),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (widget.onHome != null)
                          IconButton(
                            key: const ValueKey<String>(
                              'marketing-growth-home',
                            ),
                            tooltip: 'Home',
                            onPressed: widget.onHome,
                            icon: const Icon(Icons.home_outlined),
                          ),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Marketing & Growth',
                                key: ValueKey<String>(
                                  'marketing-growth-title',
                                ),
                                style: TextStyle(
                                  color: PandoraV2Colors.ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.35,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Verified measurement, experiments, learning and controlled actions',
                                style: TextStyle(
                                  color: PandoraV2Colors.muted,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.onSearchChats != null)
                          IconButton(
                            tooltip: 'Search chats',
                            onPressed: widget.onSearchChats,
                            icon: const Icon(Icons.search_rounded),
                          ),
                        if (widget.onMore != null)
                          IconButton(
                            tooltip: 'Settings & more',
                            onPressed: widget.onMore,
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        key: const ValueKey<String>(
                          'marketing-growth-section-nav',
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: marketingGrowthSections.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final section = marketingGrowthSections[index];
                          final selected = index == _selectedIndex;
                          return ChoiceChip(
                            key: ValueKey<String>(
                              'marketing-growth-section-${section.slug}',
                            ),
                            selected: selected,
                            showCheckmark: false,
                            avatar: Icon(section.icon, size: 17),
                            label: Text(section.label),
                            onSelected: (_) {
                              if (selected) return;
                              setState(() => _selectedIndex = index);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: PandoraV2Colors.muted,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${_section.label} • evidence-backed by default • writes require explicit approval',
                            key: const ValueKey<String>(
                              'marketing-growth-authority-note',
                            ),
                            style: const TextStyle(
                              color: PandoraV2Colors.muted,
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: AskPandoraScreen(
                onHome: widget.onHome,
                onSearchChats: widget.onSearchChats,
                onMore: widget.onMore,
                allowCharacterContext: false,
                allowProjectContext: false,
                enterpriseContext:
                    marketingGrowthEnterpriseContext(_section),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
