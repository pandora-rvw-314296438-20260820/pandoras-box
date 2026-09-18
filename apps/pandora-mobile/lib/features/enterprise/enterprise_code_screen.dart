import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/data/enterprise_code_api.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';

class EnterpriseCodeScreen extends StatefulWidget {
  const EnterpriseCodeScreen({super.key});

  @override
  State<EnterpriseCodeScreen> createState() => _EnterpriseCodeScreenState();
}

class _EnterpriseCodeScreenState extends State<EnterpriseCodeScreen> {
  final TextEditingController _repositoryController = TextEditingController();
  Map<String, dynamic>? _inspection;
  Map<String, dynamic>? _deployment;
  bool _working = false;
  String? _error;
  String? _lastInspectedUrl;

  @override
  void dispose() {
    _repositoryController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _invoke(
    String action, {
    String? deploymentId,
  }) async {
    final payload = await const EnterpriseCodeApi().invoke(
      action,
      repositoryUrl: _repositoryController.text.trim(),
      deploymentId: deploymentId,
    );
    if (payload['ok'] != true) {
      throw StateError(_friendlyError('${payload['code'] ?? 'UNKNOWN_ERROR'}'));
    }
    return payload;
  }

  Future<void> _inspect() async {
    if (!_validRepositoryUrl) return _showInvalidUrl();
    await _run(() async {
      final payload = await _invoke('inspect');
      if (!mounted) return;
      setState(() {
        _inspection = _map(payload['inspection']);
        _deployment = null;
        _lastInspectedUrl = _repositoryController.text.trim();
      });
    });
  }

  Future<void> _deploy() async {
    if (!_validRepositoryUrl) return _showInvalidUrl();
    await _run(() async {
      final payload = await _invoke('deploy');
      if (!mounted) return;
      setState(() {
        _inspection = _map(payload['inspection']);
        _deployment = _map(payload['deployment']);
        _lastInspectedUrl = _repositoryController.text.trim();
      });
      HapticFeedback.mediumImpact();
    });
  }

  Future<void> _refreshDeployment() async {
    final id = '${_deployment?['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    await _run(() async {
      final payload = await _invoke('status', deploymentId: id);
      if (!mounted) return;
      setState(() => _deployment = _map(payload['deployment']));
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool get _validRepositoryUrl {
    final raw = _repositoryController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      return false;
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    return segments.length == 2;
  }

  void _showInvalidUrl() {
    setState(() => _error =
        'Enter a GitHub repository URL such as https://github.com/owner/repository.');
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  String _cleanError(Object error) {
    final raw = error.toString().replaceFirst('Bad state: ', '').trim();
    if (raw.startsWith('FunctionException')) {
      return 'Pandora could not complete the repository operation. Try again.';
    }
    return raw.isEmpty
        ? 'Pandora could not complete the repository operation.'
        : raw;
  }

  String _friendlyError(String code) => switch (code) {
        'INVALID_REPOSITORY_URL' => 'Enter a valid GitHub repository URL.',
        'GITHUB_REPOSITORY_UNAVAILABLE' =>
          'Pandora cannot read this repository with the connected GitHub access.',
        'REPOSITORY_TOO_LARGE' =>
          'This repository is larger than the current direct-deploy intake limit.',
        'REPOSITORY_FILE_TOO_LARGE' =>
          'One repository file is larger than the current direct-deploy intake limit.',
        'VERCEL_DEPLOY_FAILED' =>
          'Vercel rejected this deployment. Pandora preserved the source and did not claim success.',
        'OWNER_ROLE_REQUIRED' =>
          'Owner or admin access is required to manage repositories.',
        _ => 'Pandora could not complete the repository operation ($code).',
      };
  @override
  Widget build(BuildContext context) {
    final repo = _map(_inspection?['repository']);
    final detected = _map(_inspection?['detected']);
    final stack = (detected?['stack'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final envNames = (detected?['environmentVariables'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final canDeploy = !_working && _validRepositoryUrl;
    final repositoryInputError =
        _error != null && _error!.startsWith('Enter a GitHub repository URL')
            ? _error
            : null;
    final deploymentStatus = _deployment == null
        ? null
        : (_deployment?['status'] ?? 'unknown').toString();

    return PandoraPage(
      title: 'Code',
      subtitle:
          'Import a GitHub repository, let Pandora detect how it works, then deploy it through the governed Enterprise release path.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PandoraSurface(
            title: 'GitHub repository',
            subtitle:
                'Paste the repository link. Credentials stay in Pandora provider connections.',
            leading: const Icon(Icons.code_rounded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey<String>('enterprise-repository-url'),
                  controller: _repositoryController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {
                    if (_repositoryController.text.trim() !=
                        _lastInspectedUrl) {
                      _inspection = null;
                      _deployment = null;
                    }
                    _error = null;
                  }),
                  decoration: InputDecoration(
                    labelText: 'GitHub repository URL',
                    hintText: 'https://github.com/owner/repository',
                    prefixIcon: const Icon(Icons.link_rounded),
                    errorText: repositoryInputError,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                          'enterprise-inspect-repository'),
                      onPressed: canDeploy ? _inspect : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('Inspect repository'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey<String>('enterprise-import-deploy'),
                      onPressed: canDeploy ? _deploy : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.rocket_launch_outlined),
                      label: Text(_working ? 'Working…' : 'Import & deploy'),
                    ),
                  ],
                ),
                if (_working) ...[
                  const SizedBox(height: 12),
                  const Semantics(
                    liveRegion: true,
                    label: 'Repository operation in progress.',
                    child: Text(
                      'Working with the connected providers…',
                      style: TextStyle(color: PandoraV2Colors.muted),
                    ),
                  ),
                ],
                if (_error != null && repositoryInputError == null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    label: 'Repository operation failed. $_error',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PandoraV2Colors.soft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PandoraV2Colors.muted),
                      ),
                      child: Text(_error!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (repo != null && detected != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              label:
                  'Repository inspection updated from the connected provider.',
              child: _repositorySummary(repo, detected, stack, envNames),
            ),
          ],
          if (_deployment != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              label: 'Deployment provider readback. Status ' +
                  (deploymentStatus ?? 'unknown') +
                  '.',
              child: _deploymentSummary(_deployment!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _repositorySummary(
    Map<String, dynamic> repo,
    Map<String, dynamic> detected,
    List<String> stack,
    List<String> envNames,
  ) {
    final sha = '${repo['exactSha'] ?? ''}';
    return PandoraSurface(
      title: '${repo['fullName'] ?? 'Repository'}',
      subtitle: repo['private'] == true
          ? 'Private GitHub repository'
          : 'GitHub repository',
      leading: const Icon(Icons.account_tree_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fact('Source', '${repo['accessPath'] ?? 'verified'}'),
          _fact('Branch', '${repo['defaultBranch'] ?? '—'}'),
          _fact('Exact source', sha.length > 12 ? sha.substring(0, 12) : sha),
          _fact('Language', '${repo['primaryLanguage'] ?? 'Not detected'}'),
          _fact('Files', '${detected['fileCount'] ?? 0}'),
          _fact('Build', '${detected['buildCommand'] ?? 'Not detected'}'),
          _fact(
              'Output', '${detected['outputDirectory'] ?? 'Platform default'}'),
          _fact('Serverless functions',
              '${detected['serverlessFunctionCount'] ?? 0}'),
          _fact('Supabase migrations',
              '${detected['supabaseMigrationCount'] ?? 0}'),
          if (stack.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final item in stack) Chip(label: Text(item))],
            ),
          ],
          if (envNames.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Environment variables detected',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final name in envNames) Chip(label: Text(name))],
            ),
          ],
          if (detected['hasVercelConfig'] == true) ...[
            const SizedBox(height: 10),
            const Text('Vercel configuration detected in the repository.'),
          ],
        ],
      ),
    );
  }

  Widget _deploymentSummary(Map<String, dynamic> deployment) {
    final status = '${deployment['status'] ?? 'QUEUED'}';
    final aliases =
        (deployment['alias'] as List?)?.whereType<String>().toList() ??
            const <String>[];
    final url =
        aliases.isNotEmpty ? aliases.first : '${deployment['url'] ?? ''}';
    return PandoraSurface(
      title: 'Deployment',
      subtitle: 'Provider readback from Vercel',
      leading: const Icon(Icons.cloud_done_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fact('Status', status),
          _fact('Deployment ID', '${deployment['id'] ?? '—'}'),
          _fact('Target', '${deployment['target'] ?? 'production'}'),
          _fact('URL', url.isEmpty ? 'Pending' : url),
          if ('${deployment['sourceSha'] ?? ''}'.isNotEmpty)
            _fact('Exact source', '${deployment['sourceSha']}'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : _refreshDeployment,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh deployment status'),
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final stacked = constraints.maxWidth < 420 || textScale >= 1.4;
          if (stacked) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PandoraV2Colors.muted,
                        ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    value.isEmpty ? '—' : value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PandoraV2Colors.muted,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    value.isEmpty ? '—' : value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        },
      );
}
