import 'package:flutter/material.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../activity/activity_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _isProfessionalMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PandoraPage(
      title: 'More',
      subtitle: 'Manage connections, business memory, and professional telemetry.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Professional Mode Toggle
          _buildProfessionalToggle(context),
          const SizedBox(height: PandoraSpacing.md),

          // Sections
          _buildMenuSection(
            context,
            title: 'System & Intelligence',
            items: [
              _MenuItem(
                icon: Icons.history_rounded,
                title: 'Activity Timeline',
                subtitle: 'See what changed, who acted, and what was verified.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ActivityScreen(),
                    ),
                  );
                },
              ),
              _MenuItem(
                icon: Icons.psychology_outlined,
                title: 'Memory & Learning',
                subtitle: 'View and manage what Pandora knows about your business.',
                onTap: () {
                  _showFeatureNotImplemented(context, 'Memory & Learning');
                },
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),

          _buildMenuSection(
            context,
            title: 'Integrations & Connections',
            items: [
              _MenuItem(
                icon: Icons.cable_rounded,
                title: 'My Connections',
                subtitle: 'Manage Facebook, Payments, SMS, and accounting tools.',
                onTap: () {
                  _showFeatureNotImplemented(context, 'My Connections');
                },
              ),
              _MenuItem(
                icon: Icons.storefront_outlined,
                title: 'Connector Marketplace',
                subtitle: 'Browse and connect new capabilities to your systems.',
                onTap: () {
                  _showFeatureNotImplemented(context, 'Connector Marketplace');
                },
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),

          _buildMenuSection(
            context,
            title: 'Organization',
            items: [
              _MenuItem(
                icon: Icons.people_outline_rounded,
                title: 'Team & Members',
                subtitle: 'Manage who has access and control role policies.',
                onTap: () {
                  _showFeatureNotImplemented(context, 'Team & Members');
                },
              ),
              _MenuItem(
                icon: Icons.credit_card_outlined,
                title: 'Billing & Subscriptions',
                subtitle: 'Track your Build Credits and Runtime Credits usage.',
                onTap: () {
                  _showFeatureNotImplemented(context, 'Billing & Subscriptions');
                },
              ),
            ],
          ),

          if (_isProfessionalMode) ...[
            const SizedBox(height: PandoraSpacing.md),
            _buildMenuSection(
              context,
              title: 'Professional Telemetry',
              isAccent: true,
              items: [
                _MenuItem(
                  icon: Icons.code_rounded,
                  title: 'Source Control & Repositories',
                  subtitle: 'Inspect commit histories, branches, and deploy logs.',
                  onTap: () {
                    _showFeatureNotImplemented(context, 'Source Control & Repos');
                  },
                ),
                _MenuItem(
                  icon: Icons.key_rounded,
                  title: 'APIs & Environment Variables',
                  subtitle: 'Securely manage access credentials, keys, and settings.',
                  onTap: () {
                    _showFeatureNotImplemented(context, 'APIs & Environment Variables');
                  },
                ),
                _MenuItem(
                  icon: Icons.analytics_outlined,
                  title: 'Developer Diagnostics',
                  subtitle: 'Explore request logs, timings, and routing policies.',
                  onTap: () {
                    _showFeatureNotImplemented(context, 'Developer Diagnostics');
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: PandoraSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildProfessionalToggle(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.md, vertical: PandoraSpacing.sm),
        child: Row(
          children: [
            Icon(
              _isProfessionalMode ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
              color: _isProfessionalMode ? const Color(0xFFC72E25) : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Professional Mode',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _isProfessionalMode
                        ? 'Exposing source, database state, and diagnostics.'
                        : 'Default simplified view for business owners.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isProfessionalMode,
              activeColor: const Color(0xFFC72E25),
              onChanged: (val) {
                setState(() {
                  _isProfessionalMode = val;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(
    BuildContext context, {
    required String title,
    required List<_MenuItem> items,
    bool isAccent = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.xs, vertical: PandoraSpacing.xxs),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: isAccent ? const Color(0xFFC72E25) : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: PandoraSpacing.xxs),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildListTile(context, items[i]),
                if (i < items.length - 1)
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(BuildContext context, _MenuItem item) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(PandoraSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(PandoraSpacing.xs),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: const Color(0xFFC72E25), size: 20),
            ),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PandoraSpacing.xs),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFeatureNotImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature view will be initialized as part of Phase 2.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
