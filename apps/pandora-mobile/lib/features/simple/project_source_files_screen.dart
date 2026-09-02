import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_experience_projection.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/models/project_source_models.dart';
import '../../core/platform/pandora_native_io.dart';
import 'pandora_v2_ui.dart';

class ProjectSourceFilesScreen extends StatefulWidget {
  const ProjectSourceFilesScreen({
    super.key,
    required this.project,
    required this.versionId,
  });

  final CustomerProject project;
  final String versionId;

  @override
  State<ProjectSourceFilesScreen> createState() =>
      _ProjectSourceFilesScreenState();
}

class _ProjectSourceFilesScreenState extends State<ProjectSourceFilesScreen> {
  final _search = TextEditingController();
  StreamSubscription<ProjectExperienceProjection>? _projectionSubscription;
  late String _selectedVersionId;
  List<_SourceVersionChoice> _versions = const [];
  ProjectSourceTree? _tree;
  ProjectSourceSearchResult? _searchResult;
  _SourceTreeDiff? _diff;
  String? _error;
  bool _loading = true;
  bool _searching = false;
  bool _exporting = false;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _selectedVersionId = widget.versionId;
    _versions = <_SourceVersionChoice>[
      _SourceVersionChoice(id: widget.versionId, label: 'Selected version'),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projectionSubscription == null) {
      final repository =
          PandoraDependencies.of(context).projectExperienceRepository;
      if (repository != null) {
        _projectionSubscription = repository
            .watchExperience(widget.project.id)
            .listen(_applyProjection, onError: (_) {});
      }
    }
    if (_tree == null && _loading) unawaited(_loadTree());
  }

  @override
  void dispose() {
    _projectionSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  ProjectExperienceApi? get _api =>
      PandoraDependencies.of(context).projectExperience;

  void _applyProjection(ProjectExperienceProjection projection) {
    if (!mounted ||
        projection.projectId.toLowerCase() != widget.project.id.toLowerCase()) {
      return;
    }
    final choices = <_SourceVersionChoice>[];
    void add(String? id, String label) {
      final normalized = id?.trim();
      if (normalized == null || normalized.isEmpty) return;
      if (choices.any((choice) => choice.id == normalized)) return;
      choices.add(_SourceVersionChoice(id: normalized, label: label));
    }

    add(projection.currentVersionId, 'Current');
    add(projection.candidateVersionId, 'Candidate');
    add(projection.productionVersionId, 'Live');
    add(_selectedVersionId, 'Selected version');
    if (choices.isEmpty) add(widget.versionId, 'Selected version');
    setState(() {
      _versions = List<_SourceVersionChoice>.unmodifiable(choices);
    });
  }

  Future<void> _selectVersion(String versionId) async {
    if (versionId == _selectedVersionId) return;
    setState(() {
      _selectedVersionId = versionId;
      _tree = null;
      _searchResult = null;
      _diff = null;
      _error = null;
      _loading = true;
    });
    await _loadTree();
  }

  Future<void> _chooseComparison() async {
    final api = _api;
    final selected = _tree;
    final alternatives =
        _versions.where((choice) => choice.id != _selectedVersionId).toList();
    if (api == null || selected == null || alternatives.isEmpty || _comparing) {
      return;
    }
    final choice = await showModalBottomSheet<_SourceVersionChoice>(
      context: context,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Compare exact source'),
                subtitle: Text('Choose another authoritative project version.'),
              ),
              for (final item in alternatives)
                ListTile(
                  title: Text(item.label),
                  subtitle: Text(item.id),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _comparing = true;
      _diff = null;
      _error = null;
    });
    try {
      final other = await api.loadSourceTree(
        projectId: widget.project.id,
        versionId: choice.id,
      );
      if (!mounted || selected.versionId != _selectedVersionId) return;
      setState(() {
        _diff = _SourceTreeDiff.compare(
          selected: selected,
          other: other,
          otherLabel: choice.label,
        );
      });
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  Future<void> _loadTree() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open source files right now.';
      });
      return;
    }
    try {
      final tree = await api.loadSourceTree(
        projectId: widget.project.id,
        versionId: _selectedVersionId,
      );
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loading = false;
        _error = null;
      });
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _openFile(ProjectSourceEntry entry) async {
    final api = _api;
    if (api == null) return;
    try {
      final file = await api.loadSourceFile(
        projectId: widget.project.id,
        versionId: _selectedVersionId,
        path: entry.path,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: PandoraV2Colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .86,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.path,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PandoraV2Colors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (file.encoding == 'utf-8')
                        IconButton(
                          tooltip: 'Copy source',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: file.content),
                            );
                            if (!sheetContext.mounted) return;
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Source copied.')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (file.redacted)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: PandoraV2InlineMessage(
                        title: 'Secret value withheld',
                        message:
                            'Pandora removed a high-risk secret value from this view.',
                      ),
                    ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PandoraV2Colors.soft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          file.encoding == 'utf-8'
                              ? file.content
                              : 'Binary file · ${file.byteSize} bytes',
                          style: const TextStyle(
                            color: PandoraV2Colors.ink,
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    final api = _api;
    if (api == null || query.length < 2 || _searching) return;
    setState(() => _searching = true);
    try {
      final result = await api.searchSourceFiles(
        projectId: widget.project.id,
        versionId: _selectedVersionId,
        query: query,
      );
      if (!mounted) return;
      setState(() {
        _searchResult = result;
        _error = null;
      });
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _exportZip() async {
    final api = _api;
    if (api == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await api.exportSourceZip(
        projectId: widget.project.id,
        versionId: _selectedVersionId,
      );
      final safeProject = widget.project.projectKey
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final saved = await PandoraNativeIo.saveBinaryDocument(
        name:
            '${safeProject.isEmpty ? 'pandora-project' : safeProject}-${widget.versionId}.zip',
        mimeType: 'application/zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Source ZIP saved.' : 'Source ZIP export was cancelled.',
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final searchResult = _searchResult;
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      appBar: AppBar(
        backgroundColor: PandoraV2Colors.canvas,
        foregroundColor: PandoraV2Colors.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text('Files'),
        actions: [
          if (tree != null)
            IconButton(
              tooltip: 'Download source ZIP',
              onPressed: _exporting ? null : _exportZip,
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadTree,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                widget.project.name,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Exact source', style: pandoraV2Muted),
              const SizedBox(height: 12),
              if (_versions.length > 1)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Version',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedVersionId,
                      isExpanded: true,
                      items: [
                        for (final version in _versions)
                          DropdownMenuItem<String>(
                            value: version.id,
                            child: Text(
                              '${version.label} · ${version.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) unawaited(_selectVersion(value));
                      },
                    ),
                  ),
                )
              else
                Text('Version $_selectedVersionId', style: pandoraV2Muted),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (tree == null)
                PandoraV2InlineMessage(
                  title: 'Source access',
                  message: _error ??
                      'Source files are available with source access.',
                  actionLabel: 'Try again',
                  onAction: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    unawaited(_loadTree());
                  },
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tree.files.length} files',
                        style: pandoraV2Muted,
                      ),
                    ),
                    if (_versions.length > 1)
                      TextButton.icon(
                        onPressed: _comparing ? null : _chooseComparison,
                        icon: _comparing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.difference_rounded),
                        label: const Text('Compare'),
                      ),
                  ],
                ),
                if (_diff != null) ...[
                  const SizedBox(height: 8),
                  _SourceDiffCard(diff: _diff!),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search source',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Search',
                            onPressed: _runSearch,
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  PandoraV2InlineMessage(
                    title: 'Source action unavailable',
                    message: _error!,
                    onAction: () => setState(() => _error = null),
                    actionLabel: 'Dismiss',
                  ),
                ],
                const SizedBox(height: 18),
                if (searchResult != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${searchResult.matches.length} matches for “${searchResult.query}”',
                          style: const TextStyle(
                            color: PandoraV2Colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _searchResult = null),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  for (final match in searchResult.matches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.search_rounded),
                      title: Text('${match.path}:${match.line}'),
                      subtitle: Text(
                        match.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        ProjectSourceEntry? entry;
                        for (final file in tree.files) {
                          if (file.path == match.path) {
                            entry = file;
                            break;
                          }
                        }
                        if (entry != null) unawaited(_openFile(entry));
                      },
                    ),
                  if (searchResult.truncated)
                    const Text(
                      'More matches exist. Refine your search.',
                      style: pandoraV2Muted,
                    ),
                  const Divider(height: 28),
                ],
                Text(
                  '${tree.files.length} files',
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (final entry in tree.files)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.isText
                          ? Icons.description_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${entry.byteSize} bytes'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openFile(entry),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _SourceVersionChoice {
  const _SourceVersionChoice({required this.id, required this.label});

  final String id;
  final String label;
}

enum _SourceTreeChangeStatus { added, modified, removed }

class _SourceTreeChange {
  const _SourceTreeChange({required this.path, required this.status});

  final String path;
  final _SourceTreeChangeStatus status;

  String get label => switch (status) {
        _SourceTreeChangeStatus.added => 'Added',
        _SourceTreeChangeStatus.modified => 'Modified',
        _SourceTreeChangeStatus.removed => 'Removed',
      };
}

class _SourceTreeDiff {
  const _SourceTreeDiff({
    required this.otherVersionId,
    required this.otherLabel,
    required this.changes,
  });

  factory _SourceTreeDiff.compare({
    required ProjectSourceTree selected,
    required ProjectSourceTree other,
    required String otherLabel,
  }) {
    if (selected.projectId.toLowerCase() != other.projectId.toLowerCase() ||
        selected.versionId == other.versionId) {
      throw const FormatException('Source comparison identity mismatch.');
    }
    final selectedByPath = <String, ProjectSourceEntry>{
      for (final file in selected.files) file.path: file,
    };
    final otherByPath = <String, ProjectSourceEntry>{
      for (final file in other.files) file.path: file,
    };
    final paths = <String>{...selectedByPath.keys, ...otherByPath.keys}.toList()
      ..sort();
    final changes = <_SourceTreeChange>[];
    for (final path in paths) {
      final selectedFile = selectedByPath[path];
      final otherFile = otherByPath[path];
      if (selectedFile == null) {
        changes.add(
          _SourceTreeChange(
            path: path,
            status: _SourceTreeChangeStatus.removed,
          ),
        );
      } else if (otherFile == null) {
        changes.add(
          _SourceTreeChange(
            path: path,
            status: _SourceTreeChangeStatus.added,
          ),
        );
      } else if (selectedFile.sha256 != otherFile.sha256) {
        changes.add(
          _SourceTreeChange(
            path: path,
            status: _SourceTreeChangeStatus.modified,
          ),
        );
      }
    }
    return _SourceTreeDiff(
      otherVersionId: other.versionId,
      otherLabel: otherLabel,
      changes: List<_SourceTreeChange>.unmodifiable(changes),
    );
  }

  final String otherVersionId;
  final String otherLabel;
  final List<_SourceTreeChange> changes;
}

class _SourceDiffCard extends StatelessWidget {
  const _SourceDiffCard({required this.diff});

  final _SourceTreeDiff diff;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          border: Border.all(color: PandoraV2Colors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compared with ${diff.otherLabel}',
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(diff.otherVersionId, style: pandoraV2Muted),
            const SizedBox(height: 10),
            if (diff.changes.isEmpty)
              const Text('No file digest changes.', style: pandoraV2Muted)
            else
              for (final change in diff.changes.take(100))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${change.label} · ${change.path}',
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            if (diff.changes.length > 100)
              Text(
                '${diff.changes.length - 100} more changes not shown.',
                style: pandoraV2Muted,
              ),
          ],
        ),
      );
}
