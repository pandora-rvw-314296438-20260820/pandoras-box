import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/models/project_source_models.dart';
import '../../core/platform/pandora_native_io.dart';
import 'pandora_v2_ui.dart';

const _syntaxPreviewLimit = 128 * 1024;

class ProjectSourceFilesScreen extends StatefulWidget {
  const ProjectSourceFilesScreen({
    super.key,
    required this.project,
    required this.versionId,
  });

  final CustomerProject project;
  final String versionId;

  @override
  State<ProjectSourceFilesScreen> createState() => _ProjectSourceFilesScreenState();
}

class _ProjectSourceFilesScreenState extends State<ProjectSourceFilesScreen> {
  final _search = TextEditingController();
  ProjectSourceTree? _tree;
  ProjectSourceSearchResult? _searchResult;
  List<_Version> _versions = const [];
  late String _selectedVersionId;
  String _folderPath = '';
  String? _error;
  bool _started = false;
  bool _loading = true;
  bool _versionsLoading = true;
  bool _searching = false;
  bool _exporting = false;
  bool _comparing = false;

  ProjectExperienceApi? get _api =>
      PandoraDependencies.of(context).projectExperience;

  @override
  void initState() {
    super.initState();
    _selectedVersionId = widget.versionId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(Future.wait([_loadVersions(), _loadTree(versionId: _selectedVersionId)]));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    final api = _api;
    if (api == null) {
      if (mounted) setState(() => _versionsLoading = false);
      return;
    }
    try {
      final items = await api.loadProjectConversation(
        projectId: widget.project.id,
        limit: 100,
      );
      final dates = <String, DateTime>{};
      for (final item in items) {
        final id = item.projectVersionId?.trim();
        if (id == null || id.isEmpty) continue;
        final previous = dates[id];
        if (previous == null || item.occurredAt.isAfter(previous)) {
          dates[id] = item.occurredAt;
        }
      }
      dates.putIfAbsent(widget.versionId, () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      final versions = dates.entries
          .map((e) => _Version(e.key, e.value, e.key == widget.versionId))
          .toList()
        ..sort((a, b) {
          if (a.current != b.current) return a.current ? -1 : 1;
          return b.at.compareTo(a.at);
        });
      if (!mounted) return;
      setState(() {
        _versions = List.unmodifiable(versions);
        _versionsLoading = false;
      });
    } on ProjectExperienceException {
      if (!mounted) return;
      setState(() {
        _versions = [
          _Version(
            widget.versionId,
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            true,
          ),
        ];
        _versionsLoading = false;
      });
    }
  }

  Future<void> _loadTree({required String versionId}) async {
    final api = _api;
    final requestedVersionId = versionId.trim();
    if (api == null || requestedVersionId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Pandora cannot open source files right now.';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tree = await api.loadSourceTree(
        projectId: widget.project.id,
        versionId: requestedVersionId,
      );
      if (!mounted || requestedVersionId != _selectedVersionId) return;
      setState(() {
        _tree = tree;
        _loading = false;
      });
    } on ProjectExperienceException catch (error) {
      if (!mounted || requestedVersionId != _selectedVersionId) return;
      setState(() {
        _tree = null;
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _selectVersion(String id) async {
    if (id == _selectedVersionId) return;
    setState(() {
      _selectedVersionId = id;
      _folderPath = '';
      _tree = null;
      _searchResult = null;
      _search.clear();
    });
    await _loadTree(versionId: id);
  }

  Future<void> _openFile(ProjectSourceEntry entry) async {
    final api = _api;
    if (api == null) return;
    final versionId = _selectedVersionId;
    try {
      final file = await api.loadSourceFile(
        projectId: widget.project.id,
        versionId: versionId,
        path: entry.path,
      );
      if (!mounted || versionId != _selectedVersionId) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: PandoraV2Colors.surface,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .9,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text('${_language(file.path)} · ${file.byteSize} bytes',
                                style: pandoraV2Muted),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy source',
                        onPressed: file.encoding == 'utf-8'
                            ? () async {
                                await Clipboard.setData(ClipboardData(text: file.content));
                                if (!sheetContext.mounted) return;
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('Displayed source copied.')),
                                );
                              }
                            : null,
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
                        message: 'Pandora removed a high-risk secret value from this view.',
                      ),
                    ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PandoraV2Colors.soft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: file.encoding == 'utf-8'
                          ? _SyntaxSourceView(path: file.path, content: file.content)
                          : Center(
                              child: Text(
                                'Binary file · ${file.byteSize} bytes',
                                style: pandoraV2Muted,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _runSearch() async {
    final api = _api;
    final query = _search.text.trim();
    if (api == null || query.length < 2 || _searching) return;
    final versionId = _selectedVersionId;
    setState(() => _searching = true);
    try {
      final result = await api.searchSourceFiles(
        projectId: widget.project.id,
        versionId: versionId,
        query: query,
      );
      if (!mounted || versionId != _selectedVersionId) return;
      setState(() {
        _searchResult = result;
        _error = null;
      });
    } on ProjectExperienceException catch (error) {
      if (mounted && versionId == _selectedVersionId) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _exportZip() async {
    final api = _api;
    if (api == null || _exporting) return;
    final versionId = _selectedVersionId;
    setState(() => _exporting = true);
    try {
      final bytes = await api.exportSourceZip(
        projectId: widget.project.id,
        versionId: versionId,
      );
      final safeProject = widget.project.projectKey
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final saved = await PandoraNativeIo.saveBinaryDocument(
        name: '${safeProject.isEmpty ? 'pandora-project' : safeProject}-$versionId.zip',
        mimeType: 'application/zip',
        bytes: bytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saved ? 'Source ZIP saved.' : 'Source ZIP export was cancelled.')),
        );
      }
    } on ProjectExperienceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _compareVersions() async {
    final api = _api;
    if (api == null || _tree == null || _comparing) return;
    final choices = _versions.where((v) => v.id != _selectedVersionId).toList();
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No earlier source version is available.')),
      );
      return;
    }
    final base = await showModalBottomSheet<_Version>(
      context: context,
      backgroundColor: PandoraV2Colors.surface,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Compare with',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Exact saved versions are compared by file path and source digest.',
                style: pandoraV2Muted,
              ),
              const SizedBox(height: 8),
              for (final version in choices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_shortVersion(version.id)),
                  subtitle: Text(_time(version.at)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(version),
                ),
            ],
          ),
        ),
      ),
    );
    if (base == null || !mounted) return;

    final currentVersionId = _selectedVersionId;
    setState(() => _comparing = true);
    try {
      final baseTree = await api.loadSourceTree(
        projectId: widget.project.id,
        versionId: base.id,
      );
      final currentTree = await api.loadSourceTree(
        projectId: widget.project.id,
        versionId: currentVersionId,
      );
      if (!mounted || currentVersionId != _selectedVersionId) return;
      await _showDiff(base, _SourceTreeDiff.between(baseTree, currentTree));
    } on ProjectExperienceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  Future<void> _showDiff(_Version base, _SourceTreeDiff diff) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: PandoraV2Colors.surface,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .82,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Version changes',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text('${_shortVersion(base.id)} → ${_shortVersion(_selectedVersionId)}',
                      style: pandoraV2Muted),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Count('Added', diff.added.length),
                      _Count('Changed', diff.changed.length),
                      _Count('Removed', diff.removed.length),
                      _Count('Unchanged', diff.unchanged),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: diff.entries.isEmpty
                        ? const Center(
                            child: Text('These versions have the same file digests.',
                                style: pandoraV2Muted),
                          )
                        : ListView(
                            children: [
                              for (final entry in diff.entries)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(entry.icon),
                                  title: Text(entry.path,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(entry.label),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final search = _searchResult;
    final folder = tree == null
        ? const _FolderView([], [])
        : _projectFolder(tree.files, _folderPath);

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
              tooltip: 'Compare versions',
              onPressed: _comparing || _versionsLoading ? null : _compareVersions,
              icon: _comparing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.difference_rounded),
            ),
          if (tree != null)
            IconButton(
              tooltip: 'Download source ZIP',
              onPressed: _exporting ? null : _exportZip,
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _loadVersions(),
              _loadTree(versionId: _selectedVersionId),
            ]);
          },
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
              const SizedBox(height: 8),
              _VersionPicker(
                selected: _selectedVersionId,
                versions: _versions,
                loading: _versionsLoading,
                onChanged: _selectVersion,
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (tree == null)
                PandoraV2InlineMessage(
                  title: 'Source access',
                  message: _error ?? 'Source files are available with source access.',
                  actionLabel: 'Try again',
                  onAction: () => unawaited(_loadTree(versionId: _selectedVersionId)),
                )
              else ...[
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
                            child: SizedBox.square(
                              dimension: 18,
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
                  const SizedBox(height: 10),
                  PandoraV2InlineMessage(
                    title: 'Source action unavailable',
                    message: _error!,
                    actionLabel: 'Dismiss',
                    onAction: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: 12),
                if (search != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${search.matches.length} matches for “${search.query}”',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _searchResult = null),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  for (final match in search.matches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.search_rounded),
                      title: Text('${match.path}:${match.line}'),
                      subtitle: Text(match.snippet,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        for (final file in tree.files) {
                          if (file.path == match.path) {
                            unawaited(_openFile(file));
                            break;
                          }
                        }
                      },
                    ),
                  if (search.truncated)
                    const Text('More matches exist. Refine your search.',
                        style: pandoraV2Muted),
                  const Divider(height: 24),
                ],
                _FolderBreadcrumbs(
                  path: _folderPath,
                  onOpen: (path) => setState(() {
                    _folderPath = path;
                    _searchResult = null;
                  }),
                ),
                Text(
                  '${folder.folders.length} folders · ${folder.files.length} files',
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final dir in folder.folders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(dir.name),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => setState(() => _folderPath = dir.path),
                  ),
                for (final file in folder.files)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(file.isText
                        ? Icons.description_outlined
                        : Icons.insert_drive_file_outlined),
                    title: Text(_basename(file.path)),
                    subtitle: Text('${file.byteSize} bytes'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openFile(file),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Version {
  const _Version(this.id, this.at, this.current);
  final String id;
  final DateTime at;
  final bool current;
}

class _VersionPicker extends StatelessWidget {
  const _VersionPicker({
    required this.selected,
    required this.versions,
    required this.loading,
    required this.onChanged,
  });

  final String selected;
  final List<_Version> versions;
  final bool loading;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator(minHeight: 2);
    final values = versions.any((v) => v.id == selected)
        ? versions
        : [_Version(selected, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), false), ...versions];
    return Row(
      children: [
        const Text('Exact source', style: pandoraV2Muted),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final version in values)
                DropdownMenuItem(
                  value: version.id,
                  child: Text(
                    version.current
                        ? 'Current · ${_shortVersion(version.id)}'
                        : _shortVersion(version.id),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ],
    );
  }
}

class _FolderBreadcrumbs extends StatelessWidget {
  const _FolderBreadcrumbs({required this.path, required this.onOpen});
  final String path;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final parts = path.isEmpty ? <String>[] : path.split('/');
    final paths = <String>[''];
    var current = '';
    for (final part in parts) {
      current = current.isEmpty ? part : '$current/$part';
      paths.add(current);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < paths.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right_rounded, size: 16),
            TextButton(
              onPressed: i == paths.length - 1 ? null : () => onOpen(paths[i]),
              child: Text(i == 0 ? 'Files' : _basename(paths[i])),
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderView {
  const _FolderView(this.folders, this.files);
  final List<_Folder> folders;
  final List<ProjectSourceEntry> files;
}

class _Folder {
  const _Folder(this.name, this.path);
  final String name;
  final String path;
}

_FolderView _projectFolder(List<ProjectSourceEntry> files, String folderPath) {
  final prefix = folderPath.isEmpty ? '' : '$folderPath/';
  final folders = <String, _Folder>{};
  final direct = <ProjectSourceEntry>[];
  for (final file in files) {
    if (!file.path.startsWith(prefix)) continue;
    final relativePath = file.path.substring(prefix.length);
    final parts = relativePath.split('/');
    if (parts.length == 1) {
      direct.add(file);
    } else {
      final name = parts.first;
      folders.putIfAbsent(
        name,
        () => _Folder(name, folderPath.isEmpty ? name : '$folderPath/$name'),
      );
    }
  }
  final dirs = folders.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  direct.sort((a, b) => a.path.compareTo(b.path));
  return _FolderView(List.unmodifiable(dirs), List.unmodifiable(direct));
}

class _SourceTreeDiff {
  const _SourceTreeDiff(this.added, this.changed, this.removed, this.unchanged);

  factory _SourceTreeDiff.between(ProjectSourceTree base, ProjectSourceTree current) {
    final baseByPath = {for (final entry in base.files) entry.path: entry};
    final currentByPath = {for (final entry in current.files) entry.path: entry};
    final added = <String>[];
    final changed = <String>[];
    final removed = <String>[];
    var unchanged = 0;
    for (final entry in current.files) {
      final prior = baseByPath[entry.path];
      if (prior == null) {
        added.add(entry.path);
      } else if (prior.sha256 != entry.sha256) {
        changed.add(entry.path);
      } else {
        unchanged++;
      }
    }
    for (final entry in base.files) {
      if (!currentByPath.containsKey(entry.path)) removed.add(entry.path);
    }
    added.sort();
    changed.sort();
    removed.sort();
    return _SourceTreeDiff(
      List.unmodifiable(added),
      List.unmodifiable(changed),
      List.unmodifiable(removed),
      unchanged,
    );
  }

  final List<String> added;
  final List<String> changed;
  final List<String> removed;
  final int unchanged;

  List<_DiffEntry> get entries => [
        for (final path in added) _DiffEntry(path, 'Added', Icons.add_circle_outline_rounded),
        for (final path in changed) _DiffEntry(path, 'Changed', Icons.change_circle_outlined),
        for (final path in removed) _DiffEntry(path, 'Removed', Icons.remove_circle_outline_rounded),
      ];
}

class _DiffEntry {
  const _DiffEntry(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label $count'));
}

class _SyntaxSourceView extends StatelessWidget {
  const _SyntaxSourceView({required this.path, required this.content});
  final String path;
  final String content;

  @override
  Widget build(BuildContext context) {
    final truncated = content.length > _syntaxPreviewLimit;
    final visible = truncated ? content.substring(0, _syntaxPreviewLimit) : content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (truncated)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Large source preview is limited to 128 KiB. Copy still uses the exact returned source.',
              style: pandoraV2Muted,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText.rich(
              TextSpan(children: _highlight(visible, _sourceLanguage(path))),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: PandoraV2Colors.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<TextSpan> _highlight(String source, String language) {
  final keywords = _languageKeywords(language);
  if (keywords.isEmpty) return [TextSpan(text: source)];
  final pattern = RegExp(
    '\\b(?:${keywords.map(RegExp.escape).join('|')})\\b|\\b\\d+(?:\\.\\d+)?\\b',
  );
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: source.substring(cursor, match.start)));
    }
    final token = match.group(0) ?? '';
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(
          color: keywords.contains(token)
              ? const Color(0xFF245D9C)
              : const Color(0xFF7B4BA3),
          fontWeight: keywords.contains(token) ? FontWeight.w700 : null,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < source.length) spans.add(TextSpan(text: source.substring(cursor)));
  return spans;
}

String _sourceLanguage(String path) => _language(path);

String _language(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.dart')) return 'Dart';
  if (p.endsWith('.ts') || p.endsWith('.tsx')) return 'TypeScript';
  if (p.endsWith('.js') || p.endsWith('.jsx') || p.endsWith('.mjs')) return 'JavaScript';
  if (p.endsWith('.sql')) return 'SQL';
  if (p.endsWith('.py')) return 'Python';
  if (p.endsWith('.json')) return 'JSON';
  if (p.endsWith('.html')) return 'HTML';
  if (p.endsWith('.css')) return 'CSS';
  if (p.endsWith('.yaml') || p.endsWith('.yml')) return 'YAML';
  if (p.endsWith('.md') || p.endsWith('.mdx')) return 'Markdown';
  if (p.endsWith('.sh')) return 'Shell';
  return 'Text';
}

Set<String> _languageKeywords(String language) {
  switch (language) {
    case 'Dart':
      return const {'class', 'const', 'final', 'var', 'void', 'async', 'await', 'if', 'else', 'for', 'return', 'import', 'extends'};
    case 'TypeScript':
    case 'JavaScript':
      return const {'const', 'let', 'var', 'function', 'class', 'async', 'await', 'if', 'else', 'for', 'return', 'import', 'export'};
    case 'SQL':
      return const {'select', 'from', 'where', 'insert', 'update', 'delete', 'create', 'alter', 'grant', 'revoke', 'table'};
    case 'Python':
      return const {'def', 'class', 'if', 'elif', 'else', 'for', 'return', 'import', 'from', 'async', 'await'};
    case 'JSON':
      return const {'true', 'false', 'null'};
    default:
      return const {};
  }
}

String _basename(String path) => path.split('/').last;

String _shortVersion(String id) =>
    id.length <= 12 ? id : '${id.substring(0, 8)}…${id.substring(id.length - 4)}';

String _time(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return 'Saved source version';
  final v = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${v.year}-${two(v.month)}-${two(v.day)} ${two(v.hour)}:${two(v.minute)} UTC';
}
