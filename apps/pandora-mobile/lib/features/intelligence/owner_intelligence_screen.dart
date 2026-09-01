import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/proof_ladder.dart';

enum OwnerIntelligenceSection {
  portfolio,
  memory,
  search,
  notifications,
  autopilot,
  release,
}

class OwnerIntelligenceScreen extends StatefulWidget {
  const OwnerIntelligenceScreen({
    super.key,
    this.initialSection = OwnerIntelligenceSection.portfolio,
  });

  final OwnerIntelligenceSection initialSection;

  @override
  State<OwnerIntelligenceScreen> createState() {
    return _OwnerIntelligenceScreenState();
  }
}

class _OwnerIntelligenceScreenState extends State<OwnerIntelligenceScreen> {
  Future<_OwnerData>? _future;

  /// Last successfully verified snapshot, retained so a refresh never replaces
  /// useful owner information with a skeleton. It is only ever rendered behind
  /// an explicit staleness notice, so saved data is never silently presented
  /// as a live decision.
  _OwnerData? _lastVerified;
  DateTime? _verifiedAt;

  late OwnerIntelligenceSection _section;
  final _searchController = TextEditingController();
  String _query = '';
  String? _busyProject;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _start();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_OwnerData> _load() async {
    final repository = PandoraDependencies.of(context).repository;
    final home = await repository.home();
    final projects = await repository.projects(allowCached: true);
    final approvals = await repository.approvals();
    final activity = await repository.activity(allowCached: true);
    final connections = await repository.connections(allowCached: true);
    final data = _OwnerData(
      home: home.data,
      projects: projects.data,
      approvals: approvals.data,
      activity: activity.data,
      connections: connections.data,
      degraded: projects.isCached || activity.isCached || connections.isCached,
    );
    _lastVerified = data;
    _verifiedAt = DateTime.now().toUtc();
    return data;
  }

  /// Starts a load whose rejection is observed immediately.
  ///
  /// `FutureBuilder` only subscribes on the next build, so a future that
  /// rejects in the meantime would be reported as an unhandled asynchronous
  /// error even though the screen renders the failure correctly.
  Future<_OwnerData> _start() {
    final future = _load();
    future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  void _refresh() {
    setState(() {
      _future = _start();
    });
  }

  /// Relative age of the retained snapshot, for the staleness notice.
  String _verifiedAgo() {
    final verifiedAt = _verifiedAt;
    if (verifiedAt == null) {
      return 'Verified earlier';
    }
    final elapsed = DateTime.now().toUtc().difference(verifiedAt);
    if (elapsed.inMinutes < 1) {
      return 'Verified moments ago';
    }
    if (elapsed.inMinutes < 60) {
      return 'Verified ${elapsed.inMinutes} minutes ago';
    }
    if (elapsed.inHours < 24) {
      return 'Verified ${elapsed.inHours} hours ago';
    }
    return 'Verified ${elapsed.inDays} days ago';
  }

  Future<void> _delegate(
    ProjectSummary project, {
    required bool prepareOnly,
  }) async {
    if (_busyProject != null) {
      return;
    }
    setState(() {
      _busyProject = project.id;
      _preparing = prepareOnly;
    });

    final message = prepareOnly
        ? 'Prepare the highest-value safe next action. Do not execute it. '
              'Explain risk, dependencies, required proof, rollback, and '
              'owner approval gates.'
        : 'Continue all safe, reversible, no-cost connected work. Stop '
              'before spending, destructive production or data changes, '
              'legal or public commitments, regulated activation, or '
              'production release. Preserve evidence and project state.';

    try {
      await PandoraDependencies.of(context).repository
          .ask(message: message, projectId: project.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            prepareOnly
                ? 'Governed preparation request accepted.'
                : 'Governed safe-work request accepted.',
          ),
        ),
      );
      _refresh();
    } on PandoraRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _busyProject = null;
          _preparing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PandoraPage(
      title: _title(_section),
      subtitle: _subtitle(_section),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh verified owner data',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<OwnerIntelligenceSection>(
            initialValue: _section,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'View',
              prefixIcon: Icon(Icons.auto_awesome_rounded),
            ),
            items: OwnerIntelligenceSection.values.map((section) {
              return DropdownMenuItem(
                value: section,
                child: Text(_title(section)),
              );
            }).toList(),
            onChanged: (section) {
              if (section != null) {
                setState(() => _section = section);
              }
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<_OwnerData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _view(snapshot.data!);
              }
              // A refresh must not discard verified content. Show what was last
              // verified, clearly labelled, and keep refreshing underneath.
              final retained = _lastVerified;
              if (retained != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DegradedContentNotice(
                      message: snapshot.hasError
                          ? 'Live owner state could not be refreshed. '
                                '${_verifiedAgo()}.'
                          : 'Refreshing live owner state. ${_verifiedAgo()}.',
                      onRetry: _refresh,
                    ),
                    const SizedBox(height: PandoraSpacing.md),
                    _view(retained),
                  ],
                );
              }
              if (snapshot.hasError) {
                return _error();
              }
              return _loading();
            },
          ),
        ],
      ),
    );
  }

  Widget _view(_OwnerData data) {
    switch (_section) {
      case OwnerIntelligenceSection.portfolio:
        return _portfolio(data);
      case OwnerIntelligenceSection.memory:
        return _memory(data);
      case OwnerIntelligenceSection.search:
        return _search(data);
      case OwnerIntelligenceSection.notifications:
        return _notifications(data);
      case OwnerIntelligenceSection.autopilot:
        return _autopilot(data);
      case OwnerIntelligenceSection.release:
        return _release(data);
    }
  }

  Widget _portfolio(_OwnerData data) {
    final recommendations = _recommendations(data);
    return _stack([
      if (data.degraded) _degraded(),
      _panel(
        'SYSTEM POSTURE',
        data.home.healthLabel,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('${data.home.activeProjectCount}', 'Active projects'),
            _metric('${data.home.needsAttentionCount}', 'Needs attention'),
            _metric('${data.home.approvalCount}', 'Approvals'),
          ],
        ),
      ),
      _panel(
        'PANDORA RECOMMENDS',
        recommendations.isEmpty
            ? 'No owner intervention is indicated'
            : recommendations.first,
        Text(
          recommendations.length < 2
              ? 'Verified state stays visible and missing proof fails closed.'
              : recommendations.skip(1).take(3).join('\n• '),
        ),
      ),
      _panel(
        'NEEDS YOU',
        data.approvals.isEmpty
            ? 'No pending approvals'
            : '${data.approvals.length} decisions waiting',
        _approvalList(data.approvals.take(3)),
      ),
      _panel(
        'PORTFOLIO',
        'Highest-value project signals',
        _projectList(data.projects.take(5)),
      ),
    ]);
  }

  Widget _memory(_OwnerData data) {
    return _stack([
      if (data.degraded) _degraded(),
      _panel(
        'MEMORY & LEARNING',
        'Read-only owner memory snapshot',
        const Text(
          'This summarizes verified owner-API state. Canonical Memory '
          'promotion remains review-gated. The mobile client never silently '
          'promotes learning candidates or writes secrets into Memory.',
        ),
      ),
      _panel(
        'CURRENT PROJECT TRUTH',
        '${data.projects.length} projects in the owner snapshot',
        _projectList(data.projects.take(8)),
      ),
      _panel(
        'RECENT LEARNING SIGNALS',
        'Meaningful recorded changes',
        _activityList(data.activity.take(8)),
      ),
    ]);
  }

  Widget _search(_OwnerData data) {
    final hits = _searchHits(data, _query);
    return _stack([
      if (data.degraded) _degraded(),
      TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() => _query = value);
        },
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          labelText: 'Search Pandora',
          hintText: 'Projects, approvals, activity, connections',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      _panel(
        'UNIVERSAL SEARCH',
        _query.trim().isEmpty
            ? 'Search the authorized owner snapshot'
            : '${hits.length} matching results',
        _query.trim().isEmpty
            ? const Text(
                'Search is local to already-authorized owner data. '
                'Keystrokes are not sent to providers.',
              )
            : Column(
                children: hits.take(30).map((hit) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(hit.icon),
                    title: Text(hit.title),
                    subtitle: Text(hit.subtitle),
                    trailing: Text(hit.kind),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  Widget _notifications(_OwnerData data) {
    final items = <Widget>[];
    for (final approval in data.approvals) {
      items.add(
        _notice(
          Icons.approval_outlined,
          'Approval needed: ${approval.action}',
          approval.reason,
        ),
      );
    }
    for (final project in data.projects) {
      if (project.blocker != null) {
        items.add(
          _notice(
            Icons.error_outline_rounded,
            '${project.name} is blocked',
            project.blocker!,
          ),
        );
      } else if (!project.progressVerified) {
        items.add(
          _notice(
            Icons.fact_check_outlined,
            '${project.name} progress is not verified',
            project.nextAction ?? 'Proof is required before relying on it.',
          ),
        );
      }
    }
    return _stack([
      if (data.degraded) _degraded(),
      _panel(
        'ATTENTION INBOX',
        items.isEmpty
            ? 'Nothing currently requires attention'
            : '${items.length} meaningful notifications',
        items.isEmpty
            ? const Text(
                'Routine machine noise stays in Developer Diagnostics.',
              )
            : Column(children: items.take(30).toList()),
      ),
      _panel(
        'NOTIFICATION POLICY',
        'Owner-relevant events only',
        const Text(
          'Prioritize approvals, blockers, failed verification, release '
          'gates, and meaningful project changes.',
        ),
      ),
    ]);
  }

  Widget _autopilot(_OwnerData data) {
    final cards = <Widget>[
      _panel(
        'AUTOPILOT',
        'Governed autonomy, never blind execution',
        const Text(
          'Prepare creates a governed request without execution. Continue '
          'safe work delegates reversible, no-cost connected work and stops '
          'at spending, destructive changes, legal/public commitments, '
          'regulated activation, and production release.',
        ),
      ),
    ];
    for (final project in data.projects.take(12)) {
      final busy = _busyProject == project.id;
      cards.add(
        _panel(
          project.phase.toUpperCase(),
          project.name,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(project.nextAction ?? project.purpose),
              if (project.blocker != null) ...[
                const SizedBox(height: 8),
                Text('Blocked: ${project.blocker!}'),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _delegate(project, prepareOnly: true),
                    icon: busy && _preparing
                        ? _spinner()
                        : const Icon(Icons.playlist_add_check_rounded),
                    label: const Text('Prepare next action'),
                  ),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _delegate(project, prepareOnly: false),
                    icon: busy && !_preparing
                        ? _spinner()
                        : const Icon(Icons.auto_mode_rounded),
                    label: const Text('Continue safe work'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return _stack(cards);
  }

  Widget _release(_OwnerData data) {
    final cards = <Widget>[
      _panel(
        'RELEASE CENTER',
        'Evidence before promotion',
        const Text(
          'Readiness comes from the proof ladder. This screen never treats '
          'a green build as production verification and never bypasses the '
          'separate owner release authorization.',
        ),
      ),
    ];
    for (final project in data.projects.take(12)) {
      cards.add(
        _panel(
          project.status.toUpperCase(),
          project.name,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(project.phase),
              const SizedBox(height: 10),
              ProofLadder(stages: project.evidenceStages),
              const SizedBox(height: 10),
              Text(project.progressLabel),
              if (project.blocker != null) ...[
                const SizedBox(height: 8),
                Text('Blocker: ${project.blocker!}'),
              ],
              if (project.nextAction != null) ...[
                const SizedBox(height: 8),
                Text('Next: ${project.nextAction!}'),
              ],
            ],
          ),
        ),
      );
    }
    return _stack(cards);
  }

  Widget _approvalList(Iterable<ApprovalSummary> approvals) {
    final items = approvals.map((approval) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.approval_outlined),
        title: Text(approval.action),
        subtitle: Text(approval.reason),
      );
    }).toList();
    if (items.isEmpty) {
      return const Text(
        'Approval and execution remain separate and fail closed.',
      );
    }
    return Column(children: items);
  }

  Widget _projectList(Iterable<ProjectSummary> projects) {
    return Column(
      children: projects.map((project) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            project.blocker == null
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
          ),
          title: Text(project.name),
          subtitle: Text(
            project.blocker ?? project.nextAction ?? project.purpose,
          ),
          trailing: Text(project.phase),
        );
      }).toList(),
    );
  }

  Widget _activityList(Iterable<AuditEvent> events) {
    final items = events.map((event) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history_rounded),
        title: Text(event.summary),
        subtitle: Text(
          [
            if (event.project != null) event.project!,
            event.actor,
            if (event.provider != null) event.provider!,
          ].join(' · '),
        ),
      );
    }).toList();
    if (items.isEmpty) {
      return const Text('No recent activity was returned.');
    }
    return Column(children: items);
  }

  Widget _notice(IconData icon, String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  Widget _metric(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _panel(String eyebrow, String title, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              eyebrow,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _stack(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      spaced.add(children[index]);
      if (index < children.length - 1) {
        spaced.add(const SizedBox(height: 12));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced,
    );
  }

  Widget _degraded() {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Some read-only summaries are cached. Approval, execution, and '
          'authorization decisions still require live verification.',
        ),
      ),
    );
  }

  Widget _loading() {
    return _stack([
      const LinearProgressIndicator(),
      _panel(
        'PREPARING PANDORA',
        'Loading verified owner state',
        const Text(
          'Reconciling project truth, approvals, activity, and providers.',
        ),
      ),
    ]);
  }

  Widget _error() {
    return _panel(
      'NEEDS ATTENTION',
      'Owner intelligence could not refresh',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pandora did not substitute stale data for a live decision.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _spinner() {
    return const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _OwnerData {
  const _OwnerData({
    required this.home,
    required this.projects,
    required this.approvals,
    required this.activity,
    required this.connections,
    required this.degraded,
  });

  final HomeSummary home;
  final List<ProjectSummary> projects;
  final List<ApprovalSummary> approvals;
  final List<AuditEvent> activity;
  final List<ConnectionSummary> connections;
  final bool degraded;
}

class _SearchHit {
  const _SearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String kind;
  final String title;
  final String subtitle;
  final IconData icon;
}

List<String> _recommendations(_OwnerData data) {
  final result = <String>[];
  if (data.approvals.isNotEmpty) {
    result.add(
      'Review ${data.approvals.length} pending approvals before execution.',
    );
  }
  for (final project in data.projects) {
    if (project.blocker != null) {
      result.add('${project.name}: resolve ${project.blocker!}');
    } else if (!project.progressVerified) {
      result.add('${project.name}: verify proof before relying on progress.');
    } else if (project.nextAction != null) {
      result.add('${project.name}: ${project.nextAction!}');
    }
    if (result.length >= 5) {
      break;
    }
  }
  return result;
}

List<_SearchHit> _searchHits(_OwnerData data, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) {
    return const [];
  }
  final hits = <_SearchHit>[];

  bool matches(Iterable<String?> values) {
    return values.whereType<String>().any((value) {
      return value.toLowerCase().contains(query);
    });
  }

  for (final project in data.projects) {
    if (matches([
      project.name,
      project.purpose,
      project.phase,
      project.status,
      project.blocker,
      project.nextAction,
      project.repository,
    ])) {
      hits.add(
        _SearchHit(
          kind: 'Project',
          title: project.name,
          subtitle: project.nextAction ?? project.blocker ?? project.purpose,
          icon: Icons.folder_open_rounded,
        ),
      );
    }
  }

  for (final approval in data.approvals) {
    if (matches([
      approval.action,
      approval.reason,
      approval.change,
      approval.projectId,
      approval.rollback,
    ])) {
      hits.add(
        _SearchHit(
          kind: 'Approval',
          title: approval.action,
          subtitle: approval.reason,
          icon: Icons.approval_rounded,
        ),
      );
    }
  }

  for (final event in data.activity) {
    if (matches([
      event.type,
      event.actor,
      event.summary,
      event.project,
      event.provider,
      event.result,
    ])) {
      hits.add(
        _SearchHit(
          kind: 'Activity',
          title: event.summary,
          subtitle: event.project ?? event.actor,
          icon: Icons.history_rounded,
        ),
      );
    }
  }

  for (final connection in data.connections) {
    if (matches([
      connection.name,
      connection.purpose,
      connection.state,
      connection.status,
    ])) {
      hits.add(
        _SearchHit(
          kind: 'Connection',
          title: connection.name,
          subtitle: '${connection.state} · ${connection.purpose}',
          icon: Icons.cable_rounded,
        ),
      );
    }
  }

  return hits;
}

String _title(OwnerIntelligenceSection section) {
  switch (section) {
    case OwnerIntelligenceSection.portfolio:
      return 'Portfolio intelligence';
    case OwnerIntelligenceSection.memory:
      return 'Memory & learning';
    case OwnerIntelligenceSection.search:
      return 'Universal search';
    case OwnerIntelligenceSection.notifications:
      return 'Notifications';
    case OwnerIntelligenceSection.autopilot:
      return 'Autopilot';
    case OwnerIntelligenceSection.release:
      return 'Release center';
  }
}

String _subtitle(OwnerIntelligenceSection section) {
  switch (section) {
    case OwnerIntelligenceSection.portfolio:
      return 'What matters now and the safest next move.';
    case OwnerIntelligenceSection.memory:
      return 'Owner-readable truth and recent learning signals.';
    case OwnerIntelligenceSection.search:
      return 'Find authorized owner data without internal ID hunting.';
    case OwnerIntelligenceSection.notifications:
      return 'Only events that merit owner attention.';
    case OwnerIntelligenceSection.autopilot:
      return 'Continue governed safe work without bypassing gates.';
    case OwnerIntelligenceSection.release:
      return 'Evidence, blockers, next gates, and rollback readiness.';
  }
}
