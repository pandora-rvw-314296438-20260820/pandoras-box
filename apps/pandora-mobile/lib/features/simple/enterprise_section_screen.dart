import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../pandora_config.dart';
import 'pandora_v2_ui.dart';

class EnterpriseSectionScreen extends StatelessWidget {
  const EnterpriseSectionScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.items = const <String>[],
  });

  final String title;
  final String description;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (title == 'Overview') {
      return _EnterpriseManagedOverview(description: description);
    }
    return PandoraPage(
      title: title,
      subtitle: description,
      child: PandoraSurface(
        title: title,
        subtitle: 'Enterprise control panel',
        leading: Icon(icon),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty)
              Text(
                'This section is ready for its provider-specific controls and data.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              for (final item in items) _bullet(item),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String item) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.circle, size: 6),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(item)),
          ],
        ),
      );
}

class _EnterpriseManagedOverview extends StatefulWidget {
  const _EnterpriseManagedOverview({required this.description});

  final String description;

  @override
  State<_EnterpriseManagedOverview> createState() =>
      _EnterpriseManagedOverviewState();
}

class _EnterpriseManagedOverviewState
    extends State<_EnterpriseManagedOverview> {
  late Future<List<_ManagedProject>> _projects;

  @override
  void initState() {
    super.initState();
    _projects = _load();
  }

  Future<List<_ManagedProject>> _load() async {
    final rows = await Supabase.instance.client
        .from('projectos_projects')
        .select(
          'id,project_key,name,repository,status,objective,config,updated_at',
        )
        .eq('organization_id', PandoraConfig.organizationId)
        .neq('status', 'archived')
        .order('updated_at', ascending: false);
    return rows
        .map(_ManagedProject.fromJson)
        .where((project) => project.enterpriseManaged)
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _projects = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Overview',
        subtitle: widget.description,
        onRefresh: _refresh,
        child: FutureBuilder<List<_ManagedProject>>(
          future: _projects,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return PandoraSurface(
                title: 'Managed systems unavailable',
                subtitle: 'Pandora could not refresh ProjectOS right now.',
                leading: const Icon(Icons.cloud_off_outlined),
                child: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              );
            }
            final projects = snapshot.data ?? const <_ManagedProject>[];
            if (projects.isEmpty) {
              return const PandoraSurface(
                title: 'No managed systems yet',
                subtitle: 'Import a repository from Code to add one.',
                leading: Icon(Icons.business_center_outlined),
                child: Text(
                    'Pandora has no Enterprise-managed ProjectOS record yet.'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PandoraSurface(
                  title: 'Managed systems',
                  subtitle:
                      '${projects.length} Enterprise system${projects.length == 1 ? '' : 's'} connected to ProjectOS',
                  leading: const Icon(Icons.business_center_rounded),
                  child: const Text(
                    'These records are persistent Pandora context for source, runtime, integrations, deployments and governed changes.',
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < projects.length; i++) ...[
                  _projectCard(projects[i]),
                  if (i != projects.length - 1) const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      );

  Widget _projectCard(_ManagedProject project) {
    final profile = project.profile;
    final deployment = _map(profile['deployment']);
    final runtime = _map(profile['runtime']);
    final inventory = _map(profile['repositoryInventory']);
    final stack = _strings(profile['stack']);
    final capabilities = _strings(profile['capabilities']);
    final exactSha = '${profile['exactSourceSha'] ?? ''}';
    final shortSha =
        exactSha.length > 12 ? exactSha.substring(0, 12) : exactSha;
    final runtimeReady = deployment['runtimeConfigurationReady'] == true;
    return PandoraSurface(
      title: project.name,
      subtitle: '${project.projectKey} • ${project.repository}',
      leading: const Icon(Icons.apartment_rounded),
      trailing: _statusPill(
        runtimeReady ? 'Fully configured' : 'Code live • runtime setup needed',
        runtimeReady,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(project.objective),
          const SizedBox(height: 16),
          _sectionTitle('Source authority'),
          _fact('Repository', project.repository),
          _fact('Branch', '${profile['defaultBranch'] ?? 'main'}'),
          _fact('Exact source', shortSha),
          _fact('Files', '${inventory['files'] ?? '—'}'),
          _fact('API files', '${inventory['apiFiles'] ?? '—'}'),
          _fact('Supabase migrations',
              '${inventory['supabaseMigrations'] ?? '—'}'),
          const SizedBox(height: 12),
          _sectionTitle('Deployment'),
          _fact('State', '${deployment['status'] ?? 'not checked'}'),
          _fact('Production', '${deployment['productionDomain'] ?? '—'}'),
          _fact('Deployment ID', '${deployment['deploymentId'] ?? '—'}'),
          const SizedBox(height: 12),
          _sectionTitle('Runtime'),
          _fact(
            'Managed runtime',
            runtimeReady ? 'Ready' : 'Configuration incomplete',
          ),
          _fact(
            'Existing production',
            '${runtime['existingProductionHealth'] ?? 'not checked'}',
          ),
          _fact(
            'Known live domain',
            '${runtime['knownExistingProductionDomain'] ?? '—'}',
          ),
          if (stack.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle('Application stack'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final item in stack) Chip(label: Text(item))],
            ),
          ],
          if (capabilities.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionTitle('What Pandora knows this system can do'),
            for (final capability in capabilities) _capability(capability),
          ],
        ],
      ),
    );
  }

  Widget _capability(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.circle, size: 6),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _statusPill(String label, bool ready) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ready ? PandoraV2Colors.ink : PandoraV2Colors.muted,
              ),
        ),
      );
  Widget _sectionTitle(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(value, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PandoraV2Colors.muted,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(value.isEmpty ? '—' : value)),
          ],
        ),
      );

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];
}

class _ManagedProject {
  const _ManagedProject({
    required this.projectKey,
    required this.name,
    required this.repository,
    required this.objective,
    required this.enterpriseManaged,
    required this.profile,
  });

  final String projectKey;
  final String name;
  final String repository;
  final String objective;
  final bool enterpriseManaged;
  final Map<String, dynamic> profile;

  factory _ManagedProject.fromJson(Map<String, dynamic> json) {
    final config = json['config'] is Map
        ? Map<String, dynamic>.from(json['config'] as Map)
        : <String, dynamic>{};
    final profile = config['enterpriseProfile'] is Map
        ? Map<String, dynamic>.from(config['enterpriseProfile'] as Map)
        : <String, dynamic>{};
    return _ManagedProject(
      projectKey: '${json['project_key'] ?? ''}',
      name: '${json['name'] ?? 'Managed project'}',
      repository: '${json['repository'] ?? ''}',
      objective: '${json['objective'] ?? ''}',
      enterpriseManaged: config['enterpriseManaged'] == true,
      profile: profile,
    );
  }
}
