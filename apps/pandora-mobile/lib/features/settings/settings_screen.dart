import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/security/pandora_auth.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/status_badge.dart';
import '../../pandora_config.dart';
import '../connections/connections_screen.dart';
import '../diagnostics/developer_diagnostics_screen.dart';
import '../intelligence/owner_intelligence_screen.dart';
import '../safety/safety_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.installedBuildLabel});

  final String? installedBuildLabel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    final dependencies = PandoraDependencies.of(context);
    try {
      dependencies.repository.clearReadOnlyCache();
      dependencies.diagnostics.clear();
      await dependencies.auth.signOut();
    } on PandoraAuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Settings',
        subtitle: 'Owner controls, trust surfaces, and diagnostics.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OwnerBriefingHero(
              eyebrow: 'Control center',
              title: 'Operate Pandora without exposing its machinery',
              message:
                  'Daily owner tools stay prominent. Raw diagnostics remain separate and sanitized.',
              icon: Icons.tune_rounded,
              tone: PandoraStatusTone.informative,
              statusLabel: 'Owner-only controls',
            ),
            const SizedBox(height: PandoraSpacing.md),
            OwnerSignal(
              label: 'Installed build',
              value: widget.installedBuildLabel ??
                  '${PandoraConfig.releaseLabel} · ${PandoraConfig.artifactClass} · Not a production release',
              icon: Icons.science_outlined,
              tone: PandoraStatusTone.informative,
            ),
            const SizedBox(height: PandoraSpacing.xl),
            const OwnerSectionHeading(
              title: 'Daily control',
              subtitle: 'Priorities, safe autonomy, and release readiness.',
            ),
            const SizedBox(height: PandoraSpacing.sm),
            _SettingsGroup(
              children: [
                _SettingsAction(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Portfolio intelligence',
                  subtitle: 'Priorities, recommendations, and Needs You',
                  onTap: () => _open(const OwnerIntelligenceScreen()),
                ),
                _SettingsAction(
                  icon: Icons.auto_mode_rounded,
                  title: 'Autopilot',
                  subtitle: 'Prepare or continue governed safe work',
                  onTap: () => _open(
                    const OwnerIntelligenceScreen(
                      initialSection: OwnerIntelligenceSection.autopilot,
                    ),
                  ),
                ),
                _SettingsAction(
                  icon: Icons.rocket_launch_outlined,
                  title: 'Release center',
                  subtitle: 'Proof ladder, blockers, and next release gates',
                  onTap: () => _open(
                    const OwnerIntelligenceScreen(
                      initialSection: OwnerIntelligenceSection.release,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PandoraSpacing.xl),
            const OwnerSectionHeading(
              title: 'Find and learn',
              subtitle: 'Search, notifications, and durable project truth.',
            ),
            const SizedBox(height: PandoraSpacing.sm),
            _SettingsGroup(
              children: [
                _SettingsAction(
                  icon: Icons.search_rounded,
                  title: 'Universal search',
                  subtitle: 'Projects, approvals, activity, connections',
                  onTap: () => _open(
                    const OwnerIntelligenceScreen(
                      initialSection: OwnerIntelligenceSection.search,
                    ),
                  ),
                ),
                _SettingsAction(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Owner-relevant attention inbox',
                  onTap: () => _open(
                    const OwnerIntelligenceScreen(
                      initialSection: OwnerIntelligenceSection.notifications,
                    ),
                  ),
                ),
                _SettingsAction(
                  icon: Icons.psychology_alt_outlined,
                  title: 'Memory & learning',
                  subtitle: 'Owner-readable truth and learning signals',
                  onTap: () => _open(
                    const OwnerIntelligenceScreen(
                      initialSection: OwnerIntelligenceSection.memory,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PandoraSpacing.xl),
            const OwnerSectionHeading(
              title: 'Trust and operations',
              subtitle: 'Provider capability, policy, and sanitized evidence.',
            ),
            const SizedBox(height: PandoraSpacing.sm),
            _SettingsGroup(
              children: [
                _SettingsAction(
                  icon: Icons.cable_rounded,
                  title: 'Connections',
                  subtitle: 'Readiness, scope, and provider capability',
                  onTap: () => _open(const ConnectionsScreen()),
                ),
                _SettingsAction(
                  icon: Icons.shield_outlined,
                  title: 'Safety',
                  subtitle: 'Policy, authorization, and evidence posture',
                  onTap: () => _open(const SafetyScreen()),
                ),
                _SettingsAction(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Developer diagnostics',
                  subtitle: 'Sanitized, temporary request metadata',
                  onTap: () => _open(const DeveloperDiagnosticsScreen()),
                ),
              ],
            ),
            const SizedBox(height: PandoraSpacing.xl),
            const OwnerSectionHeading(title: 'Account'),
            const SizedBox(height: PandoraSpacing.sm),
            OutlinedButton.icon(
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<_SettingsAction> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      );
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
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
        minVerticalPadding: PandoraSpacing.sm,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: PandoraRadius.controlBorder,
          ),
          child: Icon(icon, size: 21),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
