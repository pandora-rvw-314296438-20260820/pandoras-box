import 'package:flutter/material.dart';

import '../../core/data/pandora_user_admin_api.dart';
import '../activity/activity_screen.dart';
import '../connections/connections_screen.dart';
import '../intelligence/owner_intelligence_screen.dart';
import '../settings/settings_screen.dart';
import '../team/team_screen.dart';
import 'advanced_mode_screen.dart';
import 'domains_screen.dart';
import 'pandora_simple_ui.dart';
import 'simple_safety_screen.dart';

void _openMore(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, this.teamGateway});

  final PandoraUserAdminGateway? teamGateway;

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: const PandoraOwnerHeader(
          title: 'More',
          subtitle:
              'A few useful places. Everything else stays out of the way.',
          leadingMark: false,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('Essentials'),
            const SizedBox(height: 8),
            PandoraSimpleCard(
              shadow: false,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _MoreTile(
                    icon: Icons.language_rounded,
                    title: 'Domains',
                    subtitle: 'Addresses and publishing status',
                    onTap: () => _openMore(context, const DomainsScreen()),
                  ),
                  const _TileDivider(),
                  _MoreTile(
                    icon: Icons.query_stats_rounded,
                    title: 'Business',
                    subtitle: 'Useful signals and recommendations',
                    onTap: () =>
                        _openMore(context, const OwnerIntelligenceScreen()),
                  ),
                  const _TileDivider(),
                  _MoreTile(
                    icon: Icons.history_rounded,
                    title: 'Activity',
                    subtitle: 'What Pandora actually did',
                    onTap: () => _openMore(context, const ActivityScreen()),
                  ),
                  const _TileDivider(),
                  _MoreTile(
                    icon: Icons.cable_rounded,
                    title: 'Connections',
                    subtitle: 'Connected services and their health',
                    onTap: () => _openMore(context, const ConnectionsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const _SectionLabel('People & safety'),
            const SizedBox(height: 8),
            PandoraSimpleCard(
              shadow: false,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _MoreTile(
                    icon: Icons.groups_rounded,
                    title: 'Team',
                    subtitle: 'People who can work with you',
                    onTap: () =>
                        _openMore(context, TeamScreen(gateway: teamGateway)),
                  ),
                  const _TileDivider(),
                  _MoreTile(
                    icon: Icons.shield_rounded,
                    title: 'Safety',
                    subtitle: 'Only the protection details you need',
                    onTap: () => _openMore(context, const SimpleSafetyScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const _SectionLabel('When you need more'),
            const SizedBox(height: 8),
            PandoraSimpleCard(
              shadow: false,
              padding: EdgeInsets.zero,
              child: _MoreTile(
                icon: Icons.tune_rounded,
                title: 'Professional tools',
                subtitle: 'Code, versions, runtime, evidence and diagnostics',
                onTap: () => _openMore(context, const AdvancedModeScreen()),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: () => _openMore(context, const SettingsScreen()),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Settings'),
                style: TextButton.styleFrom(
                  foregroundColor: PandoraSimpleColors.muted,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: PandoraSimpleColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      );
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 68, color: PandoraSimpleColors.line);
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
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        leading: PandoraIconBadge(icon: icon, size: 40),
        title: Text(
          title,
          style: const TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: pandoraSimpleMutedText,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: PandoraSimpleColors.muted,
          size: 15,
        ),
        onTap: onTap,
      );
}
