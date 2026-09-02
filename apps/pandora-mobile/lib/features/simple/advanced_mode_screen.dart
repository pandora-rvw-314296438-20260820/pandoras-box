import 'package:flutter/material.dart';

import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../activity/activity_screen.dart';
import '../diagnostics/developer_diagnostics_screen.dart';
import '../projects/projects_screen.dart';
import '../safety/safety_screen.dart';
import '../settings/settings_screen.dart';

class AdvancedModeScreen extends StatelessWidget {
  const AdvancedModeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Advanced Mode',
        subtitle:
            'Technical views over the same project, version, deployment, runtime, and evidence truth.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraSurface(
              title: 'Project truth',
              subtitle:
                  'Choose a project when technical detail is version- or entitlement-bound.',
              child: Column(
                children: [
                  _AdvancedTile(
                    icon: Icons.code_rounded,
                    title: 'Code',
                    subtitle:
                        'Open a project to inspect entitled source files for an exact version.',
                    onTap: () => _open(context, const ProjectsScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.difference_outlined,
                    title: 'Changes',
                    subtitle:
                        'Verified recent work and exact change history from the existing activity ledger.',
                    onTap: () => _open(context, const ActivityScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.storage_rounded,
                    title: 'Database',
                    subtitle:
                        'Technical database and provider diagnostics from the existing bounded diagnostics surface.',
                    onTap: () =>
                        _open(context, const DeveloperDiagnosticsScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.rocket_launch_outlined,
                    title: 'Deployments',
                    subtitle:
                        'Open a project to inspect deployment and publishing truth already bound to its versions.',
                    onTap: () => _open(context, const ProjectsScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.layers_outlined,
                    title: 'Versions',
                    subtitle:
                        'Open a project to review the existing version history and restore semantics.',
                    onTap: () => _open(context, const ProjectsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Operations',
              subtitle:
                  'Operational detail stays derived from the existing runtime and evidence sources.',
              child: Column(
                children: [
                  _AdvancedTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Jobs & Logs',
                    subtitle:
                        'Worker, runtime, and diagnostic detail from the existing bounded diagnostics surface.',
                    onTap: () =>
                        _open(context, const DeveloperDiagnosticsScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Evidence',
                    subtitle:
                        'Detailed verification, audit, and safety evidence from the existing trust surface.',
                    onTap: () => _open(context, const SafetyScreen()),
                  ),
                  _AdvancedTile(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Runtime',
                    subtitle:
                        'Current technical runtime diagnostics without creating a second runtime authority.',
                    onTap: () =>
                        _open(context, const DeveloperDiagnosticsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Account',
              child: _AdvancedTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle:
                    'Account, security, appearance, and application identity settings.',
                onTap: () => _open(context, const SettingsScreen()),
              ),
            ),
        ],
      ),
    );
}

class _AdvancedTile extends StatelessWidget {
  const _AdvancedTile({
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
