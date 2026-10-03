import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/pandora_core_api.dart';
import '../../core/data/pandora_enterprise_api.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../team/team_screen.dart';

const _canvas = Color(0xFF090C10);
const _surface = Color(0xFF131920);
const _muted = Color(0xFF9CA8B5);
const _ink = Color(0xFFF4F6F8);

/// The common customer operating surface, embedded in Pandora's existing shell.
/// All data and commands carry the same explicit organization and entry receipt.
class PandoraEnterpriseWorkspaceScreen extends StatefulWidget {
  const PandoraEnterpriseWorkspaceScreen({
    super.key,
    required this.gateway,
    required this.organizationId,
    this.entryId,
    this.section = 'overview',
    this.onNavigate,
    this.onContextChanged,
    this.onPendingWorkChanged,
  });
  final PandoraEnterpriseGateway gateway;
  final String organizationId;
  final String? entryId;
  final String section;
  final ValueChanged<String>? onNavigate;
  final ValueChanged<PandoraCoreRecord>? onContextChanged;
  final ValueChanged<bool>? onPendingWorkChanged;

  @override
  State<PandoraEnterpriseWorkspaceScreen> createState() =>
      _PandoraEnterpriseWorkspaceScreenState();
}

class _PandoraEnterpriseWorkspaceScreenState
    extends State<PandoraEnterpriseWorkspaceScreen> {
  PandoraCoreRecord? _snapshot;
  PandoraCoreFailure? _failure;
  bool _loading = false;
  bool _editing = false;
  bool _teamVisible = false;
  int _generation = 0;
  late String _section;

  static const _sections = <String, String>{
    'overview': 'Overview',
    'work': 'Work',
    'documents': 'Documents',
    'activity': 'Activity',
    'people': 'People',
  };

  @override
  void initState() {
    super.initState();
    _section =
        _sections.containsKey(widget.section) ? widget.section : 'overview';
    _load();
  }

  @override
  void didUpdateWidget(covariant PandoraEnterpriseWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.entryId != widget.entryId ||
        oldWidget.section != widget.section) {
      _snapshot = null;
      _failure = null;
      _teamVisible = false;
      _section =
          _sections.containsKey(widget.section) ? widget.section : 'overview';
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  List<PandoraCoreRecord> _rows(String key) => coreRecords(_snapshot?[key]);
  bool get _canManage =>
      coreRecord(_snapshot?['permissions'])['can_manage_work'] == true;

  void _verify(
      PandoraCoreRecord value, String organizationId, String? entryId) {
    final workspace = coreRecord(value['workspace']);
    if (value['schema_version']?.toString() != '1' ||
        value['organization_id'] != organizationId ||
        workspace['organization_id'] != organizationId ||
        workspace['adapter'] != 'enterprise_core_v1' ||
        (entryId != null &&
            (value['entry_id'] != entryId ||
                value['viewing_as'] != 'pandora_administrator')) ||
        (entryId == null && value['viewing_as'] != 'member')) {
      throw const PandoraCoreFailure('SCOPE_MISMATCH',
          'Pandora could not verify this workspace. Return and check access.');
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final organizationId = widget.organizationId;
    final entryId = widget.entryId;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final value = await widget.gateway.snapshot(
          organizationId: organizationId, section: _section, entryId: entryId);
      if (!mounted || generation != _generation) return;
      _verify(value, organizationId, entryId);
      setState(() => _snapshot = value);
      widget.onContextChanged?.call({
        'organizationId': organizationId,
        'adapter': 'enterprise_core_v1',
        'section': _section,
        if (entryId != null) 'entryId': entryId,
      });
    } on PandoraCoreFailure catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = error;
        if (const {
          'ACCESS_DENIED',
          'SIGN_IN_REQUIRED',
          'SCOPE_MISMATCH',
          'INVALID_RESPONSE'
        }.contains(error.code)) {
          _snapshot = null;
          _teamVisible = false;
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failure = const PandoraCoreFailure('UNAVAILABLE',
            'The workspace could not be refreshed. Retry when connected.'));
      }
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  void _select(String section) {
    if (_section == section) return;
    widget.onNavigate?.call(section);
    setState(() {
      _section = section;
      _teamVisible = false;
    });
    _load();
  }

  Future<void> _editTask([PandoraCoreRecord? task]) async {
    if (_editing || !_canManage || (task != null && task['editable'] != true))
      return;
    final organizationId = widget.organizationId;
    final entryId = widget.entryId;
    final generation = _generation;
    _editing = true;
    final result = await showModalBottomSheet<PandoraCoreRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (_) => PandoraEnterpriseTaskForm(
        gateway: widget.gateway,
        organizationId: organizationId,
        entryId: entryId,
        task: task,
        onPendingChanged: (pending) {
          if (mounted &&
              widget.organizationId == organizationId &&
              widget.entryId == entryId) {
            widget.onPendingWorkChanged?.call(pending);
          }
        },
      ),
    );
    _editing = false;
    widget.onPendingWorkChanged?.call(false);
    if (!mounted || generation != _generation || result == null) return;
    if (result['organization_id'] != organizationId) {
      setState(() {
        _snapshot = null;
        _failure = const PandoraCoreFailure('SCOPE_MISMATCH',
            'The task response did not match this workspace. Refresh before continuing.');
      });
      return;
    }
    final evidence = coreText(result['evidence_ref'], '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Task saved and read back.'),
      action: evidence.isEmpty
          ? null
          : SnackBarAction(
              label: 'Receipt',
              onPressed: () => _detail('Task evidence', {
                    'Receipt': evidence,
                    'Outcome': 'Saved and read back',
                  })),
    ));
    await _load();
  }

  Future<void> _openDocument(PandoraCoreRecord document) async {
    final url = coreText(document['source_url'], '');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted)
        _message('The document could not be opened. Try again.');
    } catch (_) {
      if (mounted) _message('The document could not be opened. Try again.');
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void _detail(String title, Map<String, String> values,
      {VoidCallback? onOpen}) {
    showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: _surface,
        builder: (sheetContext) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 20)),
                  const SizedBox(height: 12),
                  for (final item in values.entries)
                    if (item.value.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.key,
                                    style: const TextStyle(
                                        color: _muted, fontSize: 12)),
                                SelectableText(item.value,
                                    style: const TextStyle(color: _ink)),
                              ])),
                  if (onOpen != null)
                    FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onOpen();
                        },
                        child: const Text('Open document')),
                  TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Close')),
                ]));
  }

  @override
  Widget build(BuildContext context) {
    final workspace = coreRecord(_snapshot?['workspace']);
    return PopScope<void>(
        canPop: !_teamVisible,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _teamVisible) setState(() => _teamVisible = false);
        },
        child: Material(
            color: _canvas,
            child: SafeArea(
                bottom: false,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                          child: Row(children: [
                            if (_teamVisible)
                              IconButton(
                                  tooltip: 'Back',
                                  onPressed: () =>
                                      setState(() => _teamVisible = false),
                                  icon: const Icon(Icons.arrow_back_rounded))
                            else if (PandoraNavigationScope.maybeOf(context)
                                    ?.openDrawer !=
                                null)
                              PandoraMenuButton(
                                  onPressed:
                                      PandoraNavigationScope.maybeOf(context)!
                                          .openDrawer!),
                            Expanded(
                                child: Text(
                                    _teamVisible
                                        ? 'Team & Access'
                                        : coreText(workspace['display_name'],
                                            'Enterprise workspace'),
                                    style: const TextStyle(
                                        color: _ink,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)),
                            IconButton(
                                key: const ValueKey('enterprise-refresh'),
                                tooltip: 'Refresh workspace',
                                onPressed: _loading ? null : _load,
                                icon: const Icon(Icons.refresh_rounded)),
                          ])),
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                          child: _teamVisible
                              ? TeamScreen(
                                  organizationId: widget.organizationId)
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                    key: const ValueKey('enterprise-scroll'),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                        18, 8, 18, 24),
                                    children: [
                                      if (_failure != null)
                                        _EnterpriseNotice(
                                            title: _snapshot == null
                                                ? 'Workspace unavailable'
                                                : 'Last loaded state',
                                            message: _failure!.message,
                                            onRetry: _load),
                                      if (_snapshot != null) ...[
                                        SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(children: [
                                              for (final section
                                                  in _sections.entries)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 7),
                                                    child: ChoiceChip(
                                                        key: ValueKey(
                                                            'enterprise-section-${section.key}'),
                                                        label:
                                                            Text(section.value),
                                                        selected: _section ==
                                                            section.key,
                                                        onSelected: (_) =>
                                                            _select(
                                                                section.key))),
                                            ])),
                                        const SizedBox(height: 16),
                                        ..._body(),
                                      ],
                                    ],
                                  ))),
                    ]))));
  }

  List<Widget> _body() {
    final tasks = _rows('tasks');
    final counts = coreRecord(_snapshot?['counts']);
    return switch (_section) {
      'overview' => [
          Wrap(spacing: 24, runSpacing: 10, children: [
            _Count('Open work', counts['open_tasks']),
            _Count('Overdue', counts['overdue_tasks']),
            _Count('Documents', counts['documents']),
          ]),
          const SizedBox(height: 18),
          if (_canManage) _createButton(),
          const _SectionTitle('Work needing attention'),
          if (tasks
              .where(
                  (t) => t['state'] != 'completed' && t['state'] != 'cancelled')
              .isEmpty)
            const _EmptyWorkspace(
                'No open work. Add a task when there is something to do.')
          else
            for (final task in tasks
                .where((t) =>
                    t['state'] != 'completed' && t['state'] != 'cancelled')
                .take(8))
              _taskRow(task),
          const _SectionTitle('Recent outcomes'),
          ..._activityRows(limit: 5),
        ],
      'work' => [
          if (_canManage) _createButton(),
          if (tasks.isEmpty)
            const _EmptyWorkspace('No tasks yet.')
          else
            for (final task in tasks) _taskRow(task),
        ],
      'documents' => [
          if (_rows('documents').isEmpty)
            const _EmptyWorkspace(
                'No linked documents yet. Ask your administrator to connect a document source.'),
          for (final doc in _rows('documents'))
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(coreText(doc['title'], 'Document')),
                subtitle: Text(coreText(doc['source_name'], 'Linked document')),
                onTap: () => _detail(
                    coreText(doc['title'], 'Document'),
                    {
                      'Type': coreText(doc['document_type'], ''),
                      'Source': coreText(doc['source_name'], ''),
                      'Version': coreText(doc['version_number'], ''),
                      'Observed': _date(doc['source_observed_at']),
                      'Content evidence': coreText(doc['content_sha256'], ''),
                    },
                    onOpen: coreText(doc['source_url'], '').isEmpty
                        ? null
                        : () => _openDocument(doc))),
          const _SectionTitle('Sources'),
          if (_rows('sources').isEmpty)
            const _EmptyWorkspace('No document sources connected.'),
          for (final source in _rows('sources'))
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(coreText(source['name'], 'Source')),
                subtitle: Text(coreText(source['status'], 'Unknown'))),
        ],
      'activity' => _activityRows(),
      'people' => [
          if (const {'owner', 'admin'}.contains(_snapshot?['actor_role']))
            Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                    key: const ValueKey('enterprise-manage-team'),
                    onPressed: () => setState(() => _teamVisible = true),
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Manage Team & Access'))),
          if (_rows('people').isEmpty)
            const _EmptyWorkspace('No active team members are visible.'),
          for (final person in _rows('people'))
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(coreText(person['display_name'], 'Team member')),
                subtitle: Text(coreText(person['role'], 'Member'))),
        ],
      _ => const <Widget>[],
    };
  }

  Widget _createButton() => Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
          key: const ValueKey('enterprise-add-task'),
          onPressed: _editing ? null : () => _editTask(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add task')));

  Widget _taskRow(PandoraCoreRecord task) => ListTile(
      key: ValueKey('enterprise-task-${task['id']}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(task['state'] == 'completed'
          ? Icons.check_circle_outline_rounded
          : Icons.radio_button_unchecked_rounded),
      title: Text(coreText(task['title'], 'Task'),
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        _stateLabel(task['state']),
        if (task['due_at'] != null) 'Due ${_date(task['due_at'])}'
      ].join(' · ')),
      onTap: _canManage && task['editable'] == true
          ? () => _editTask(task)
          : () => _detail(coreText(task['title'], 'Task'), {
                'Details': coreText(task['description'], ''),
                'State': _stateLabel(task['state']),
                'Due': _date(task['due_at']),
              }));

  List<Widget> _activityRows({int limit = 100}) => _rows('activity').isEmpty
      ? const [_EmptyWorkspace('No recorded activity yet.')]
      : [
          for (final item in _rows('activity').take(limit))
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(coreText(item['title'], 'Recorded activity')),
                subtitle: Text(_date(item['occurred_at'])),
                onTap: () =>
                    _detail(coreText(item['title'], 'Recorded activity'), {
                      'Outcome': coreText(item['summary'], ''),
                      'Source': coreText(item['source'], ''),
                      'When': _date(item['occurred_at']),
                    }))
        ];
}

class PandoraEnterpriseTaskForm extends StatefulWidget {
  const PandoraEnterpriseTaskForm(
      {super.key,
      required this.gateway,
      required this.organizationId,
      this.entryId,
      this.task,
      this.onPendingChanged});
  final PandoraEnterpriseGateway gateway;
  final String organizationId;
  final String? entryId;
  final PandoraCoreRecord? task;
  final ValueChanged<bool>? onPendingChanged;
  @override
  State<PandoraEnterpriseTaskForm> createState() =>
      _PandoraEnterpriseTaskFormState();
}

class _PandoraEnterpriseTaskFormState extends State<PandoraEnterpriseTaskForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _state;
  DateTime? _due;
  bool _dueChanged = false;
  bool _saving = false;
  String? _failure;
  final String _key = newCoreIdempotencyKey();
  PandoraCoreRecord? _submitted;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: coreText(widget.task?['title'], ''));
    _description =
        TextEditingController(text: coreText(widget.task?['description'], ''));
    _state = coreText(widget.task?['state'], 'open');
    _due = DateTime.tryParse(coreText(widget.task?['due_at'], ''))?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _due ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (!mounted || date == null) return;
    final time = await showTimePicker(
        context: context,
        initialTime:
            _due == null ? TimeOfDay.now() : TimeOfDay.fromDateTime(_due!));
    if (!mounted || time == null) return;
    setState(() {
      _due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _dueChanged = true;
    });
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final updating = widget.task != null;
    final payload = _submitted ??
        <String, dynamic>{
          'title': _title.text.trim(),
          'description': _description.text.trim(),
          if (updating) 'id': widget.task!['id'],
          if (updating) 'expected_updated_at': widget.task!['updated_at'],
          if (updating) 'state': _state,
          if (_due != null) 'due_at': _due!.toUtc().toIso8601String(),
          if (updating && _dueChanged && _due == null) 'due_at': null,
        };
    setState(() {
      _saving = true;
      _failure = null;
      _submitted = payload;
    });
    widget.onPendingChanged?.call(true);
    try {
      final result = await widget.gateway.operate(
          organizationId: widget.organizationId,
          entryId: widget.entryId,
          operation: updating ? 'task.update' : 'task.create',
          payload: payload,
          idempotencyKey: _key);
      if (!mounted) return;
      final task = coreRecord(result['task']);
      if (result['organization_id'] != widget.organizationId ||
          coreText(task['id'], '').isEmpty ||
          coreText(result['receipt_id'], '').isEmpty ||
          (updating && task['id'] != widget.task!['id'])) {
        throw const PandoraCoreFailure('SCOPE_MISMATCH',
            'Pandora could not verify the saved task. Refresh before continuing.');
      }
      Navigator.pop(context, result);
    } on PandoraCoreFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.code == 'CONFLICT'
            ? 'This task changed. Close and refresh before editing it again.'
            : error.message;
        if (error.code == 'INVALID_REQUEST') _submitted = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _failure =
            'The result is not confirmed. Retry keeps the same request to avoid a duplicate.');
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.onPendingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
      canPop: !_saving,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .88),
          child: Form(
              key: _form,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(widget.task == null ? 'Add task' : 'Update task',
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 21)),
                  const SizedBox(height: 16),
                  TextFormField(
                      key: const ValueKey('enterprise-task-title'),
                      controller: _title,
                      enabled: !_saving && _submitted == null,
                      maxLength: 160,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter a title.'
                          : null),
                  TextFormField(
                      key: const ValueKey('enterprise-task-description'),
                      controller: _description,
                      enabled: !_saving && _submitted == null,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Details')),
                  if (widget.task != null)
                    DropdownButtonFormField<String>(
                        key: const ValueKey('enterprise-task-state'),
                        initialValue: _state,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'State'),
                        items: [
                          for (final state in const [
                            'open',
                            'in_progress',
                            'blocked',
                            'completed',
                            'cancelled'
                          ])
                            DropdownMenuItem(
                                value: state, child: Text(_stateLabel(state)))
                        ],
                        onChanged: _saving || _submitted != null
                            ? null
                            : (value) =>
                                setState(() => _state = value ?? _state)),
                  const SizedBox(height: 10),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(_due == null
                          ? 'No due date'
                          : 'Due ${_date(_due!.toIso8601String())}'),
                      subtitle: const Text('Your local time'),
                      onTap: _saving || _submitted != null ? null : _pickDue,
                      trailing: _due == null
                          ? null
                          : IconButton(
                              tooltip: 'Clear due date',
                              onPressed: _saving || _submitted != null
                                  ? null
                                  : () => setState(() {
                                        _due = null;
                                        _dueChanged = true;
                                      }),
                              icon: const Icon(Icons.close_rounded))),
                  if (_failure != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_failure!,
                            style: const TextStyle(color: Color(0xFFFFC58A)))),
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            child:
                                Text(_submitted == null ? 'Cancel' : 'Close')),
                        FilledButton(
                            key: const ValueKey('enterprise-task-save'),
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save task'))
                      ]),
                ],
              )),
        ),
      ));
}

String _date(Object? value) {
  final date = DateTime.tryParse(coreText(value, ''))?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _stateLabel(Object? value) => switch (value) {
      'in_progress' => 'In progress',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      'blocked' => 'Blocked',
      'open' => 'Open',
      _ => coreText(value, 'Unknown')
    };

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: const TextStyle(color: _muted, height: 1.4)));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: _ink, fontWeight: FontWeight.w700, fontSize: 16)));
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(coreText(value, '—'),
            style: const TextStyle(
                color: _ink, fontWeight: FontWeight.w700, fontSize: 22)),
        Text(label, style: const TextStyle(color: _muted, fontSize: 12))
      ]);
}

class _EnterpriseNotice extends StatelessWidget {
  const _EnterpriseNotice(
      {required this.title, required this.message, required this.onRetry});
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(message, style: const TextStyle(color: _muted)),
        TextButton(onPressed: onRetry, child: const Text('Retry'))
      ]));
}
