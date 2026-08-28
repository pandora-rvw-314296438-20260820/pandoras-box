import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../activity/activity_screen.dart';
import '../approvals/approvals_screen.dart';
import '../projects/project_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'ask_pandora_screen.dart';
import 'pandora_simple_ui.dart';
import 'systems_screen.dart';

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
  final TextEditingController _intent = TextEditingController();
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

  @override
  void dispose() {
    _intent.dispose();
    super.dispose();
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

  void _ask([String? suggested]) {
    final prompt = (suggested ?? _intent.text).trim();
    if (widget.onAskPandora != null) {
      widget.onAskPandora!(prompt);
      return;
    }
    _openHome(
      context,
      AskPandoraScreen(initialPrompt: prompt.isEmpty ? null : prompt),
    );
  }

  void _openSystems() {
    if (widget.onOpenSystems != null) {
      widget.onOpenSystems!();
    } else {
      _openHome(context, const SystemsScreen());
    }
  }

  void _openNeedsYou() {
    if (widget.onOpenNeedsYou != null) {
      widget.onOpenNeedsYou!();
    } else {
      _openHome(context, const ApprovalsScreen());
    }
  }

  void _showRecommendationSource(String message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PandoraSimpleColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why Pandora recommends this',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(message, style: pandoraSimpleText),
              const SizedBox(height: 18),
              PandoraPrimaryButton(
                label: 'Ask Pandora to handle it',
                onPressed: () {
                  Navigator.of(context).pop();
                  _ask(message);
                },
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
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
            _IntentCard(
                controller: _intent, onSubmit: _ask, onSuggestion: _ask),
            const SizedBox(height: 20),
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
              _VerifiedHome(
                summary: _summary!,
                onAsk: _ask,
                onOpenSystems: _openSystems,
                onOpenNeedsYou: _openNeedsYou,
                onOpenActivity: () =>
                    _openHome(context, const ActivityScreen()),
                onExplainRecommendation: _showRecommendationSource,
              ),
          ],
        ),
      );
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.controller,
    required this.onSubmit,
    required this.onSuggestion,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const PandoraIconBadge(
                    icon: Icons.auto_awesome_rounded, size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    decoration: const InputDecoration(
                      hintText: 'What do you want Pandora to do?',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Speak to Pandora',
                  onPressed: () => onSuggestion(controller.text),
                  icon: const Icon(Icons.mic_none_rounded),
                  color: PandoraSimpleColors.ink,
                ),
                IconButton(
                  tooltip: 'Attach context',
                  onPressed: () => onSuggestion(controller.text),
                  icon: const Icon(Icons.attach_file_rounded),
                  color: PandoraSimpleColors.ink,
                ),
                IconButton(
                  tooltip: 'Send to Pandora',
                  onPressed: onSubmit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  color: PandoraSimpleColors.red,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final suggestions = <(IconData, String)>[
                  (
                    Icons.calendar_month_outlined,
                    'Build an online booking system'
                  ),
                  (
                    Icons.person_add_alt_1_outlined,
                    'Automate customer follow-ups'
                  ),
                  (Icons.trending_up_rounded, 'Improve my website'),
                ];
                if (constraints.maxWidth < 570) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final suggestion in suggestions)
                        _SuggestionChip(
                          icon: suggestion.$1,
                          label: suggestion.$2,
                          onTap: () => onSuggestion(suggestion.$2),
                        ),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0;
                        index < suggestions.length;
                        index++) ...[
                      Expanded(
                        child: _SuggestionChip(
                          icon: suggestions[index].$1,
                          label: suggestions[index].$2,
                          onTap: () => onSuggestion(suggestions[index].$2),
                        ),
                      ),
                      if (index != suggestions.length - 1)
                        const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PandoraSimpleColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: PandoraSimpleColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: PandoraSimpleColors.deepRed, size: 21),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _VerifiedHome extends StatelessWidget {
  const _VerifiedHome({
    required this.summary,
    required this.onAsk,
    required this.onOpenSystems,
    required this.onOpenNeedsYou,
    required this.onOpenActivity,
    required this.onExplainRecommendation,
  });

  final HomeSummary summary;
  final ValueChanged<String> onAsk;
  final VoidCallback onOpenSystems;
  final VoidCallback onOpenNeedsYou;
  final VoidCallback onOpenActivity;
  final ValueChanged<String> onExplainRecommendation;

  @override
  Widget build(BuildContext context) {
    final recommendation = summary.priority?.reason ??
        (summary.topProjects.isNotEmpty
            ? summary.topProjects.first.nextAction
            : null);
    final attentionProject = summary.topProjects.where(
      (project) => project.blocker != null || project.nextAction != null,
    );
    final attention = attentionProject.isEmpty ? null : attentionProject.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PandoraSectionTitle(
          title: 'Needs You',
          meta: summary.countersVerified ? '· ${summary.approvalCount}' : '· —',
          actionLabel: 'View all',
          onAction: onOpenNeedsYou,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = <Widget>[
              _NeedCard(
                icon: Icons.fact_check_outlined,
                title: summary.priority?.action ??
                    (summary.countersVerified && summary.approvalCount > 0
                        ? '${summary.approvalCount} decision${summary.approvalCount == 1 ? '' : 's'} ready for review'
                        : 'Nothing needs your decision right now'),
                detail: summary.priority?.reason ??
                    (summary.countersVerified
                        ? 'Pandora will surface the next decision here.'
                        : 'Decision counters have not been verified.'),
                action: summary.approvalCount > 0 ? 'Review' : 'Open',
                onTap: onOpenNeedsYou,
              ),
              _NeedCard(
                icon: attention == null
                    ? Icons.verified_user_outlined
                    : Icons.hub_outlined,
                iconForeground: attention == null
                    ? PandoraSimpleColors.green
                    : PandoraSimpleColors.blue,
                iconBackground: attention == null
                    ? PandoraSimpleColors.greenWash
                    : PandoraSimpleColors.blueWash,
                title: attention?.name ?? 'No additional issue is verified',
                detail: attention?.blocker ??
                    attention?.nextAction ??
                    'Pandora is monitoring your connected systems.',
                action: attention == null ? 'Systems' : 'Open',
                onTap: attention == null
                    ? onOpenSystems
                    : () => _openHome(
                          context,
                          ProjectDetailScreen(project: attention),
                        ),
              ),
            ];
            if (constraints.maxWidth < 620) {
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            }
            // IntrinsicHeight bounds equal-height cards when parent height is unbounded (scroll views).
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'Pandora is working',
          live: true,
          actionLabel: 'View all',
          onAction: onOpenSystems,
        ),
        _WorkingCard(summary: summary),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'Business Pulse',
          actionLabel: 'View dashboard',
          onAction: onOpenSystems,
        ),
        _BusinessPulse(summary: summary),
        const SizedBox(height: 22),
        const PandoraSectionTitle(title: 'Pandora Recommends'),
        _RecommendationCard(
          recommendation: recommendation,
          onAsk: onAsk,
          onExplain: onExplainRecommendation,
        ),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'My Systems',
          actionLabel: 'See all systems →',
          onAction: onOpenSystems,
        ),
        _SystemsStrip(summary: summary, onOpenSystems: onOpenSystems),
        const SizedBox(height: 22),
        PandoraSectionTitle(
          title: 'Recent activity',
          actionLabel: 'View all',
          onAction: onOpenActivity,
        ),
        _ActivityCard(summary: summary, onOpenActivity: onOpenActivity),
      ],
    );
  }
}

class _NeedCard extends StatelessWidget {
  const _NeedCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
    this.iconForeground = PandoraSimpleColors.red,
    this.iconBackground = PandoraSimpleColors.blush,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;
  final Color iconForeground;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        shadow: false,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PandoraIconBadge(
                  icon: icon,
                  foreground: iconForeground,
                  background: iconBackground,
                  size: 48,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: pandoraSimpleMutedText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: PandoraSimpleColors.deepRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: PandoraSimpleColors.deepRed,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      );
}

class _WorkingCard extends StatelessWidget {
  const _WorkingCard({required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.topProjects.isEmpty) {
      return const PandoraEmptyTruth(
        title: 'No active work is verified',
        message: 'New work will appear here after Pandora accepts it.',
      );
    }
    final projects = summary.topProjects.take(3).toList(growable: false);
    return PandoraSimpleCard(
      padding: EdgeInsets.zero,
      shadow: false,
      child: Column(
        children: [
          for (var index = 0; index < projects.length; index++) ...[
            _WorkingRow(project: projects[index]),
            if (index != projects.length - 1)
              const Divider(height: 1, color: PandoraSimpleColors.line),
          ],
        ],
      ),
    );
  }
}

class _WorkingRow extends StatelessWidget {
  const _WorkingRow({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final ownerState = resolveOwnerProjectState(project);
    final blocked = ownerState == OwnerProjectState.blocked ||
        ownerState == OwnerProjectState.ownerActionRequired;
    final testing = ownerState == OwnerProjectState.executing;
    final healthy = ownerState == OwnerProjectState.monitoring &&
        project.evidenceState(EvidenceStage.productionVerified) ==
            EvidenceClaimState.verified;
    final foreground = healthy
        ? PandoraSimpleColors.green
        : blocked
            ? PandoraSimpleColors.red
            : testing
                ? PandoraSimpleColors.amber
                : PandoraSimpleColors.ink;
    final background = healthy
        ? PandoraSimpleColors.greenWash
        : blocked
            ? PandoraSimpleColors.blush
            : testing
                ? PandoraSimpleColors.amberWash
                : const Color(0xFFF5F1EC);
    return InkWell(
      onTap: () => _openHome(context, ProjectDetailScreen(project: project)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            PandoraIconBadge(
              icon: healthy
                  ? Icons.shield_outlined
                  : testing
                      ? Icons.code_rounded
                      : Icons.motion_photos_on_outlined,
              foreground: foreground,
              background: background,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    project.nextAction ?? project.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pandoraSimpleMutedText,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PandoraStatusPill(
              label: ownerWorkStatusLabel(project),
              foreground: foreground,
              background: background,
              icon: healthy ? Icons.check_circle_outline_rounded : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessPulse extends StatelessWidget {
  const _BusinessPulse({required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final verified = summary.countersVerified;
    final metrics = <_PulseMetric>[
      _PulseMetric(
        icon: Icons.person_outline_rounded,
        label: 'Active systems',
        value: verified ? '${summary.activeProjectCount}' : '—',
        note: verified ? 'Verified now' : 'Not verified',
        foreground: PandoraSimpleColors.blue,
        background: PandoraSimpleColors.blueWash,
      ),
      _PulseMetric(
        icon: Icons.event_available_outlined,
        label: 'Decisions',
        value: verified ? '${summary.approvalCount}' : '—',
        note: verified && summary.approvalCount > 0
            ? '${summary.approvalCount} need attention'
            : 'Nothing waiting',
        foreground: PandoraSimpleColors.red,
        background: PandoraSimpleColors.blush,
      ),
      const _PulseMetric(
        icon: Icons.payments_outlined,
        label: 'Revenue',
        value: '—',
        note: 'Connect accounting',
        foreground: PandoraSimpleColors.green,
        background: PandoraSimpleColors.greenWash,
      ),
      _PulseMetric(
        icon: Icons.settings_suggest_outlined,
        label: 'Operations',
        value: summary.healthLabel,
        note: summary.freshness.isFresh ? 'Fresh evidence' : 'Check freshness',
        foreground: PandoraSimpleColors.purple,
        background: PandoraSimpleColors.purpleWash,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = width >= 690
            ? 4
            : width >= 420
                ? 2
                : 1;
        final itemWidth = (width - ((count - 1) * 10)) / count;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _PulseCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _PulseMetric {
  const _PulseMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color foreground;
  final Color background;
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({required this.metric});

  final _PulseMetric metric;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        padding: const EdgeInsets.all(13),
        shadow: false,
        child: Row(
          children: [
            PandoraIconBadge(
              icon: metric.icon,
              foreground: metric.foreground,
              background: metric.background,
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    style: const TextStyle(
                      color: PandoraSimpleColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: metric.foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.onAsk,
    required this.onExplain,
  });

  final String? recommendation;
  final ValueChanged<String> onAsk;
  final ValueChanged<String> onExplain;

  @override
  Widget build(BuildContext context) {
    final message = recommendation ??
        'No recommendation is verified yet. Ask Pandora what the safest useful next step should be.';
    return PandoraSimpleCard(
      backgroundColor: const Color(0xFFFFF5F6),
      borderColor: const Color(0xFFF2CDD2),
      shadow: false,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              decoration: const BoxDecoration(
                color: PandoraSimpleColors.red,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PandoraIconBadge(
                      icon: Icons.auto_awesome_rounded,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            style: const TextStyle(
                              color: PandoraSimpleColors.ink,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Pandora can turn this into a governed working result.',
                            style: pandoraSimpleMutedText,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actions = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PandoraPrimaryButton(
                      label: 'Automate this',
                      icon: Icons.auto_awesome_rounded,
                      onPressed: () => onAsk(message),
                    ),
                    TextButton(
                      onPressed: () => onExplain(message),
                      style: TextButton.styleFrom(
                        foregroundColor: PandoraSimpleColors.deepRed,
                      ),
                      child: const Text('Why?'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [content, const SizedBox(height: 14), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 16),
                    SizedBox(width: 160, child: actions),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemsStrip extends StatelessWidget {
  const _SystemsStrip({required this.summary, required this.onOpenSystems});

  final HomeSummary summary;
  final VoidCallback onOpenSystems;

  @override
  Widget build(BuildContext context) {
    if (summary.topProjects.isEmpty) {
      return PandoraEmptyTruth(
        title: 'No verified systems yet',
        message: 'Ask Pandora to build or connect the first system.',
        actionLabel: 'Open Systems',
        onAction: onOpenSystems,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final projects = summary.topProjects.take(4).toList(growable: false);
        final count = constraints.maxWidth >= 690
            ? 4
            : constraints.maxWidth >= 420
                ? 2
                : 1;
        final width = (constraints.maxWidth - ((count - 1) * 10)) / count;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < projects.length; index++)
              SizedBox(
                width: width,
                child: _SystemCard(project: projects[index], index: index),
              ),
          ],
        );
      },
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.project, required this.index});

  final ProjectSummary project;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = <(Color, Color, IconData)>[
      (
        PandoraSimpleColors.green,
        PandoraSimpleColors.greenWash,
        Icons.calendar_today_outlined,
      ),
      (
        PandoraSimpleColors.blue,
        PandoraSimpleColors.blueWash,
        Icons.language_rounded,
      ),
      (
        PandoraSimpleColors.amber,
        PandoraSimpleColors.amberWash,
        Icons.chat_bubble_outline_rounded,
      ),
      (
        PandoraSimpleColors.purple,
        PandoraSimpleColors.purpleWash,
        Icons.groups_outlined,
      ),
    ];
    final color = colors[index % colors.length];
    return PandoraSimpleCard(
      padding: const EdgeInsets.all(13),
      shadow: false,
      onTap: () => _openHome(context, ProjectDetailScreen(project: project)),
      child: Row(
        children: [
          PandoraIconBadge(
            icon: color.$3,
            foreground: color.$1,
            background: color.$2,
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color.$1,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        ownerSystemHealthLabel(project),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.$1,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.summary, required this.onOpenActivity});

  final HomeSummary summary;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    if (summary.recentActivity.isEmpty) {
      return PandoraEmptyTruth(
        title: 'No recent verified activity',
        message: 'Completed and verified work will appear here.',
        actionLabel: 'Open activity',
        onAction: onOpenActivity,
      );
    }
    final events = summary.recentActivity.take(4).toList(growable: false);
    return PandoraSimpleCard(
      padding: EdgeInsets.zero,
      shadow: false,
      child: Column(
        children: [
          for (var index = 0; index < events.length; index++) ...[
            InkWell(
              onTap: onOpenActivity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      index == 2
                          ? Icons.warning_amber_rounded
                          : index == 3
                              ? Icons.rocket_launch_outlined
                              : Icons.check_circle_rounded,
                      color: index == 2
                          ? PandoraSimpleColors.amber
                          : index == 3
                              ? PandoraSimpleColors.purple
                              : index == 1
                                  ? PandoraSimpleColors.blue
                                  : PandoraSimpleColors.green,
                      size: 23,
                    ),
                    const SizedBox(width: 13),
                    SizedBox(
                      width: 76,
                      child: Text(
                        index == 3 ? 'Earlier' : 'Recent',
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        events[index].summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: pandoraSimpleText,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: PandoraSimpleColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (index != events.length - 1)
              const Divider(height: 1, color: PandoraSimpleColors.line),
          ],
        ],
      ),
    );
  }
}
