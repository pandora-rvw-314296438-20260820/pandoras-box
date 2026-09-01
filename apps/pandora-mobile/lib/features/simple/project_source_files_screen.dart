
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
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
  State<ProjectSourceFilesScreen> createState() => _ProjectSourceFilesScreenState();
}

class _ProjectSourceFilesScreenState extends State<ProjectSourceFilesScreen> {
  final _search = TextEditingController();
  ProjectSourceTree? _tree;
  ProjectSourceSearchResult? _searchResult;
  String? _error;
  bool _loading = true;
  bool _searching = false;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tree == null && _loading) unawaited(_loadTree());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ProjectExperienceApi? get _api =>
      PandoraDependencies.of(context).projectExperience;

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
        versionId: widget.versionId,
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
        versionId: widget.versionId,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
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
        versionId: widget.versionId,
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
        versionId: widget.versionId,
      );
      final safeProject = widget.project.projectKey
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final saved = await PandoraNativeIo.saveBinaryDocument(
        name: '${safeProject.isEmpty ? 'pandora-project' : safeProject}-${widget.versionId}.zip',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
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
              Text(
                'Exact source · ${widget.versionId}',
                style: pandoraV2Muted,
              ),
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
                        final entry = tree.files
                            .where((file) => file.path == match.path)
                            .firstOrNull;
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
