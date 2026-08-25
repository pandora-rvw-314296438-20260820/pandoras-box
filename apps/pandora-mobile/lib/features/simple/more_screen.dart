import 'package:flutter/material.dart';

import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/pandora_mark.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../activity/activity_screen.dart';
import '../command/command_screen.dart';
import '../connections/connections_screen.dart';
import '../diagnostics/developer_diagnostics_screen.dart';
import '../home/home_screen.dart';
import '../intelligence/owner_intelligence_screen.dart';
import '../projects/projects_screen.dart';
import '../safety/safety_screen.dart';
import '../settings/settings_screen.dart';

void _openMore(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'More',
        subtitle:
            'Business intelligence, history, safety, and professional tools.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ModeCard(),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Business & history',
              child: Column(
                children: [
                  _MoreTile(
                    icon: Icons.query_stats_outlined,
                    title: 'Business',
                    subtitle: 'Signals, recommendations, and owner intelligence',
                    onTap: () =>
                        _openMore(context, const OwnerIntelligenceScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.history_rounded,
                    title: 'Activity',
                    subtitle: 'Verified recent work and results',
                    onTap: () => _openMore(context, const ActivityScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.shield_outlined,
                    title: 'Verify & Safety',
                    subtitle: 'Evidence, audit integrity, and protected controls',
                    onTap: () => _openMore(context, const SafetyScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Professional mode',
              subtitle:
                  'Technical details stay here until you intentionally open them.',
              child: Column(
                children: [
                  _MoreTile(
                    icon: Icons.workspaces_outline,
                    title: 'Projects',
                    subtitle: 'Detailed phases, tasks, and evidence',
                    onTap: () => _openMore(context, const ProjectsScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.cable_outlined,
                    title: 'Connections',
                    subtitle: 'Provider scopes and connection state',
                    onTap: () => _openMore(context, const ConnectionsScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.terminal_rounded,
                    title: 'Governed command',
                    subtitle: 'Advanced ProjectOS request surface',
                    onTap: () => _openMore(context, const CommandScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.dashboard_customize_outlined,
                    title: 'Classic owner dashboard',
                    subtitle: 'The detailed operational owner view',
                    onTap: () => _openMore(context, const HomeScreen()),
                  ),
                  _MoreTile(
                    icon: Icons.developer_mode_outlined,
                    title: 'Developer diagnostics',
                    subtitle: 'Bounded technical diagnostics',
                    onTap: () => _openMore(
                      context,
                      const DeveloperDiagnosticsScreen(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Account',
              child: _MoreTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Appearance, account, security, and app identity',
                onTap: () => _openMore(context, const SettingsScreen()),
              ),
            ),
          ],
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) => PandoraSurface(
        child: Row(
          children: [
            const PandoraMark(size: 44),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Simple Mode',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: PandoraSpacing.xxs),
                  Text(
                    'Business outcomes first. Technical complexity stays behind Pandora.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
