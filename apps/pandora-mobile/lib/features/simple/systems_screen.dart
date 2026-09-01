import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../connections/connections_screen.dart';
import '../projects/project_detail_screen.dart';

void _openSystems(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class SystemsScreen extends StatefulWidget {
  const SystemsScreen({super.key});

  @override
  State<SystemsScreen> createState() => _SystemsScreenState();
}

class _SystemsScreenState extends State<SystemsScreen> {
  bool _loading = true;
  String? _error;
  List<ProjectSummary> _projects = const [];
  List<ConnectionSummary> _connections = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _projects.isEmpty && _connections.isEmpty) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final repository = PandoraDependencies.of(context).repository;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projectsFuture = repository.projects(allowCached: true);
      final connectionsFuture = repository.connections(allowCached: true);
      final projects = await projectsFuture;
      final connections = await connectionsFuture;
      if (!mounted) return;
      setState(() {
        _projects = projects.data;
        _connections = connections.data;
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
        _error = 'Pandora could not verify your systems.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
    title: 'Systems',
    subtitle: 'What Pandora is building, running, and connected to.',
    onRefresh: _load,
    child: _loading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(PandoraSpacing.xl),
              child: CircularProgressIndicator(),
            ),
          )
        : _error != null
        ? PandoraSurface(
            title: 'Systems unavailable',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_error!),
                const SizedBox(height: PandoraSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PandoraSurface(
                title: 'My Systems',
                subtitle:
                    '${_projects.length} systems currently visible to you.',
                child: _projects.isEmpty
                    ? const Text('No systems are available yet.')
                    : Column(
                        children: [
                          for (final project in _projects)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                child: Icon(Icons.layers_outlined),
                              ),
                              title: Text(project.name),
                              subtitle: Text(
                                'Health: ${ownerSystemHealthLabel(project)}\n'
                                'Work: ${ownerWorkStatusLabel(project)} · '
                                '${ownerProductionStatusLabel(project)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openSystems(
                                context,
                                ProjectDetailScreen(project: project),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: PandoraSpacing.md),
              PandoraSurface(
                title: 'Connections',
                subtitle:
                    'Services Pandora can use within the access you approved.',
                child: _connections.isEmpty
                    ? const Text('No verified connections are available yet.')
                    : Column(
                        children: [
                          for (final connection in _connections)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                resolveOwnerConnectionState(connection) ==
                                        OwnerConnectionState.verified
                                    ? Icons.link_rounded
                                    : Icons.link_off_rounded,
                              ),
                              title: Text(connection.name),
                              subtitle: Text(
                                resolveOwnerConnectionState(connection).label,
                              ),
                              trailing: Text(
                                ownerConnectionCapabilityLabel(connection),
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: PandoraSpacing.md),
              OutlinedButton.icon(
                onPressed: () =>
                    _openSystems(context, const ConnectionsScreen()),
                icon: const Icon(Icons.settings_input_component_outlined),
                label: const Text('Connection details'),
              ),
            ],
          ),
  );
}
