import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/eurofish_workspace_api.dart';
import 'enterprise_workspace_home.dart';
import 'plp_resort_workspace.dart';

class SharedEnterpriseWorkspaceScreen extends StatelessWidget {
  const SharedEnterpriseWorkspaceScreen({
    super.key,
    required this.selection,
    required this.onHome,
    required this.onOpenSection,
  });

  final EnterpriseWorkspaceSelection selection;
  final VoidCallback onHome;
  final ValueChanged<String> onOpenSection;

  @override
  Widget build(BuildContext context) {
    switch (selection.workspace.key) {
      case 'plp-boracay':
        return _PlpSharedWorkspace(
          selection: selection,
          onHome: onHome,
          onOpenSection: onOpenSection,
        );
      case '1064-euro-fish-traders':
        return _EurofishSharedWorkspace(
          selection: selection,
          onHome: onHome,
          onOpenSection: onOpenSection,
        );
      case 'bok':
        return _BusinessSection(
          selection: selection,
          onHome: onHome,
          onOpenSection: onOpenSection,
          sourceMessage:
              'No verified BOK operating source is connected for this section yet.',
        );
      default:
        return _FailureState(
          selection: selection,
          message: 'This workspace section is unavailable.',
          onHome: onHome,
        );
    }
  }
}

class _PlpSharedWorkspace extends StatefulWidget {
  const _PlpSharedWorkspace({
    required this.selection,
    required this.onHome,
    required this.onOpenSection,
  });

  final EnterpriseWorkspaceSelection selection;
  final VoidCallback onHome;
  final ValueChanged<String> onOpenSection;

  @override
  State<_PlpSharedWorkspace> createState() => _PlpSharedWorkspaceState();
}

class _PlpSharedWorkspaceState extends State<_PlpSharedWorkspace> {
  late Future<Map<String, Object?>> _future = _load();

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.from(value);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    throw StateError('Invalid PLP bootstrap payload.');
  }

  Future<Map<String, Object?>> _load() async {
    final client = Supabase.instance.client;
    final bootstrap =
        _map(await client.rpc('plp_enterprise_mobile_bootstrap_v1'));
    try {
      bootstrap['resortCommandCenter'] =
          _map(await client.rpc('plp_resort_command_center_v1'));
    } catch (_) {
      // The authenticated PLP bootstrap remains useful while this additive
      // projection is unavailable.
    }
    return bootstrap;
  }

  String get _sectionId {
    switch (widget.selection.section.routeSlug) {
      case 'operations':
      case 'needs-you':
        return 'operations';
      case 'guests':
        return 'guests';
      case 'sales-revenue':
        return 'revenue';
      case 'team-access':
        return 'team';
      case 'activity':
        return 'activity';
      default:
        return 'today';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingState(
            label: 'Loading verified resort data…',
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _FailureState(
            selection: widget.selection,
            message:
                'Verified resort data is unavailable. Pandora will not invent operational state.',
            onHome: widget.onHome,
            onRetry: () => setState(() => _future = _load()),
          );
        }
        return PlpResortWorkspaceScreen(
          key: ValueKey<String>(
            'shared-plp-${widget.selection.section.routeSlug}',
          ),
          section: plpResortSectionById(_sectionId)!,
          bootstrap: snapshot.data!,
          onOpenNavigation: () {},
          onRefresh: () => setState(() => _future = _load()),
          onOpenSection: widget.onOpenSection,
          onOpenActivity: () => widget.onOpenSection('activity'),
        );
      },
    );
  }
}

class _EurofishSharedWorkspace extends StatefulWidget {
  const _EurofishSharedWorkspace({
    required this.selection,
    required this.onHome,
    required this.onOpenSection,
  });

  final EnterpriseWorkspaceSelection selection;
  final VoidCallback onHome;
  final ValueChanged<String> onOpenSection;

  @override
  State<_EurofishSharedWorkspace> createState() =>
      _EurofishSharedWorkspaceState();
}

class _EurofishSharedWorkspaceState extends State<_EurofishSharedWorkspace> {
  final EurofishWorkspaceApi _api = EurofishWorkspaceApi();
  late Future<EurofishWorkspaceSnapshot> _future = _api.loadOverview();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EurofishWorkspaceSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingState(
            label: 'Loading import/export state…',
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _FailureState(
            selection: widget.selection,
            message:
                'No authorized import/export provider snapshot is available.',
            onHome: widget.onHome,
            onRetry: () => setState(() => _future = _api.loadOverview()),
          );
        }

        final data = snapshot.data!;
        return _BusinessSection(
          selection: widget.selection,
          onHome: widget.onHome,
          onOpenSection: widget.onOpenSection,
          metrics: <String, String>{
            'Verified evidence': data.verifiedEvidenceCount.toString(),
            'Needs verification': data.needsVerificationCount.toString(),
            'Connected sources': data.connectedSourceCount.toString(),
          },
        );
      },
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({
    required this.selection,
    required this.onHome,
    required this.onOpenSection,
    this.metrics = const <String, String>{},
    this.sourceMessage,
  });

  final EnterpriseWorkspaceSelection selection;
  final VoidCallback onHome;
  final ValueChanged<String> onOpenSection;
  final Map<String, String> metrics;
  final String? sourceMessage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07111B),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: ValueKey<String>(
            'shared-${selection.workspace.key}-${selection.section.routeSlug}',
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey<String>('shared-workspace-home'),
                  onPressed: onHome,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    selection.workspace.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              selection.section.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            if (metrics.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final entry in metrics.entries)
                    Container(
                      width: 150,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1728),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF263750),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.key,
                            style: const TextStyle(
                              color: Color(0xFF9FB0C5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              )
            else
              Container(
                key: const ValueKey<String>(
                  'shared-workspace-source-unavailable',
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1728),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  sourceMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
              ),
            const SizedBox(height: 28),
            for (final section in selection.workspace.sections)
              if (section.routeSlug != selection.section.routeSlug)
                ListTile(
                  key: ValueKey<String>(
                    'shared-section-${selection.workspace.key}-${section.routeSlug}',
                  ),
                  leading: Icon(
                    section.icon,
                    color: selection.workspace.accent,
                  ),
                  title: Text(
                    section.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => onOpenSection(section.routeSlug),
                ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07111B),
      child: Center(
        child: Semantics(
          label: label,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({
    required this.selection,
    required this.onHome,
    required this.message,
    this.onRetry,
  });

  final EnterpriseWorkspaceSelection selection;
  final VoidCallback onHome;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07111B),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: onHome,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(height: 24),
              Text(
                selection.workspace.name,
                style: const TextStyle(
                  color: Color(0xFF9FB0C5),
                ),
              ),
              Text(
                selection.section.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const ValueKey<String>('shared-workspace-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
