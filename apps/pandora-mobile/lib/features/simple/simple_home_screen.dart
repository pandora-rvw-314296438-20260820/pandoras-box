import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../approvals/approvals_screen.dart';
import '../projects/project_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'domains_screen.dart';
import 'pandora_simple_ui.dart';
import 'project_create_experience.dart';
import 'projects_screen.dart';

void _openHome(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({
    super.key,
    this.onAskPandora,
    this.onOpenSystems,
    this.onOpenNeedsYou,
    this.onOpenMore,
  });

  final ValueChanged<String>? onAskPandora;
  final VoidCallback? onOpenSystems;
  final VoidCallback? onOpenNeedsYou;
  final VoidCallback? onOpenMore;

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  HomeSummary? _summary;
  bool _loading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = PandoraDependencies.of(context).repository;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await repository.home();
      if (!mounted) return;
      setState(() {
        _summary = snapshot.data;
        _loading = false;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora could not verify the current business state.';
      });
    }
  }

  void _openProjects() {
    if (widget.onOpenSystems != null) {
      widget.onOpenSystems!();
      return;
    }
    _openHome(context, const ProjectsScreen());
  }

  void _openNeedsYou() {
    if (widget.onOpenNeedsYou != null) {
      widget.onOpenNeedsYou!();
      return;
    }
    _openHome(context, const ApprovalsScreen());
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
    onRefresh: _load,
    header: PandoraOwnerHeader(
      title: 'Good morning, Mark',
      subtitle: "Here's your business today.",
      onNotifications: _openNeedsYou,
      onAvatar: () => _openHome(context, const SettingsScreen()),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StartProjectCard(
          onTap: () =>
              _openHome(context, const CreateProjectExperienceScreen()),
        ),
        const SizedBox(height: 22),
        if (_loading)
          const PandoraSimpleCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: CircularProgressIndicator(
                  color: PandoraSimpleColors.red,
                ),
              ),
            ),
          )
        else if (_error != null)
          PandoraEmptyTruth(
            title: 'Current state unavailable',
            message: _error!,
            actionLabel: 'Check again',
            onAction: _load,
          )
        else
          _CleanHome(
            summary: _summary!,
            onOpenProjects: _openProjects,
            onOpenNeedsYou: _openNeedsYou,
            onOpenDomains: () => _openHome(context, const DomainsScreen()),
          ),
      ],
    ),
  );
}

class _StartProjectCard extends StatelessWidget {
  const _StartProjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
    onTap: onTap,
    padding: const EdgeInsets.all(20),
    backgroundColor: const Color(0xFFFFF8F9),
    borderColor: const Color(0xFFF1D9DE),
    child: Row(
      children: [
        const PandoraIconBadge(icon: Icons.auto_awesome_rounded, size: 58),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start a new project',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.25,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Tell Pandora what you want to build.',
                style: pandoraSimpleMutedText,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Icon(
          Icons.arrow_forward_rounded,
          color: PandoraSimpleColors.red,
          size: 26,
        ),
      ],
    ),
  );
}

class _CleanHome extends StatelessWidget {
  const _CleanHome({
    required this.summary,
    required this.onOpenProjects,
    required this.onOpenNeedsYou,
    required this.onOpenDomains,
  });

  final HomeSummary summary;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenNeedsYou;
  final VoidCallback onOpenDomains;

  @override
  Widget build(BuildContext context) {
    DomainSummary? liveDomain;
    for (final domain in summary.domains) {
      if (domain.isLive) {
        liveDomain = domain;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PandoraSectionTitle(
          title: 'Projects',
          actionLabel: 'View all',
          onAction: onOpenProjects,
        ),
        _ProjectsHomeCard(
          projects: summary.topProjects,
          onOpenProjects: onOpenProjects,
        ),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'Domains',
          actionLabel: 'View all',
          onAction: onOpenDomains,
        ),
        _DomainsHomeCard(
          domains: summary.domains,
          onOpenDomains: onOpenDomains,
        ),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'Needs You',
          meta: summary.countersVerified ? '· ${summary.approvalCount}' : '· —',
          actionLabel: 'View all',
          onAction: onOpenNeedsYou,
        ),
        _NeedsYouHomeCard(summary: summary, onTap: onOpenNeedsYou),
        const SizedBox(height: 22),
        const PandoraSectionTitle(title: 'Live'),
        _LiveHomeCard(domain: liveDomain, onOpenDomains: onOpenDomains),
      ],
    );
  }
}

class _ProjectsHomeCard extends StatelessWidget {
  const _ProjectsHomeCard({
    required this.projects,
    required this.onOpenProjects,
  });

  final List<ProjectSummary> projects;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return PandoraSimpleCard(
        shadow: false,
        onTap: onOpenProjects,
        child: const Row(
          children: [
            PandoraIconBadge(icon: Icons.folder_outlined, size: 48),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Pandora has not confirmed any current work yet. Your projects will appear here after you create one.',
                style: pandoraSimpleMutedText,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 17,
              color: PandoraSimpleColors.muted,
            ),
          ],
        ),
      );
    }

    final project = projects.first;
    final state = _projectOwnerState(project.status);
    final live = state == 'Live';
    return PandoraSimpleCard(
      shadow: false,
      onTap: () => _openHome(context, ProjectDetailScreen(project: project)),
      child: Row(
        children: [
          const PandoraIconBadge(icon: Icons.storefront_outlined, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _homeProjectSummary(project),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: pandoraSimpleMutedText,
                ),
                const SizedBox(height: 8),
                PandoraStatusPill(
                  label: state,
                  icon: live ? Icons.circle : null,
                  foreground: live
                      ? PandoraSimpleColors.green
                      : PandoraSimpleColors.deepRed,
                  background: live
                      ? PandoraSimpleColors.greenWash
                      : PandoraSimpleColors.blush,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 17,
            color: PandoraSimpleColors.muted,
          ),
        ],
      ),
    );
  }
}

class _DomainsHomeCard extends StatelessWidget {
  const _DomainsHomeCard({required this.domains, required this.onOpenDomains});

  final List<DomainSummary> domains;
  final VoidCallback onOpenDomains;

  @override
  Widget build(BuildContext context) {
    if (domains.isEmpty) {
      return PandoraSimpleCard(
        shadow: false,
        onTap: onOpenDomains,
        child: const Row(
          children: [
            PandoraIconBadge(icon: Icons.language_rounded, size: 48),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Give your project its own address',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Get or connect a domain.',
                    style: pandoraSimpleMutedText,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.add_circle_outline_rounded,
              color: PandoraSimpleColors.red,
            ),
          ],
        ),
      );
    }

    final domain = domains.first;
    return PandoraSimpleCard(
      shadow: false,
      onTap: onOpenDomains,
      child: Row(
        children: [
          PandoraIconBadge(
            icon: Icons.public_rounded,
            size: 50,
            foreground: domain.isLive
                ? PandoraSimpleColors.green
                : PandoraSimpleColors.red,
            background: domain.isLive
                ? PandoraSimpleColors.greenWash
                : PandoraSimpleColors.blush,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain.domain,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(domain.projectName, style: pandoraSimpleMutedText),
                const SizedBox(height: 8),
                PandoraStatusPill(
                  label: domain.statusLabel,
                  icon: domain.isLive ? Icons.circle : null,
                  foreground: domain.isLive
                      ? PandoraSimpleColors.green
                      : PandoraSimpleColors.deepRed,
                  background: domain.isLive
                      ? PandoraSimpleColors.greenWash
                      : PandoraSimpleColors.blush,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 17,
            color: PandoraSimpleColors.muted,
          ),
        ],
      ),
    );
  }
}

class _NeedsYouHomeCard extends StatelessWidget {
  const _NeedsYouHomeCard({required this.summary, required this.onTap});

  final HomeSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDecisions = summary.countersVerified && summary.approvalCount > 0;
    return PandoraSimpleCard(
      shadow: false,
      onTap: onTap,
      child: Row(
        children: [
          const PandoraIconBadge(icon: Icons.fact_check_outlined, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.priority?.action ??
                      (hasDecisions
                          ? '${summary.approvalCount} decision${summary.approvalCount == 1 ? '' : 's'} ready for review'
                          : 'Nothing needs your decision right now'),
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  summary.priority?.reason ??
                      (summary.countersVerified
                          ? 'Pandora will surface the next decision here.'
                          : 'Pandora has not confirmed how many decisions need you yet.'),
                  style: pandoraSimpleMutedText,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 17,
            color: PandoraSimpleColors.muted,
          ),
        ],
      ),
    );
  }
}

class _LiveHomeCard extends StatelessWidget {
  const _LiveHomeCard({required this.domain, required this.onOpenDomains});

  final DomainSummary? domain;
  final VoidCallback onOpenDomains;

  @override
  Widget build(BuildContext context) {
    final current = domain;
    if (current == null) {
      return PandoraSimpleCard(
        shadow: false,
        onTap: onOpenDomains,
        child: const Row(
          children: [
            PandoraIconBadge(icon: Icons.public_off_outlined, size: 48),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Nothing is published on a verified domain yet.',
                style: pandoraSimpleMutedText,
              ),
            ),
          ],
        ),
      );
    }

    return PandoraSimpleCard(
      shadow: false,
      onTap: onOpenDomains,
      child: Row(
        children: [
          const PandoraIconBadge(
            icon: Icons.public_rounded,
            size: 50,
            foreground: PandoraSimpleColors.green,
            background: PandoraSimpleColors.greenWash,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.projectName,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(current.domain, style: pandoraSimpleMutedText),
              ],
            ),
          ),
          const PandoraStatusPill(label: 'Live', icon: Icons.circle),
        ],
      ),
    );
  }
}

String _homeProjectSummary(ProjectSummary project) {
  var summary = project.purpose
      .replaceAll(RegExp(r'^\s*[-#>*+]+\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (summary.isEmpty ||
      summary.toLowerCase().contains('if you cannot directly inspect') ||
      summary.toLowerCase().contains('implementation instructions')) {
    return '${project.name} project';
  }

  final sentenceEnd = summary.indexOf('.');
  if (sentenceEnd > 0) summary = summary.substring(0, sentenceEnd + 1);
  if (summary.length <= 180) return summary;

  final clipped = summary.substring(0, 180);
  final lastSpace = clipped.lastIndexOf(' ');
  final safeEnd = lastSpace >= 120 ? lastSpace : 180;
  return '${clipped.substring(0, safeEnd).trimRight()}…';
}

String _projectOwnerState(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('live')) return 'Live';
  if (normalized.contains('block') || normalized.contains('attention')) {
    return 'Needs You';
  }
  if (normalized.contains('ready')) return 'Ready';
  if (normalized.contains('active') ||
      normalized.contains('progress') ||
      normalized.contains('working')) {
    return 'Working';
  }
  return status.isEmpty ? 'Not verified' : status;
}
