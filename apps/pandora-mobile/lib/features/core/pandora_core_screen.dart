import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_core_api.dart';
import '../../core/data/pandora_user_admin_api.dart';
import '../../core/security/pandora_auth.dart';
import '../../core/security/pandora_identity_verification.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../approvals/approvals_screen.dart';
import '../enterprise/plp_editorial_surfaces.dart';
import '../team/team_screen.dart';
import 'pandora_core_memory_panel.dart';

const _ink = Color(0xFFF2F2F2);
const _muted = Color(0xFFA0A3A8);
const _surface = Color(0xFF121519);
const _line = Color(0xFF292D32);

/// A single operational projection of Pandora Core. The same signed-in RPC
/// contract powers Home, client administration and the deeper owner sections.
/// Cached shell roots retain state, but only the visible business page owns
/// system Back. A conversation overlay or another root cannot pop this page.
class PandoraCoreRouteVisibility extends InheritedWidget {
  const PandoraCoreRouteVisibility({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PandoraCoreRouteVisibility>()
          ?.active ??
      true;

  @override
  bool updateShouldNotify(PandoraCoreRouteVisibility oldWidget) =>
      active != oldWidget.active;
}

class PandoraCoreScreen extends StatefulWidget {
  const PandoraCoreScreen({
    super.key,
    required this.gateway,
    this.section = 'home',
    this.organizationId,
    this.onHome,
    this.onNavigate,
    this.onEnterClient,
    this.onContextChanged,
    this.initialAction,
    this.teamGateway,
  });

  final PandoraCoreGateway gateway;
  final String section;
  final String? organizationId;
  final VoidCallback? onHome;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function(PandoraCoreRecord client)? onEnterClient;
  final ValueChanged<PandoraCoreRecord>? onContextChanged;
  final String? initialAction;
  final PandoraUserAdminGateway? teamGateway;

  @override
  State<PandoraCoreScreen> createState() => _PandoraCoreScreenState();
}

class _PandoraCoreScreenState extends State<PandoraCoreScreen> {
  PandoraCoreRecord? _snapshot;
  PandoraCoreFailure? _failure;
  bool _loading = false;
  bool _acting = false;
  bool _initialActionOpened = false;
  bool _decisionQueue = false;
  bool _modelDetails = false;
  String _toolTitle = 'Team & Access';
  int _generation = 0;
  String? _clientId;
  String _tab = '';
  Widget? _tool;
  String _query = '';
  final _search = TextEditingController();

  String get _section => _clientId == null ? widget.section : 'client';
  PandoraCoreRecord get _client => coreRecord(_snapshot?['client']);
  String get _title => _decisionQueue && _clientId == null
      ? 'Needs You'
      : switch (_section) {
          'home' => 'Pandora',
          'clients' => 'Clients',
          'client' => coreText(_client['display_name'], 'Manage client'),
          'business' => 'Business',
          'platform' => 'Platform',
          'administration' => 'Administration',
          _ => 'Pandora',
        };

  @override
  void initState() {
    super.initState();
    _clientId = widget.organizationId;
    _decisionQueue = widget.initialAction == 'needs_you';
    _load();
  }

  @override
  void didUpdateWidget(covariant PandoraCoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.organizationId != widget.organizationId ||
        oldWidget.gateway != widget.gateway) {
      _clientId = widget.organizationId;
      _tab = '';
      _tool = null;
      _snapshot = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final section = _section;
    final organizationId = _clientId;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final value = await widget.gateway.snapshot(
        section,
        organizationId: organizationId,
      );
      if (!mounted || generation != _generation) return;
      if (organizationId != null &&
          coreText(coreRecord(value['client'])['organization_id'], '') !=
              organizationId) {
        throw const PandoraCoreFailure(
          'SCOPE_MISMATCH',
          'Pandora could not verify this client. Return to Clients and refresh.',
        );
      }
      setState(() => _snapshot = value);
      widget.onContextChanged?.call({
        'coreSection': section,
        if (organizationId != null) 'organizationId': organizationId,
      });
      if (!_initialActionOpened && widget.initialAction != null) {
        _initialActionOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          if (widget.initialAction == 'create_client') {
            _registerClient();
          } else if (widget.initialAction == 'prepare_proposal') {
            _prospectForm(initial: const {'stage': 'proposal'});
          } else if (widget.initialAction == 'manage_users' &&
              _clientId != null) {
            _openTeam(_clientId!);
          }
        });
      }
    } on PandoraCoreFailure catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failure = error;
          if (const {'ACCESS_DENIED', 'SIGN_IN_REQUIRED', 'SCOPE_MISMATCH'}
              .contains(error.code)) {
            _snapshot = null;
            _tool = null;
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failure = const PandoraCoreFailure(
              'UNAVAILABLE',
              'Pandora could not load this view. Check your connection and retry.',
            ));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _openClient(PandoraCoreRecord client) {
    final id = coreText(client['organization_id'], '');
    if (id.isEmpty) return;
    widget.onContextChanged
        ?.call({'coreSection': 'client', 'organizationId': id});
    setState(() {
      _clientId = id;
      _tab = '';
      _snapshot = null;
      _tool = null;
    });
    _load();
  }

  void _back() {
    if (_tool != null) {
      setState(() => _tool = null);
      _load();
    } else if (_clientId != null && widget.organizationId == null) {
      widget.onContextChanged?.call({'coreSection': widget.section});
      setState(() {
        _clientId = null;
        _tab = '';
        _snapshot = null;
      });
      _load();
    } else {
      widget.onHome?.call();
    }
  }

  Future<void> _enter(PandoraCoreRecord client) async {
    if (_acting || widget.onEnterClient == null) return;
    setState(() => _acting = true);
    try {
      await widget.onEnterClient!(client);
    } on PandoraCoreFailure catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('Pandora could not verify client access. Try again.');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(value)));

  String _organizationName(String? organizationId) {
    if (organizationId == null ||
        organizationId ==
            coreRecord(_snapshot?['operator'])['platform_organization_id']) {
      return 'Pandora';
    }
    if (_client['organization_id'] == organizationId) {
      return coreText(_client['display_name'], 'Organization $organizationId');
    }
    for (final client in _rows('clients')) {
      if (client['organization_id'] == organizationId) {
        return coreText(client['display_name'], 'Organization $organizationId');
      }
    }
    return 'Organization $organizationId';
  }

  void _openTeam(String organizationId) => setState(() {
        _tool = TeamScreen(
          gateway: widget.teamGateway,
          organizationId: organizationId,
          organizationName: _organizationName(organizationId),
          embedded: true,
        );
      });

  Future<void> _form(
    String operation,
    String title,
    List<CoreFormField> fields, {
    String? organizationId,
    PandoraCoreRecord initial = const {},
    String submitLabel = 'Save',
    bool financial = false,
    String? notice,
    String? successMessage,
  }) async {
    final result = await showModalBottomSheet<PandoraCoreRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (_) => PandoraCoreOperationForm(
        gateway: widget.gateway,
        operation: operation,
        title: title,
        fields: fields,
        organizationId: organizationId,
        initial: initial,
        submitLabel: submitLabel,
        financial: financial,
        notice: notice,
        scopeLabel: _organizationName(organizationId),
        identity:
            context.getInheritedWidgetOfExactType<PandoraDependencies>()?.auth,
      ),
    );
    if (!mounted || result == null) return;
    _message(successMessage ??
        coreText(result['next_action'], 'Saved. Current state refreshed.'));
    final created = coreText(result['organization_id'], '');
    if (operation == 'client.register' && created.isNotEmpty) {
      setState(() {
        _clientId = created;
        _tab = 'Onboarding';
        _snapshot = null;
      });
    }
    await _load();
  }

  Future<void> _requestWorkspaceAccess(String organizationId) => _form(
        'access.request',
        'Request workspace access',
        const [
          CoreFormField('reason', 'Reason', required: true, multiline: true),
        ],
        organizationId: organizationId,
        submitLabel: 'Request access',
        notice: 'Scope: ${_organizationName(organizationId)}. '
            'This request needs review; it does not grant workspace access.',
        successMessage: 'Workspace access request pending review.',
      );

  Future<void> _registerClient() => _form(
        'client.register',
        'Add Enterprise Client',
        [
          const CoreFormField('name', 'Business name', required: true),
          const CoreFormField('slug', 'Short name', required: true),
          const CoreFormField('industry', 'Industry', required: true, options: {
            'custom': 'General business',
            'hospitality': 'Hospitality',
            'trade': 'Import / export',
            'legal': 'Law / professional services',
            'restaurant': 'Restaurant',
            'retail': 'Retail',
          }),
          const CoreFormField('workspace_type', 'Workspace type', options: {
            'generic': 'General business',
            'plp': 'Resort / hospitality',
            'eurofish': 'Import / export',
            'batalla': 'Law / professional services',
            'bok': 'Restaurant / hospitality group',
          }),
          const CoreFormField('primary_contact_name', 'Primary contact'),
          const CoreFormField('primary_contact_email', 'Contact email',
              email: true),
          if (coreRecords(_snapshot?['plans']).isNotEmpty)
            CoreFormField(
              'plan_id',
              'Plan',
              options: {
                '': 'Choose later',
                for (final plan in coreRecords(_snapshot?['plans']))
                  coreText(plan['id'], ''): coreText(plan['name']),
              },
            ),
        ],
        submitLabel: 'Create client',
      );

  List<PandoraCoreRecord> _rows(String key) => coreRecords(_snapshot?[key]);

  @override
  Widget build(BuildContext context) {
    final navigationActive = PandoraCoreRouteVisibility.isActive(context);
    final canGoBack =
        _tool != null || (_clientId != null && widget.organizationId == null);
    final content = _tool ??
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const ValueKey('core-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_failure != null)
                _Notice(
                  title: _snapshot == null
                      ? 'This view is unavailable'
                      : 'Showing the last loaded state',
                  message: _failure!.message,
                  action: 'Retry',
                  onAction: _loading ? null : _load,
                ),
              if (_snapshot == null && !_loading && _failure == null)
                const _Notice(
                    title: 'No verified state yet',
                    message: 'Refresh to load Pandora’s current state.'),
              if (_snapshot != null) ..._body(),
            ],
          ),
        );
    return PopScope<void>(
      canPop: !navigationActive || !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && navigationActive && canGoBack) _back();
      },
      child: Material(
        color: _editorialSurface ? plpCanvas : const Color(0xFF090B0E),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                child: Row(
                  children: [
                    if (canGoBack)
                      IconButton(
                        key: const ValueKey('core-back'),
                        tooltip: 'Back',
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    else if (PandoraNavigationScope.maybeOf(context)
                            ?.openDrawer !=
                        null)
                      PandoraMenuButton(
                        onPressed: PandoraNavigationScope.maybeOf(context)!
                            .openDrawer!,
                      )
                    else
                      const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _tool != null
                            ? (_tool is TeamScreen
                                ? 'Team & Access'
                                : _toolTitle)
                            : _title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _editorialSurface ? plpInk : _ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_tool is! TeamScreen)
                      IconButton(
                        key: const ValueKey('core-refresh'),
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _load,
                        icon: Icon(Icons.refresh_rounded,
                            size: 21,
                            color: _editorialSurface ? plpInk : null),
                      ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  bool get _editorialSurface =>
      _tool == null &&
      const {'home', 'clients', 'business', 'platform', 'administration'}
          .contains(_section);

  List<Widget> _body() => switch (_section) {
        'home' => _decisionQueue ? _decisionList() : _home(),
        'clients' => _clients(),
        'client' => _clientDetail(),
        'business' => _business(),
        'platform' => _platform(),
        'administration' => _administration(),
        _ => const [SizedBox.shrink()],
      };

  List<Widget> _home() {
    final health = coreRecord(_snapshot?['health']);
    final clients = _rows('clients');
    final needsYou = _rows('needs_you');
    final handling = _rows('handling');
    final outcomes = _rows('outcomes');
    return [
      TextButton.icon(
        key: const ValueKey('core-add-client'),
        onPressed: _registerClient,
        icon: const Icon(Icons.add_rounded, color: plpInk),
        label: const Text(
          'Add Enterprise Client',
          style: TextStyle(color: plpInk),
        ),
      ),
      const PlpSectionTitle('System status'),
      PlpMetricStrip(items: [
        ('Clients', coreText(health['clients']), 'Registered'),
        ('Active', coreText(health['active_clients']), 'Current'),
      ]),
      const SizedBox(height: 12),
      PlpMetricStrip(items: [
        ('Attention', coreText(health['attention_clients']), 'Need you'),
        ('Platform', coreText(health['state'], 'Not recorded'), 'Current'),
      ]),
      const PlpSectionTitle('Needs You'),
      if (needsYou.isEmpty)
        const _PlpMissing('No owner decisions in this snapshot.')
      else
        for (final row in needsYou.take(5))
          PlpEditorialRow(
            title: coreText(row['title'], 'Decision'),
            detail: coreText(row['reason'], 'Needs an owner decision'),
            onTap: () => _showDecision(row),
          ),
      PlpEditorialRow(
        title: 'Open queue',
        detail: 'Review the full decision list',
        onTap: () => widget.onNavigate?.call('needs_you'),
      ),
      const PlpSectionTitle('Clients'),
      if (clients.isEmpty)
        const _PlpMissing('No enterprise clients registered yet.')
      else
        for (final client in clients.take(6))
          PlpEditorialRow(
            title: coreText(client['display_name'], 'Enterprise client'),
            detail: coreText(client['industry'], 'Industry not recorded'),
            value: coreText(client['lifecycle_state'], 'Not recorded'),
            onTap: () => _showRecord(client),
          ),
      const PlpSectionTitle('Pandora is handling'),
      if (handling.isEmpty)
        const _PlpMissing('No active work in this snapshot.')
      else
        for (final row in handling.take(4))
          PlpEditorialRow(
            title: coreText(row['title'], 'Operation'),
            detail: coreText(row['state'], 'State not recorded'),
            onTap: () => _showRecord(row),
          ),
      const PlpSectionTitle('Recent outcomes'),
      if (outcomes.isEmpty)
        const _PlpMissing('No verified outcomes in this snapshot.')
      else
        for (final row in outcomes.take(5))
          PlpEditorialRow(
            title: coreText(row['title'], 'Outcome'),
            detail: coreText(row['state'], 'State not recorded'),
            onTap: () => _showRecord(row),
          ),
    ];
  }

  List<Widget> _clients() {
    final clients = _rows('clients').where((client) =>
        _query.isEmpty ||
        '${client['display_name']} ${client['industry']} '
                '${client['lifecycle_state']}'
            .toLowerCase()
            .contains(_query));
    return [
      const PlpSectionTitle('Clients'),
      _Action(
        key: const ValueKey('core-add-client'),
        label: 'Add Enterprise Client',
        icon: Icons.add_rounded,
        onPressed: _registerClient,
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _search,
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
        decoration: const InputDecoration(
          hintText: 'Find a client',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 14),
      if (clients.isEmpty)
        const _Empty('No matching enterprise clients.')
      else
        for (final client in clients) _clientCard(client),
    ];
  }

  Widget _clientCard(PandoraCoreRecord client) {
    final id = coreText(client['organization_id'], '');
    return _Panel(
      key: ValueKey('core-client-$id'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(coreText(client['display_name'], 'Enterprise client'),
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700, fontSize: 17))),
          const SizedBox(width: 8),
          _StatePill(client['lifecycle_state']),
        ]),
        const SizedBox(height: 5),
        Text(coreText(client['industry'], 'Industry not recorded'),
            style: const TextStyle(color: _muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 8, children: [
          _Signal('users', client['users']),
          _Signal('connections', client['connections']),
          _Signal('devices', client['devices']),
        ]),
        const SizedBox(height: 9),
        _StatusLine('Health', client['health']),
        Wrap(spacing: 8, children: [
          TextButton(
            key: ValueKey('core-manage-$id'),
            onPressed: () => _openClient(client),
            child: const Text('Manage client'),
          ),
          TextButton(
            key: ValueKey('core-enter-$id'),
            onPressed: client['can_enter'] == true &&
                    widget.onEnterClient != null &&
                    !_acting
                ? () => _enter(client)
                : null,
            child: const Text('Enter client workspace'),
          ),
          if (client['can_enter'] != true)
            TextButton(
              key: ValueKey('core-request-access-$id'),
              onPressed: () => _requestWorkspaceAccess(id),
              child: const Text('Request workspace access'),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _clientDetail() {
    final client = _client;
    final id = _clientId!;
    const tabs = [
      'Summary',
      'Onboarding',
      'People',
      'Connections',
      'Devices',
      'Usage',
      'Commercial',
      'Support',
      'Releases',
    ];
    final tab = tabs.contains(_tab) ? _tab : tabs.first;
    return [
      Text(coreText(client['industry'], 'Enterprise client'),
          style: const TextStyle(color: _muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _StatePill(client['lifecycle_state']),
        _StatePill(client['onboarding_state']),
        _Action(
          key: ValueKey('core-enter-$id'),
          label: 'Enter client workspace',
          icon: Icons.open_in_new_rounded,
          onPressed: client['can_enter'] == true &&
                  widget.onEnterClient != null &&
                  !_acting
              ? () => _enter(client)
              : null,
        ),
        if (client['can_enter'] != true)
          _Action(
            key: ValueKey('core-request-access-$id'),
            label: 'Request workspace access',
            icon: Icons.lock_open_outlined,
            onPressed: () => _requestWorkspaceAccess(id),
          ),
      ]),
      if (client['can_enter'] != true)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
              'Workspace entry needs verified access and a configured workspace.',
              style: TextStyle(color: _muted, fontSize: 12)),
        ),
      const SizedBox(height: 16),
      _tabs(tabs, tab),
      const SizedBox(height: 14),
      ...switch (tab) {
        'Summary' => [
            _Panel(
              child: Wrap(spacing: 24, runSpacing: 14, children: [
                _Signal('users', client['users']),
                _Signal('administrators', client['admins']),
                _Signal('connections', client['connections']),
                _Signal('devices', client['devices']),
              ]),
            ),
            _StatusLine('Health', client['health']),
            _StatusLine('Last active', client['last_active']),
            _StatusLine('Created', client['created_at']),
            const SizedBox(height: 10),
            _Action(
              label: 'Edit client',
              icon: Icons.edit_outlined,
              onPressed: () => _form(
                'client.update',
                'Edit client',
                const [
                  CoreFormField('primary_contact_name', 'Primary contact'),
                  CoreFormField('primary_contact_email', 'Contact email',
                      email: true),
                  CoreFormField('notes', 'Notes', multiline: true),
                  CoreFormField('lifecycle_state', 'Lifecycle', options: {
                    'prospect': 'Prospect',
                    'contracting': 'Contracting',
                    'onboarding': 'Onboarding',
                    'attention': 'Needs attention',
                    'suspended': 'Suspended',
                    'offboarding': 'Offboarding',
                    'archived': 'Archived',
                  }),
                ],
                organizationId: id,
                initial: client,
              ),
            ),
          ],
        'Onboarding' => [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Action(
                  label: 'Verify onboarding',
                  icon: Icons.fact_check_outlined,
                  onPressed: _acting
                      ? null
                      : () => _run('onboarding.verify', id, const {})),
              _Action(
                  label: 'Configure capabilities',
                  icon: Icons.extension_outlined,
                  onPressed: () => _capabilityForm(id)),
              _Action(
                  label: 'Record verification',
                  icon: Icons.verified_outlined,
                  onPressed: () => _attestForm(id)),
              _Action(
                  label: 'Approve go-live',
                  icon: Icons.rocket_launch_outlined,
                  onPressed: () => _form(
                      'client.go_live',
                      'Approve client go-live',
                      const [
                        CoreFormField('evidence_ref', 'Verification evidence',
                            required: true),
                      ],
                      organizationId: id,
                      submitLabel: 'Approve go-live')),
            ]),
            const SizedBox(height: 12),
            if (_rows('onboarding').isEmpty)
              const _Empty('No onboarding steps are available.')
            else
              for (final step in _rows('onboarding'))
                _RecordTile(
                  row: step,
                  onTap: () => _onboardingStep(step, id),
                ),
          ],
        'People' => [
            _Action(
              label: 'Manage Team & Access',
              icon: Icons.group_outlined,
              onPressed: () => _openTeam(id),
            ),
            const SizedBox(height: 12),
            ..._recordList('members', 'No client users recorded.'),
          ],
        'Connections' => _recordList(
            'connections', 'No connections verified for this client.'),
        'Devices' => [
            ..._recordList('devices', 'No enrolled devices.'),
            if (_rows('devices').isNotEmpty)
              _Action(
                label: 'Revoke a device',
                icon: Icons.phonelink_erase_rounded,
                onPressed: () => _form(
                    'device.revoke',
                    'Revoke device',
                    [
                      CoreFormField('id', 'Device', required: true, options: {
                        for (final device in _rows('devices'))
                          coreText(device['id'], ''):
                              _recordTitle(device, 'Enrolled device'),
                      }),
                      const CoreFormField('reason', 'Reason', required: true),
                    ],
                    organizationId: id),
              ),
          ],
        'Usage' => [
            ..._recordList(
                'usage', 'No measured usage for this client in this period.'),
            const _Heading('Allowances'),
            ..._recordList(
                'usage_allowances', 'No active allowance is recorded.'),
          ],
        'Commercial' => [
            _commercialActions(id),
            const _Heading('Subscription'),
            if (coreRecord(_snapshot?['subscription']).isEmpty)
              const _Empty('No subscription recorded.')
            else
              _RecordTile(
                row: coreRecord(_snapshot?['subscription']),
                onTap: () =>
                    _showRecord(coreRecord(_snapshot?['subscription'])),
              ),
            const _Heading('Contracts'),
            ..._recordList('contracts', 'No contracts linked.'),
            const _Heading('Invoices'),
            ..._recordList('invoices', 'No invoices recorded.'),
            const _Heading('Payments'),
            ..._recordList('payments', 'No payments recorded.'),
          ],
        'Support' => [
            _Action(
              label: 'Add support case',
              icon: Icons.add_rounded,
              onPressed: () => _caseForm(id),
            ),
            const SizedBox(height: 12),
            ..._recordList('cases', 'No open support cases.'),
          ],
        'Releases' => _recordList(
            'deployments', 'No verified deployment linked to this client.'),
        _ => const <Widget>[],
      },
    ];
  }

  List<Widget> _business() {
    return [
      const PlpSectionTitle('Business'),
      ..._businessBody(),
    ];
  }

  List<Widget> _businessBody() {
    const tabs = [
      'Pipeline',
      'Contracts',
      'Subscriptions',
      'Invoices',
      'Payments',
      'Usage & Costs',
      'Plans',
      'Partners',
    ];
    final tab = tabs.contains(_tab) ? _tab : tabs.first;
    final key = {
      'Pipeline': 'pipeline',
      'Contracts': 'contracts',
      'Subscriptions': 'subscriptions',
      'Invoices': 'invoices',
      'Payments': 'payments',
      'Usage & Costs': 'usage',
      'Plans': 'plans',
      'Partners': 'vendors',
    }[tab]!;
    return [
      _businessSummary(coreRecord(_snapshot?['business'])),
      const SizedBox(height: 14),
      _tabs(tabs, tab),
      const SizedBox(height: 12),
      if (tab == 'Pipeline')
        _Action(
            label: 'Add prospect',
            icon: Icons.add_rounded,
            onPressed: () => _prospectForm()),
      if (tab == 'Plans')
        _Action(
            label: 'Create plan',
            icon: Icons.add_rounded,
            onPressed: () => _form(
                'plan.save',
                'Create plan',
                const [
                  CoreFormField('code', 'Code', required: true),
                  CoreFormField('name', 'Name', required: true),
                  CoreFormField('currency', 'Currency', options: {
                    'PHP': 'PHP',
                    'USD': 'USD',
                  }),
                  CoreFormField('monthly_fee_micros', 'Monthly fee',
                      money: true),
                  CoreFormField(
                      'included_allowance_micros', 'Included cost allowance',
                      money: true),
                  CoreFormField('entitlements', 'Capability entitlements',
                      list: true,
                      hint:
                          'Commercial terms; comma-separated capability keys'),
                  CoreFormField(
                      'request_admission_policy', 'Cloud-chat request control',
                      options: {
                        'record_only': 'Record requests only',
                        'block': 'Block at monthly request limit',
                      }),
                  CoreFormField(
                      'limits.monthly_requests', 'Monthly cloud-chat requests',
                      integer: true,
                      requiredWhenField: 'request_admission_policy',
                      requiredWhenValue: 'block'),
                  CoreFormField('limits.users', 'Commercial seat allowance',
                      integer: true),
                  CoreFormField('limits.devices', 'Commercial device allowance',
                      integer: true),
                  CoreFormField(
                      'limits.monthly_tokens', 'Commercial token allowance',
                      integer: true),
                  CoreFormField(
                      'limits.budget_micros', 'Commercial cost allowance',
                      money: true),
                  CoreFormField('state', 'Availability',
                      options: {'draft': 'Draft', 'active': 'Active'}),
                  CoreFormField('overage_policy', 'Commercial overage terms',
                      options: {
                        'approval_required': 'Approval clause',
                        'blocked': 'No-overage clause',
                        'contracted': 'Contracted overage',
                      }),
                  CoreFormField('support_tier', 'Support tier', options: {
                    'standard': 'Standard',
                    'priority': 'Priority',
                    'dedicated': 'Dedicated',
                  }),
                ],
                financial: true,
                notice: 'Only cloud-chat request blocking is enforced for '
                    'enabled subscriptions. Other allowances, entitlements '
                    'and overage terms are commercial records.')),
      if (tab == 'Partners')
        _Action(
            label: 'Add vendor or partner',
            icon: Icons.add_rounded,
            onPressed: () => _form(
                'partner.save',
                'Vendor or partner',
                const [
                  CoreFormField('name', 'Name', required: true),
                  CoreFormField('kind', 'Relationship',
                      options: {'vendor': 'Vendor', 'partner': 'Partner'}),
                  CoreFormField('service', 'Service'),
                  CoreFormField('contact', 'Contact'),
                  CoreFormField(
                      'recurring_cost_micros', 'Monthly operating cost',
                      money: true),
                  CoreFormField('currency', 'Currency',
                      options: {'PHP': 'PHP', 'USD': 'USD'}),
                  CoreFormField('next_review_on', 'Next review',
                      hint: 'YYYY-MM-DD'),
                  CoreFormField('notes', 'Notes', multiline: true),
                ],
                financial: true)),
      if (const ['Contracts', 'Subscriptions', 'Invoices', 'Payments']
          .contains(tab))
        const _Notice(
          title: 'Client commercial records',
          message: 'Open a client to create scoped commercial records.',
        ),
      const SizedBox(height: 10),
      ..._recordList(key, 'No ${tab.toLowerCase()} recorded.'),
      if (tab == 'Usage & Costs') ...[
        const _Heading('Allowances'),
        ..._recordList('usage_allowances', 'No active allowances recorded.'),
      ],
    ];
  }

  Widget _commercialActions(String id) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Action(
            label: 'Set subscription',
            icon: Icons.repeat_rounded,
            onPressed: () => _form(
                'subscription.save',
                'Client subscription',
                [
                  if (_rows('plans').isNotEmpty)
                    CoreFormField('plan_id', 'Plan', required: true, options: {
                      for (final plan in _rows('plans'))
                        coreText(plan['id'], ''): coreText(plan['name']),
                    }),
                  const CoreFormField('state', 'State', options: {
                    'draft': 'Draft',
                    'trial': 'Trial',
                    'active': 'Active',
                    'past_due': 'Past due',
                    'cancelled': 'Cancelled',
                  }),
                  const CoreFormField('request_admission_enabled',
                      'Apply cloud-chat request limit',
                      boolean: true,
                      hint: 'Requires an active plan with request blocking.',
                      options: {
                        'false': 'Off',
                        'true': 'On — enforce request limit',
                      }),
                  const CoreFormField('currency', 'Currency', options: {
                    'PHP': 'PHP',
                    'USD': 'USD',
                  }),
                  const CoreFormField('monthly_fee_micros', 'Monthly fee',
                      money: true),
                  const CoreFormField('setup_fee_micros', 'Setup fee',
                      money: true),
                  const CoreFormField('starts_on', 'Start date',
                      hint: 'YYYY-MM-DD'),
                  const CoreFormField('ends_on', 'End date',
                      hint: 'YYYY-MM-DD'),
                  const CoreFormField('renews_on', 'Renewal date',
                      hint: 'YYYY-MM-DD'),
                ],
                organizationId: id,
                initial: coreRecord(_snapshot?['subscription']),
                financial: true,
                notice: 'Applies only to cloud-chat request admission. '
                    'Server-recorded coverage dates cannot be edited or reset '
                    'here. Other allowances remain commercial terms.')),
        _Action(
            label: 'Link contract',
            icon: Icons.description_outlined,
            onPressed: () => _form(
                'contract.save',
                'Link client contract',
                const [
                  CoreFormField('title', 'Title', required: true),
                  CoreFormField('contract_type', 'Type', options: {
                    'service_agreement': 'Service agreement',
                    'sow': 'Scope of work',
                    'nda': 'NDA',
                    'dpa': 'DPA',
                    'renewal': 'Renewal',
                  }),
                  CoreFormField('document_url', 'Document link', url: true),
                  CoreFormField('starts_on', 'Start date', hint: 'YYYY-MM-DD'),
                  CoreFormField('ends_on', 'End date', hint: 'YYYY-MM-DD'),
                  CoreFormField('renewal_on', 'Renewal date',
                      hint: 'YYYY-MM-DD'),
                  CoreFormField('state', 'State', options: {
                    'draft': 'Draft',
                    'active': 'Active',
                    'expired': 'Expired',
                    'terminated': 'Terminated',
                  }),
                ],
                organizationId: id,
                financial: true)),
        _Action(
            label: 'Create invoice',
            icon: Icons.receipt_long_outlined,
            onPressed: () => _form(
                'invoice.save',
                'Create invoice',
                const [
                  CoreFormField('invoice_number', 'Invoice number',
                      required: true),
                  CoreFormField('currency', 'Currency', options: {
                    'PHP': 'PHP',
                    'USD': 'USD',
                  }),
                  CoreFormField('amount_micros', 'Amount',
                      required: true, money: true),
                  CoreFormField('issued_on', 'Issue date', hint: 'YYYY-MM-DD'),
                  CoreFormField('due_on', 'Due date', hint: 'YYYY-MM-DD'),
                  CoreFormField('state', 'State', options: {
                    'draft': 'Draft',
                    'issued': 'Issued',
                  }),
                ],
                organizationId: id,
                financial: true)),
        _Action(
            label: 'Record payment',
            icon: Icons.payments_outlined,
            onPressed: () => _form(
                'payment.record',
                'Record manual payment',
                [
                  CoreFormField('invoice_id', 'Invoice',
                      required: true,
                      options: {
                        for (final invoice in _rows('invoices'))
                          coreText(invoice['id'], ''):
                              coreText(invoice['invoice_number'], 'Invoice'),
                      }),
                  const CoreFormField('amount_micros', 'Amount',
                      required: true, money: true),
                  const CoreFormField('currency', 'Currency', options: {
                    'PHP': 'PHP',
                    'USD': 'USD',
                  }),
                  const CoreFormField('payment_kind', 'Kind', options: {
                    'payment': 'Payment',
                    'credit': 'Credit',
                    'refund': 'Refund',
                    'adjustment': 'Adjustment',
                  }),
                  const CoreFormField('reference', 'Payment reference',
                      required: true),
                  const CoreFormField('occurred_on', 'Transaction date',
                      required: true, hint: 'YYYY-MM-DD'),
                ],
                organizationId: id,
                financial: true)),
      ]);

  List<Widget> _platform() {
    return [
      const PlpSectionTitle('Platform'),
      ..._platformBody(),
    ];
  }

  List<Widget> _platformBody() {
    const tabs = [
      'Connections',
      'Providers',
      'Models',
      'Devices',
      'Deployments',
      'Automations',
      'Memory',
      'Evidence',
    ];
    final tab = tabs.contains(_tab) ? _tab : tabs.first;
    return [
      _tabs(tabs, tab),
      const SizedBox(height: 14),
      if (tab == 'Connections')
        _Action(
          label: 'Open Live Connections',
          icon: Icons.cable_rounded,
          onPressed: () => widget.onNavigate?.call('connections'),
        ),
      if (tab == 'Providers')
        _Action(
          label: 'Capabilities & Providers',
          icon: Icons.account_tree_outlined,
          onPressed: () => widget.onNavigate?.call('capabilities'),
        ),
      if (tab == 'Models') _modelRoutingSummary(),
      if (tab == 'Models')
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _modelDetails = !_modelDetails),
            icon: Icon(_modelDetails ? Icons.expand_less : Icons.expand_more),
            label: Text(_modelDetails ? 'Hide model details' : 'Model details'),
          ),
        ),
      if (tab == 'Memory') const PandoraCoreMemoryPanel(),
      if (tab == 'Automations' && widget.onNavigate != null)
        _Action(
          label: 'Open Operations Room',
          icon: Icons.settings_suggest_outlined,
          onPressed: () => widget.onNavigate?.call('operations'),
        ),
      const SizedBox(height: 10),
      if (tab == 'Memory') const _Heading('Pending learning delivery'),
      if (tab == 'Automations') const _Heading('Recent work'),
      if (tab != 'Models' || _modelDetails)
        ..._recordList(
            tab.toLowerCase(),
            tab == 'Memory'
                ? 'No pending learning deliveries.'
                : tab == 'Automations'
                    ? 'No recorded tasks in this snapshot.'
                    : 'No verified ${tab.toLowerCase()} state in this snapshot.',
            hidePromotedCandidate: tab == 'Deployments'),
    ];
  }

  Widget _modelRoutingSummary() {
    final routing = coreRecord(_snapshot?['model_routing']);
    final failedModels = _rows('models')
        .where((row) => row['verification_state'] == 'failed')
        .length;
    if (routing.isEmpty) {
      return Column(children: [
        const _Empty('Current model routing evidence is unavailable.'),
        if (failedModels > 0)
          _StatusLine('Models with failed checks', '$failedModels'),
      ]);
    }
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('Auto routing',
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w700))),
          _StatePill(routing['enabled'] == true
              ? 'Enabled'
              : routing['enabled'] == false
                  ? 'Disabled'
                  : 'Unknown'),
        ]),
        const SizedBox(height: 8),
        for (final field in {
          'configured_eligible_models': 'Eligible models',
          if (_modelDetails) ...{
            'verified_eligible_models': 'With runtime evidence',
            'fresh_verified_eligible_models': 'Verified within 24 hours',
          },
        }.entries)
          if (routing[field.key] is num)
            _StatusLine(field.value, coreText(routing[field.key])),
        if (failedModels > 0)
          _StatusLine('Models with failed checks', '$failedModels'),
        if (_modelDetails)
          TextButton(
            onPressed: () =>
                _showRecord(routing, title: 'Auto routing evidence'),
            child: const Text('Routing evidence'),
          ),
      ]),
    );
  }

  List<Widget> _administration() {
    return [
      const PlpSectionTitle('Administration'),
      ..._administrationBody(),
    ];
  }

  List<Widget> _administrationBody() {
    const tabs = ['Team', 'Security', 'Incidents', 'Audit', 'Policies'];
    final tab = tabs.contains(_tab) ? _tab : tabs.first;
    return [
      _tabs(tabs, tab),
      const SizedBox(height: 14),
      if (tab == 'Team') ...[
        _Action(
            label: 'Manage Team & Access',
            icon: Icons.group_outlined,
            onPressed: () {
              final org = coreText(
                  coreRecord(
                      _snapshot?['operator'])['platform_organization_id'],
                  '');
              if (org.isEmpty) return;
              _openTeam(org);
            }),
        const SizedBox(height: 12),
        ..._recordList('team', 'No internal team records available.'),
      ],
      if (tab == 'Security') ...[
        _Action(
            label: 'Verify & Safety',
            icon: Icons.shield_outlined,
            onPressed: () => widget.onNavigate?.call('safety')),
        const _Heading('Operator access'),
        if (coreRecord(_snapshot?['operator'])['role'] == 'owner')
          _Action(
              label: 'Manage operator access',
              icon: Icons.admin_panel_settings_outlined,
              onPressed: _operatorForm),
        ..._recordList('operators', 'No operator grants visible.'),
      ],
      if (tab == 'Incidents') ...[
        _Action(
            label: 'Record incident',
            icon: Icons.add_rounded,
            onPressed: () => _incidentForm()),
        const SizedBox(height: 12),
        ..._recordList('incidents', 'No incidents recorded.'),
      ],
      if (tab == 'Audit')
        ..._recordList('audit', 'No audit records in this snapshot.'),
      if (tab == 'Policies')
        ..._recordList('policies', 'No policy state available.'),
    ];
  }

  List<Widget> _decisionList() => [
        const PlpSectionTitle('Needs You'),
        _Action(
            label: 'Pending authorizations',
            icon: Icons.verified_user_outlined,
            onPressed: () => setState(() {
                  _toolTitle = 'Pending authorizations';
                  _tool = const ApprovalsScreen();
                })),
        const SizedBox(height: 12),
        if (_rows('needs_you').isEmpty)
          const _Empty('No owner decisions in this snapshot.')
        else
          for (final row in _rows('needs_you'))
            _RecordTile(
                row: row, isDecision: true, onTap: () => _showDecision(row)),
      ];

  void _showDecision(PandoraCoreRecord row) {
    _showRecord(row, title: 'Needs You', actionLabel: 'Open action',
        onAction: () {
      final action = coreText(row['action'], '');
      if (action == 'open_approvals') {
        setState(() {
          _toolTitle = 'Pending authorizations';
          _tool = const ApprovalsScreen();
        });
        return;
      }
      if (action == 'open_operations') {
        widget.onNavigate?.call('operations');
        return;
      }
      final organizationId = coreText(row['organization_id'], '');
      if (organizationId.isNotEmpty &&
          _rows('clients')
              .any((client) => client['organization_id'] == organizationId)) {
        _openClient({'organization_id': organizationId});
        setState(() => _tab = switch (action) {
              'open_connections' => 'Connections',
              'open_onboarding' => 'Onboarding',
              'open_case' => 'Support',
              'open_client_commercial' => 'Commercial',
              _ => 'Summary',
            });
      } else if (action == 'open_connections') {
        final platformId = coreText(
            coreRecord(_snapshot?['operator'])['platform_organization_id'], '');
        if (organizationId.isEmpty || organizationId == platformId) {
          widget.onNavigate?.call('connections');
        } else {
          _message('Refresh Clients to verify this connection’s organization.');
        }
      } else {
        widget.onNavigate?.call('administration');
      }
    });
  }

  Future<void> _prospectForm({PandoraCoreRecord initial = const {}}) => _form(
      'prospect.save',
      initial['id'] == null ? 'Add prospect' : 'Update prospect',
      [
        const CoreFormField('company_name', 'Company', required: true),
        const CoreFormField('contact_name', 'Contact'),
        const CoreFormField('contact_email', 'Contact email', email: true),
        const CoreFormField('industry', 'Industry'),
        const CoreFormField('source', 'Source'),
        const CoreFormField('stage', 'Stage', options: {
          'prospect': 'Prospect',
          'qualified': 'Qualified',
          'demo': 'Demo',
          'proposal': 'Proposal',
          'contracting': 'Contracting',
          'won': 'Won',
          'lost': 'Lost'
        }),
        CoreFormField('converted_organization_id', 'Converted client',
            requiredWhenField: 'stage',
            requiredWhenValue: 'won',
            hint: 'Register the client in Clients before marking won.',
            options: {
              '': 'Not linked',
              for (final client in _rows('clients'))
                coreText(client['organization_id']):
                    coreText(client['display_name']),
            }),
        const CoreFormField('currency', 'Currency',
            options: {'PHP': 'PHP', 'USD': 'USD'}),
        const CoreFormField('estimated_value_micros', 'Estimated value',
            money: true),
        const CoreFormField('next_action', 'Next action', required: true),
        const CoreFormField('follow_up_at', 'Follow up', hint: 'YYYY-MM-DD'),
        const CoreFormField('decision_on', 'Decision date', hint: 'YYYY-MM-DD'),
        const CoreFormField('notes', 'Notes', multiline: true),
      ],
      initial: initial);

  Future<void> _incidentForm({PandoraCoreRecord initial = const {}}) => _form(
      'incident.save',
      initial['id'] == null ? 'Record incident' : 'Update incident',
      const [
        CoreFormField('title', 'Title', required: true),
        CoreFormField('severity', 'Severity', options: {
          'low': 'Low',
          'medium': 'Medium',
          'high': 'High',
          'critical': 'Critical',
        }),
        CoreFormField('state', 'State', options: {
          'investigating': 'Investigating',
          'identified': 'Identified',
          'recovering': 'Recovering',
          'resolved': 'Resolved',
        }),
        CoreFormField('impact', 'Impact', required: true, multiline: true),
        CoreFormField('diagnosis', 'Diagnosis', multiline: true),
        CoreFormField('resolution', 'Resolution',
            multiline: true,
            requiredWhenField: 'state',
            requiredWhenValue: 'resolved'),
        CoreFormField('verification_ref', 'Recovery evidence',
            requiredWhenField: 'state', requiredWhenValue: 'resolved'),
      ],
      organizationId: coreText(initial['organization_id'], '').isEmpty
          ? null
          : coreText(initial['organization_id']),
      initial: initial,
      notice:
          'Scope: ${_organizationName(coreText(initial['organization_id'], '').isEmpty ? null : coreText(initial['organization_id']))}',
      submitLabel: 'Save incident');

  Future<void> _capabilityForm(String id) async {
    final packs = _rows('available_capability_packs');
    if (packs.isEmpty) {
      _message(
          'No active capability packs are available in this snapshot. Refresh to check the catalog.');
      return;
    }
    final selected = await showModalBottomSheet<PandoraCoreRecord>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(shrinkWrap: true, children: [
        for (final pack in packs)
          ListTile(
              title: Text(coreText(pack['name'], coreText(pack['key']))),
              subtitle: Text('Version ${coreText(pack['version'])}'),
              onTap: () => Navigator.pop(sheetContext, pack)),
      ]),
    );
    if (!mounted || selected == null) return;
    await _form(
        'capability.activate',
        'Configure capability',
        [
          CoreFormField('pack_key', 'Capability', options: {
            coreText(selected['key']):
                coreText(selected['name'], coreText(selected['key']))
          }),
          CoreFormField('pack_version', 'Version', options: {
            coreText(selected['version']): coreText(selected['version'])
          }),
        ],
        organizationId: id,
        submitLabel: 'Configure');
  }

  Future<void> _attestForm(String id, {String? step}) => _form(
      'onboarding.attest',
      'Record onboarding evidence',
      [
        if (step == null)
          const CoreFormField('step', 'Step', options: {
            'routing': 'AI routing and policy',
            'verification': 'Workspace verification',
            'connections': 'Connections',
            'billing': 'Billing',
          }),
        CoreFormField('state', 'Evidence state', options: {
          'verified': 'Verified by owner',
          if (step == 'connections' || step == 'billing')
            'not_required': 'Not required',
        }),
        const CoreFormField('note', 'What was verified',
            required: true, multiline: true),
        const CoreFormField('evidence_ref', 'Evidence reference',
            required: true),
      ],
      organizationId: id,
      initial: {if (step != null) 'step': step},
      submitLabel: 'Record evidence');

  void _onboardingStep(PandoraCoreRecord step, String id) {
    final key = coreText(step['key'] ?? step['step'], '');
    if (key == 'identity' || key == 'go_live') {
      _showRecord(step);
      return;
    }
    _showRecord(step, actionLabel: 'Update step', onAction: () async {
      final action = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (sheetContext) =>
              Column(mainAxisSize: MainAxisSize.min, children: [
                if (key == 'administrator')
                  ListTile(
                      title: const Text('Manage users'),
                      onTap: () => Navigator.pop(sheetContext, 'users')),
                if (key == 'capabilities')
                  ListTile(
                      title: const Text('Configure capabilities'),
                      onTap: () => Navigator.pop(sheetContext, 'capabilities')),
                if (key == 'limits' || key == 'billing')
                  ListTile(
                      title: const Text('Set commercial terms'),
                      onTap: () => Navigator.pop(sheetContext, 'commercial')),
                if (const {'routing', 'verification', 'connections', 'billing'}
                    .contains(key))
                  ListTile(
                      title: const Text('Record verification evidence'),
                      onTap: () => Navigator.pop(sheetContext, 'attest')),
                ListTile(
                    title: const Text('Record pending work or blocker'),
                    onTap: () => Navigator.pop(sheetContext, 'checkpoint')),
              ]));
      if (!mounted || action == null) return;
      switch (action) {
        case 'users':
          _openTeam(id);
        case 'capabilities':
          await _capabilityForm(id);
        case 'commercial':
          setState(() => _tab = 'Commercial');
        case 'attest':
          await _attestForm(id, step: key);
        case 'checkpoint':
          await _form(
              'onboarding.checkpoint',
              coreText(step['title'], 'Onboarding step'),
              const [
                CoreFormField('state', 'Progress',
                    options: {'pending': 'Pending', 'blocked': 'Blocked'}),
                CoreFormField('note', 'What is required next',
                    required: true, multiline: true),
              ],
              organizationId: id,
              initial: {'step': key, 'state': step['state']});
      }
    });
  }

  Future<void> _operatorForm() async {
    final team =
        _rows('team').where((row) => row['status'] == 'active').toList();
    if (team.isEmpty) {
      _message('An active internal team member is required.');
      return;
    }
    await _form(
        'operator.grant',
        'Operator access',
        [
          CoreFormField('user_id', 'Internal team member',
              required: true,
              options: {
                for (final member in team)
                  coreText(member['user_id']):
                      coreText(member['name'], 'Team member'),
              }),
          const CoreFormField('role', 'Authority', options: {
            'support': 'Support',
            'operator': 'Operator',
            'finance': 'Finance',
            'owner': 'Owner'
          }),
          CoreFormField('scope_organization_id', 'Client scope', options: {
            for (final client in _rows('clients'))
              coreText(client['organization_id']):
                  coreText(client['display_name']),
            '': 'All clients and platform',
          }),
          const CoreFormField('expires_at', 'Expires',
              hint: 'YYYY-MM-DDTHH:MM:SSZ'),
          const CoreFormField('state', 'State',
              options: {'active': 'Active', 'revoked': 'Revoked'}),
          const CoreFormField('reason', 'Reason',
              required: true, multiline: true),
        ],
        submitLabel: 'Save access');
  }

  void _recordAction(String key, PandoraCoreRecord row) {
    if (key == 'evidence') {
      final kind = _humanizeRecordAction(row['kind']);
      _showRecord(row, title: kind.isEmpty ? 'Evidence record' : kind);
      return;
    }
    if (key == 'pipeline') {
      _prospectForm(initial: row);
      return;
    }
    if (key == 'cases' && _clientId != null) {
      _caseForm(_clientId!, initial: row);
      return;
    }
    if (key == 'incidents') {
      _incidentForm(initial: row);
      return;
    }
    _showRecord(row);
  }

  Future<void> _caseForm(String id, {PandoraCoreRecord initial = const {}}) {
    final assignedUserId = coreText(initial['assigned_user_id'], '');
    final assignees = <String, String>{
      '': 'Unassigned',
      if (assignedUserId.isNotEmpty)
        assignedUserId: 'Current assignee (unchanged)',
      for (final member in _rows('members'))
        if (member['status'] == 'active' &&
            coreText(member['user_id'], '').isNotEmpty &&
            (member['organization_id'] == null ||
                member['organization_id'] == id))
          coreText(member['user_id']):
              coreText(member['name'], 'Client member'),
    };
    return _form(
        'case.save',
        initial['id'] == null ? 'Add support case' : 'Update support case',
        [
          const CoreFormField('subject', 'Title', required: true),
          const CoreFormField('kind', 'Kind', options: {
            'issue': 'Support issue',
            'request': 'Request',
            'feature': 'Feature request',
            'onboarding': 'Onboarding blocker',
            'training': 'Training',
            'access': 'Access request',
          }),
          const CoreFormField('priority', 'Priority', options: {
            'normal': 'Normal',
            'low': 'Low',
            'high': 'High',
            'urgent': 'Urgent',
          }),
          CoreFormField('assigned_user_id', 'Assigned to',
              options: assignees,
              hint: 'New assignments use active members of this client.'),
          const CoreFormField('description', 'Details',
              multiline: true, required: true),
          const CoreFormField('due_at', 'Due date', hint: 'YYYY-MM-DD'),
          const CoreFormField('needs_owner', 'Owner decision needed',
              boolean: true, options: {'false': 'No', 'true': 'Yes'}),
          const CoreFormField('state', 'Status', options: {
            'open': 'Open',
            'in_progress': 'In progress',
            'blocked': 'Blocked',
            'completed': 'Resolved',
            'cancelled': 'Cancelled'
          }),
          const CoreFormField('resolution', 'Resolution', multiline: true),
        ],
        organizationId: id,
        initial: initial,
        notice: 'Scope: ${_organizationName(id)}');
  }

  Future<void> _run(String operation, String? organizationId,
      PandoraCoreRecord payload) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final result = await widget.gateway.operate(operation,
          organizationId: organizationId,
          payload: payload,
          idempotencyKey: newCoreIdempotencyKey());
      if (!mounted) return;
      _message(coreText(result['next_action'], 'Verification recorded.'));
      await _load();
    } on PandoraCoreFailure catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('The action could not be verified.');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Widget _tabs(List<String> tabs, String selected) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                label: Text(tab),
                selected: selected == tab,
                onSelected: (_) => setState(() => _tab = tab),
              ),
            ),
        ]),
      );

  Widget _businessSummary(PandoraCoreRecord business) {
    final coverage = business['coverage'];
    final currencies = coreRecords(business['currencies']);
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (currencies.isNotEmpty)
          for (final currency in currencies)
            _RecordTile(row: currency, onTap: () => _showRecord(currency))
        else
          const Text('Revenue and margin need authoritative billing data.',
              style: TextStyle(color: _muted, height: 1.4)),
        if (coverage is String && coverage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(coverage, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ]),
    );
  }

  List<Widget> _recordList(String key, String empty,
      {bool hidePromotedCandidate = false}) {
    var rows = _rows(key);
    if (hidePromotedCandidate) {
      // Deduplicate only the Simple list. Audit observations remain untouched.
      (String, String)? identity(PandoraCoreRecord row) {
        final deployment = coreText(row['provider_deployment_id'], '');
        final sha =
            coreText(row['source_sha'], coreText(row['source_commit_sha'], ''));
        final commit = coreText(row['source_commit_sha'], '');
        if (deployment.isEmpty ||
            !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(sha) ||
            (commit.isNotEmpty && commit != sha)) {
          return null;
        }
        return (deployment, sha);
      }

      final production = {
        for (final row in rows)
          if (row['release_observation_kind'] == 'canonical_production' &&
              identity(row) != null)
            identity(row)!,
      };
      rows = rows
          .where((row) =>
              row['release_observation_kind'] != 'candidate' ||
              identity(row) == null ||
              !production.contains(identity(row)))
          .toList(growable: false);
    }
    if (rows.isEmpty) return [_Empty(empty)];
    return [
      for (final row in rows)
        _RecordTile(
          row: row,
          domain: key,
          scopeLabel: _recordScopeLabel(row['organization_id']),
          actorLabel: _recordActorLabel(row),
          onTap: () => _recordAction(key, row),
        ),
    ];
  }

  String _recordScopeLabel(Object? organizationId) {
    if (organizationId == null) return 'All clients and platform';
    final id = coreText(organizationId, '');
    if (id == coreRecord(_snapshot?['operator'])['platform_organization_id']) {
      return 'Pandora';
    }
    for (final client in [..._rows('clients'), _client]) {
      if (client['organization_id'] == id) {
        return coreText(client['display_name'], 'Selected client');
      }
    }
    return 'Selected client';
  }

  String? _recordActorLabel(PandoraCoreRecord row) {
    final userId = row['user_id'] ?? row['actor_user_id'];
    if (userId == null) return null;
    for (final member in _rows('team')) {
      if (member['user_id'] == userId) {
        final name = coreText(member['name'], '');
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  void _showRecord(PandoraCoreRecord row,
      {String? title, String? actionLabel, VoidCallback? onAction}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(title ?? _recordTitle(row, 'Record'),
                style: const TextStyle(
                    color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final entry in _recordFields.entries)
              if ((row[entry.key] != null ||
                      (row.containsKey(entry.key) &&
                          const {
                            'requests_admitted',
                            'requests_remaining',
                            'request_effective_from',
                            'request_admission_started_at',
                            'request_reset_at',
                            'request_window_start',
                          }.contains(entry.key))) &&
                  row[entry.key] is! Map &&
                  row[entry.key] is! List &&
                  !(entry.key == 'source_sha' &&
                      row['source_sha'] == row['source_commit_sha']))
                _StatusLine(
                    entry.value,
                    _displayValue(entry.key, row[entry.key],
                        currency: coreText(row['currency'], '')),
                    preserveExact: const {'candidate', 'canonical_production'}
                            .contains(row['release_observation_kind']) ||
                        const {
                          'event_type',
                          'event_hash',
                          'organization_id',
                          'actor_user_id',
                          'user_id',
                          'model_id',
                          'model',
                          'policy_version',
                          'evidence_ref',
                        }.contains(entry.key)),
            if (const {'candidate', 'canonical_production'}
                .contains(row['release_observation_kind']))
              for (final edge
                  in coreRecords(row['edge_functions']).take(8)) ...[
                const SizedBox(height: 12),
                _Heading(coreText(edge['slug'], 'Edge Function')),
                for (final field in const {
                  'version': 'Provider version',
                  'source_sha': 'Source version',
                  'source_sha256': 'Source digest',
                  'observed_at': 'Observed',
                }.entries)
                  if (edge[field.key] is String || edge[field.key] is num)
                    _StatusLine(field.value, coreText(edge[field.key]),
                        preserveExact: true),
              ],
            const SizedBox(height: 14),
            if (actionLabel != null && onAction != null)
              FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onAction();
                  },
                  child: Text(actionLabel)),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class CoreFormField {
  const CoreFormField(
    this.keyName,
    this.label, {
    this.required = false,
    this.requiredWhenField,
    this.requiredWhenValue,
    this.multiline = false,
    this.email = false,
    this.url = false,
    this.money = false,
    this.integer = false,
    this.list = false,
    this.boolean = false,
    this.hint,
    this.options,
  });
  final String keyName;
  final String label;
  final bool required;
  final String? requiredWhenField;
  final String? requiredWhenValue;
  final bool multiline;
  final bool email;
  final bool url;
  final bool money;
  final bool integer;
  final bool list;
  final bool boolean;
  final String? hint;
  final Map<String, String>? options;
}

class PandoraCoreOperationForm extends StatefulWidget {
  const PandoraCoreOperationForm({
    super.key,
    required this.gateway,
    required this.operation,
    required this.title,
    required this.fields,
    this.organizationId,
    this.initial = const {},
    this.submitLabel = 'Save',
    this.financial = false,
    this.notice,
    this.identity,
    this.scopeLabel,
  });
  final PandoraCoreGateway gateway;
  final String operation;
  final String title;
  final List<CoreFormField> fields;
  final String? organizationId;
  final PandoraCoreRecord initial;
  final String submitLabel;
  final bool financial;
  final String? notice;
  final PandoraAuth? identity;
  final String? scopeLabel;

  @override
  State<PandoraCoreOperationForm> createState() =>
      _PandoraCoreOperationFormState();
}

class _PandoraCoreOperationFormState extends State<PandoraCoreOperationForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  final Map<String, String> _choices = {};
  final String _idempotencyKey = newCoreIdempotencyKey();
  PandoraCoreRecord? _submittedPayload;
  bool _saving = false;
  bool _confirming = false;
  bool _stepUpAttempted = false;
  PandoraCoreFailure? _failure;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        if (field.options == null)
          field.keyName: TextEditingController(
            text: widget.initial[field.keyName] == null
                ? ''
                : field.money
                    ? formatCoreMoneyMicros(widget.initial[field.keyName])
                    : coreText(widget.initial[field.keyName], ''),
          ),
    };
    for (final field in widget.fields) {
      final options = field.options;
      if (options == null || options.isEmpty) continue;
      final initial = coreText(widget.initial[field.keyName], '');
      _choices[field.keyName] =
          options.containsKey(initial) ? initial : options.keys.first;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  PandoraCoreRecord _payload() {
    final result = <String, dynamic>{
      for (final entry in widget.initial.entries)
        if (const {'id', 'step'}.contains(entry.key)) entry.key: entry.value,
    };
    for (final field in widget.fields) {
      final text = field.options != null
          ? _choices[field.keyName] ?? ''
          : _controllers[field.keyName]!.text.trim();
      if (text.isEmpty) continue;
      final dynamic value = field.money
          ? parseCoreMoneyMicros(text)!
          : field.integer
              ? int.parse(text)
              : field.boolean
                  ? text == 'true'
                  : field.list
                      ? text
                          .split(',')
                          .map((item) => item.trim())
                          .where((item) => item.isNotEmpty)
                          .toList()
                      : text;
      if (field.keyName.startsWith('limits.')) {
        final limits = coreRecord(result['limits']);
        limits[field.keyName.substring(7)] = value;
        result['limits'] = limits;
      } else {
        result[field.keyName] = value;
      }
    }
    return result;
  }

  bool _required(CoreFormField field) =>
      field.required ||
      (field.requiredWhenField != null &&
          _choices[field.requiredWhenField] == field.requiredWhenValue);

  Object? _fieldValue(CoreFormField field, PandoraCoreRecord record) =>
      field.keyName.startsWith('limits.')
          ? coreRecord(record['limits'])[field.keyName.substring(7)]
          : record[field.keyName];

  Future<void> _save() async {
    if (_saving || _confirming || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final payload = _submittedPayload ?? _payload();
    if (widget.financial && _submittedPayload == null) {
      setState(() => _confirming = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm commercial record'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.scopeLabel ?? 'Selected account'),
                const SizedBox(height: 8),
                const Text('Manual commercial record'),
                const SizedBox(height: 8),
                for (final field in widget.fields)
                  if (_fieldValue(field, payload) != null &&
                      (field.money ||
                          const {
                            'name',
                            'plan_id',
                            'invoice_number',
                            'currency',
                            'state',
                            'payment_kind',
                            'starts_on',
                            'ends_on',
                            'renews_on',
                            'request_admission_policy',
                            'request_admission_enabled',
                            'limits.monthly_requests',
                          }.contains(field.keyName)))
                    Text(
                        '${field.label}: ${field.options?[_fieldValue(field, payload)] ?? _displayValue(field.keyName, _fieldValue(field, payload), currency: coreText(payload['currency'], ''))}'),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (confirmed != true) return;
    }
    setState(() {
      _saving = true;
      _failure = null;
      _submittedPayload = payload;
    });
    try {
      final result = await widget.gateway.operate(
        widget.operation,
        organizationId: widget.organizationId,
        payload: payload,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on PandoraCoreFailure catch (error) {
      if (!mounted) return;
      if (error.requiresStepUp && !_stepUpAttempted) {
        _stepUpAttempted = true;
        final verified = await verifyCoreIdentity(context, widget.identity);
        if (!mounted) return;
        setState(() {
          _saving = false;
          _failure = verified ? null : error;
        });
        if (verified) await _save();
        return;
      }
      setState(() {
        _failure = error;
        if (const {'INVALID_REQUEST', 'ACCESS_DENIED', 'CONFLICT'}
            .contains(error.code)) {
          _submittedPayload = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _failure = const PandoraCoreFailure(
            'UNAVAILABLE',
            'The result could not be confirmed. Retry uses the '
                'same request so a completed action is not duplicated.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .86),
          child: Form(
            key: _form,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w700)),
                if (widget.financial) ...[
                  const SizedBox(height: 8),
                  const Text('Manual record · identity verification required',
                      style: TextStyle(color: _muted, fontSize: 12)),
                ],
                if (widget.notice != null) ...[
                  const SizedBox(height: 8),
                  Text(widget.notice!,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                for (final field in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: field.options != null
                        ? DropdownButtonFormField<String>(
                            key: ValueKey('core-field-${field.keyName}'),
                            initialValue: _choices[field.keyName],
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText: field.label,
                                helperText: field.hint,
                                helperMaxLines: 2),
                            items: [
                              for (final entry in field.options!.entries)
                                DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value,
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: _saving || _submittedPayload != null
                                ? null
                                : (value) => setState(() {
                                      _choices[field.keyName] = value ?? '';
                                    }),
                            validator: (value) => _required(field) &&
                                    (value == null || value.isEmpty)
                                ? 'Choose ${field.label.toLowerCase()}.'
                                : null,
                          )
                        : TextFormField(
                            key: ValueKey('core-field-${field.keyName}'),
                            controller: _controllers[field.keyName],
                            enabled: !_saving && _submittedPayload == null,
                            maxLines: field.multiline ? 3 : 1,
                            maxLength: field.multiline ? 1500 : 240,
                            keyboardType: field.integer
                                ? TextInputType.number
                                : field.money
                                    ? const TextInputType.numberWithOptions(
                                        decimal: true)
                                    : field.email
                                        ? TextInputType.emailAddress
                                        : field.url
                                            ? TextInputType.url
                                            : TextInputType.text,
                            decoration: InputDecoration(
                                labelText: field.label,
                                hintText: field.hint,
                                counterText: ''),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (_required(field) && text.isEmpty) {
                                return 'Enter ${field.label.toLowerCase()}.';
                              }
                              if (text.isEmpty) return null;
                              if (field.integer &&
                                  (int.tryParse(text) == null ||
                                      int.parse(text) < 0)) {
                                return 'Enter a non-negative whole number.';
                              }
                              if (field.list &&
                                  text.split(',').any((item) =>
                                      !RegExp(r'^[a-z][a-z0-9_.-]{1,100}$')
                                          .hasMatch(item.trim()))) {
                                return 'Use comma-separated capability keys.';
                              }
                              if (field.money &&
                                  parseCoreMoneyMicros(text) == null) {
                                return 'Use a non-negative amount up to 100,000,000 with at most 6 decimal places.';
                              }
                              if (field.email &&
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(text)) {
                                return 'Enter a valid email address.';
                              }
                              if (field.url) {
                                final uri = Uri.tryParse(text);
                                if (uri == null ||
                                    uri.scheme != 'https' ||
                                    uri.host.isEmpty ||
                                    uri.userInfo.isNotEmpty) {
                                  return 'Enter an HTTPS document link.';
                                }
                              }
                              if (field.keyName == 'slug' &&
                                  !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
                                      .hasMatch(text)) {
                                return 'Use lowercase words joined with hyphens.';
                              }
                              return null;
                            },
                          ),
                  ),
                if (_failure != null)
                  _Notice(
                      title: 'Action needs attention',
                      message: _failure!.message),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  Flexible(
                    child: FilledButton(
                      key: const ValueKey('core-submit'),
                      onPressed: _saving || _confirming ? null : _save,
                      child: Text(_saving ? 'Saving…' : widget.submitLabel),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}

const _recordFields = <String, String>{
  'display_name': 'Client',
  'name': 'Name',
  'title': 'Title',
  'company_name': 'Company',
  'client_name': 'Client',
  'industry': 'Industry',
  'provider': 'Provider',
  'provider_key': 'Provider',
  'provider_name': 'Model provider',
  'model': 'Model',
  'model_id': 'Model ID',
  'region': 'Region',
  'configured_eligible': 'Routing eligible',
  'runtime_tested_at': 'Runtime tested',
  'runtime_verified_at': 'Runtime passed',
  'runtime_evidence_state': 'Runtime evidence',
  'availability_reason': 'Availability',
  'mode': 'Routing mode',
  'policy_version': 'Policy version',
  'enabled': 'Routing enabled',
  'routing_eligible': 'Routing eligible',
  'fallback_enabled': 'Fallback enabled',
  'configured_eligible_models': 'Eligible models',
  'verified_eligible_models': 'With runtime evidence',
  'fresh_verified_eligible_models': 'Verified within 24 hours',
  'conversational_models': 'Conversational models',
  'models_returned': 'Models shown',
  'policy_observed_at': 'Policy observed',
  'policy_updated_at': 'Policy changed',
  'catalog_observed_at': 'Catalog observed',
  'state': 'State',
  'status': 'Status',
  'health': 'Health',
  'lifecycle_state': 'Lifecycle',
  'verification_state': 'Verification',
  'source': 'Source',
  'evidence_source': 'Evidence',
  'why': 'Why',
  'reason': 'Reason',
  'action': 'Next action',
  'next_action': 'Next action',
  'risk': 'Risk',
  'description': 'Details',
  'impact': 'Impact',
  'priority': 'Priority',
  'severity': 'Severity',
  'role': 'Role',
  'event_type': 'Action',
  'organization_id': 'Organization ID',
  'actor_user_id': 'Actor ID',
  'user_id': 'User ID',
  'event_hash': 'Audit evidence',
  'expires_at': 'Expires',
  'email': 'Email',
  'version': 'Version',
  'app_version': 'App version',
  'source_commit_sha': 'Source version',
  'source_sha': 'Source version',
  'source_tree_sha': 'Source tree',
  'provider_deployment_id': 'Provider deployment',
  'provider_state': 'Provider state',
  'audit_receipt_id': 'Audit receipt',
  'runtime_verified': 'Runtime verification',
  'owner_flow_verified': 'Owner flow verification',
  'client_flow_verified': 'Client flow verification',
  'production_verified': 'Production verification',
  'supabase_project_ref': 'Database project',
  'supabase_migration_version': 'Applied migration version',
  'supabase_migration_name': 'Applied migration',
  'supabase_source_file_version': 'Source migration version',
  'supabase_source_sha256': 'Migration source digest',
  'supabase_statements_sha256': 'Applied statements digest',
  'verification_status': 'Verification',
  'deployment_url': 'Deployment',
  'last_verified_at': 'Last verified',
  'verified_at': 'Verified',
  'last_seen_at': 'Last seen',
  'last_active': 'Last active',
  'created_at': 'Created',
  'kind': 'Evidence type',
  'content_sha256': 'Content SHA-256',
  'project_id': 'Project ID',
  'task_key': 'Task ID',
  'queued_at': 'Queued',
  'attempts': 'Attempts',
  'updated_at': 'Updated',
  'occurred_at': 'Occurred',
  'deadline': 'Deadline',
  'due_at': 'Due',
  'renews_at': 'Renewal',
  'renews_on': 'Renewal',
  'renewal_on': 'Renewal',
  'due_on': 'Due',
  'source_kind': 'Source',
  'evidence_state': 'Evidence state',
  'evidence_ref': 'Evidence',
  'mrr_micros': 'Recorded MRR',
  'arr_micros': 'Recorded ARR',
  'remaining_micros': 'Remaining balance',
  'currency': 'Currency',
  'monthly_fee_micros': 'Monthly fee',
  'total_micros': 'Total',
  'amount_micros': 'Amount',
  'estimated_cost_micros': 'Estimated cost',
  'billed_cost_micros': 'Billed cost',
  'request_limit': 'Monthly cloud-chat requests',
  'request_admission_policy': 'Cloud-chat request policy',
  'request_admission_enabled': 'Cloud-chat request control',
  'request_admission_state': 'Request admission',
  'request_admission_started_at': 'First enabled (UTC)',
  'request_effective_from': 'Counting from (UTC)',
  'request_window_start': 'Window starts (UTC)',
  'request_reset_at': 'Resets (UTC)',
  'requests_admitted': 'Admitted cloud-chat requests',
  'requests_remaining': 'Requests remaining',
  'token_limit': 'Commercial token allowance',
  'budget_micros': 'Commercial cost allowance',
  'included_allowance_micros': 'Included cost allowance',
  'requests_recorded': 'Recorded requests',
  'tokens_recorded': 'Recorded tokens',
  'coverage': 'Coverage',
  'evidence_note': 'Evidence coverage',
  'local_evidence_note': 'Local usage coverage',
  'last_observed_at': 'Last observed',
  'requests': 'Requests',
  'succeeded': 'Successful requests',
  'tokens': 'Total tokens',
  'requests_with_cost': 'Requests with estimated cost',
  'input_tokens': 'Input tokens',
  'output_tokens': 'Output tokens',
  'local_requests': 'Local requests',
  'invoice_number': 'Invoice',
  'reference': 'Reference',
  'outcome': 'Outcome',
  'summary': 'Summary',
  'notes': 'Notes',
};

String _displayValue(String key, Object? value, {String currency = ''}) {
  if (value == null) return 'Unknown';
  if (key == 'state' && value == 'needs_decision') return 'Needs decision';
  if (key == 'availability_reason') return _modelAvailability(value);
  if (const {
    'configured_eligible',
    'enabled',
    'routing_eligible',
    'fallback_enabled'
  }.contains(key)) {
    return value == true
        ? 'Yes'
        : value == false
            ? 'No'
            : 'Unknown';
  }
  if (key == 'request_admission_enabled') {
    return value == true ? 'On' : 'Off';
  }
  if (key == 'request_admission_policy') {
    return switch (value) {
      'block' => 'Block at monthly cloud-chat request limit',
      'record_only' => 'Record requests only',
      _ => 'Unknown',
    };
  }
  if (key == 'request_admission_state') {
    return switch (value) {
      'enforcing' => 'Enforced',
      'limit_reached' => 'Monthly request limit reached',
      'not_enrolled' => 'Not enabled',
      'policy_unavailable' => 'Blocked: request policy needs attention',
      _ => 'Unknown',
    };
  }
  if (const {
    'runtime_verified',
    'owner_flow_verified',
    'client_flow_verified',
    'production_verified',
  }.contains(key)) {
    return value == true ? 'Verified' : 'Not verified';
  }
  if (key.endsWith('_micros')) {
    if (currency.isEmpty) return 'Unknown';
    return '$currency ${formatCoreMoneyMicros(value)}';
  }
  return coreText(value);
}

String _humanizeRecordAction(Object? value) {
  final words = coreText(value, '')
      .replaceFirst(RegExp(r'^core[.]'), '')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .trim();
  return words.isEmpty ? '' : '${words[0].toUpperCase()}${words.substring(1)}';
}

String _recordTitle(PandoraCoreRecord row, String fallback) {
  if (coreText(row['event_type'], '').isNotEmpty) {
    return _humanizeRecordAction(row['event_type']);
  }
  for (final key in const [
    'display_name',
    'title',
    'name',
    'company_name',
    'subject',
    'label',
    'provider',
    'provider_key',
    'model',
    'model_id',
    'invoice_number',
    'email',
    'summary',
    'currency',
  ]) {
    final value = coreText(row[key], '');
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String _modelAvailability(Object? reason) => switch (reason) {
      'model_not_active' => 'Model not active',
      'runtime_verification_failed' => 'Runtime verification failed',
      'runtime_not_verified' => 'Runtime not verified',
      'not_routable' => 'Routing unavailable',
      'invocation_unavailable' => 'Invocation unavailable',
      'eligible_by_current_routing_policy' => 'Eligible for Auto routing',
      _ => 'Availability unknown',
    };

String _modelSubtitle(PandoraCoreRecord row) => [
      coreText(row['provider_name'], coreText(row['provider'], '')),
      coreText(row['model_id'], ''),
      switch (row['verification_state']) {
        'passed' => 'Runtime passed',
        'failed' => 'Runtime failed',
        _ => 'Runtime not verified',
      },
      switch (row['runtime_evidence_state']) {
        'fresh' => 'Evidence within 24 hours',
        'stale' => 'Stale runtime evidence',
        _ => 'Evidence time unknown',
      },
    ].where((value) => value.isNotEmpty).join(' · ');

String _releaseObservationState(PandoraCoreRecord row) {
  final runtime = row['runtime_verified'];
  final owner = row['owner_flow_verified'];
  final client = row['client_flow_verified'];
  final production = row['production_verified'];
  if (production == true) return 'Production verified';
  if (runtime == true && owner == true && client == true) {
    return 'Runtime and user flows verified';
  }

  final state = coreText(row['provider_state'],
          coreText(row['status'], coreText(row['state'], '')))
      .trim()
      .toLowerCase();
  if (state == 'ready') return 'Deployed · verification pending';
  if (state.isEmpty) return 'Deployment observed · verification pending';
  return 'Deployment ${_humanizeRecordAction(state)}';
}

String _releaseVerificationSummary(PandoraCoreRecord row) {
  final runtime = row['runtime_verified'];
  final owner = row['owner_flow_verified'];
  final client = row['client_flow_verified'];
  if (runtime == false && owner == false && client == false) {
    return 'Runtime and user flows not verified';
  }
  if (runtime == true && owner == true && client == true) {
    return 'Runtime and user flows verified';
  }
  return [
    runtime == true
        ? 'Runtime verified'
        : runtime == false
            ? 'Runtime not verified'
            : 'Runtime verification unavailable',
    owner == true && client == true
        ? 'User flows verified'
        : owner == false || client == false
            ? 'User flows not verified'
            : 'User-flow verification unavailable',
  ].join(' · ');
}

String _usageSubtitle(PandoraCoreRecord row, String? scopeLabel) {
  final currency = coreText(row['currency'], '');
  final estimates = row['estimated_cost_micros'];
  final billed = row['billed_cost_micros'];
  return [
    if (scopeLabel != null) scopeLabel,
    if (row['requests'] is num) '${row['requests']} requests',
    if (row['input_tokens'] is num) '${row['input_tokens']} input tokens',
    if (row['output_tokens'] is num) '${row['output_tokens']} output tokens',
    if (row['input_tokens'] == null &&
        row['output_tokens'] == null &&
        row['tokens'] is num)
      '${row['tokens']} tokens',
    if (estimates is num && currency.isNotEmpty)
      'Estimated $currency ${formatCoreMoneyMicros(estimates)}',
    if (billed is num && currency.isNotEmpty)
      'Billed $currency ${formatCoreMoneyMicros(billed)}',
    if (estimates == null && billed == null)
      'Cost unavailable'
    else if (currency.isEmpty)
      'Cost currency unavailable',
  ].join(' · ');
}

String _allowanceSubtitle(PandoraCoreRecord row) => [
      if (row['request_limit'] is num)
        '${row['request_limit']} monthly cloud-chat requests',
      if (row['requests_admitted'] is num)
        '${row['requests_admitted']} admitted',
      if (row['requests_remaining'] is num)
        '${row['requests_remaining']} remaining',
      if (row['token_limit'] is num) '${row['token_limit']} commercial tokens',
      if (row['budget_micros'] is num &&
          coreText(row['currency'], '').isNotEmpty)
        'Commercial cost allowance ${_displayValue('budget_micros', row['budget_micros'], currency: coreText(row['currency']))}',
      if (row['request_admission_enabled'] == false)
        'Request blocking not enabled',
    ].join(' · ');

class _RecordTile extends StatelessWidget {
  const _RecordTile(
      {required this.row,
      required this.onTap,
      this.isDecision = false,
      this.domain,
      this.scopeLabel,
      this.actorLabel});
  final PandoraCoreRecord row;
  final VoidCallback onTap;
  final bool isDecision;
  final String? domain;
  final String? scopeLabel;
  final String? actorLabel;
  @override
  Widget build(BuildContext context) {
    final isRelease = const {'candidate', 'canonical_production'}
        .contains(row['release_observation_kind']);
    final isAudit = domain == 'audit';
    final isOperator = domain == 'operators';
    final isModel = domain == 'models';
    final isAutomation = domain == 'automations';
    final isEvidence = domain == 'evidence';
    final recordedAt = DateTime.tryParse(coreText(row['created_at'], ''));
    final queuedAt = DateTime.tryParse(coreText(row['queued_at'], ''));
    final isRecordedEvidence =
        isEvidence && coreText(row['id'], '').isNotEmpty && recordedAt != null;
    final isUsage = domain == 'usage';
    final isAllowance = domain == 'usage_allowances';
    final evidenceKind = _humanizeRecordAction(row['kind']);
    final title = isAutomation
        ? row['title_state'] == 'recorded'
            ? coreText(row['name'], 'Task title unavailable')
            : 'Task title unavailable'
        : isEvidence
            ? evidenceKind.isEmpty
                ? 'Evidence record'
                : evidenceKind
            : isUsage
                ? [coreText(row['provider'], ''), coreText(row['model'], '')]
                    .where((value) => value.isNotEmpty)
                    .join(' · ')
                : isAllowance
                    ? '${scopeLabel ?? 'Client'} allowances'
                    : isOperator
                        ? '${_humanizeRecordAction(row['role']).isEmpty ? 'Operator' : _humanizeRecordAction(row['role'])} access'
                        : isAudit
                            ? _humanizeRecordAction(
                                row['event_type'] ?? row['action'])
                            : _recordTitle(row, 'Recorded item');
    final subtitle = isAutomation
        ? [
            if (coreText(row['client_name'], '').isNotEmpty)
              coreText(row['client_name']),
            if (queuedAt != null)
              'Queued ${MaterialLocalizations.of(context).formatShortDate(queuedAt.toLocal())}',
          ].join(' · ')
        : isEvidence
            ? [
                if (row['organization_id'] != null && scopeLabel != null)
                  scopeLabel!,
                if (recordedAt != null)
                  MaterialLocalizations.of(context)
                      .formatShortDate(recordedAt.toLocal()),
              ].join(' · ')
            : isModel
                ? _modelSubtitle(row)
                : isUsage
                    ? _usageSubtitle(row, scopeLabel)
                    : isAllowance
                        ? _allowanceSubtitle(row)
                        : isAudit || isOperator
                            ? [
                                if (actorLabel != null) actorLabel!,
                                if (scopeLabel != null) scopeLabel!,
                                if (isOperator && row['expires_at'] != null)
                                  'Expires ${coreText(row['expires_at'])}',
                                if (isAudit && row['created_at'] != null)
                                  coreText(row['created_at']),
                              ].join(' · ')
                            : isRelease
                                ? [
                                    coreText(row['summary'], ''),
                                    if (row['evidence_state'] == 'stale')
                                      'Stale provider evidence',
                                    _releaseVerificationSummary(row),
                                  ]
                                    .where((value) => value.isNotEmpty)
                                    .join(' · ')
                                : [
                                    for (final key in const [
                                      'client_name',
                                      'why',
                                      'reason',
                                      'next_action',
                                      'summary',
                                      'provider',
                                      'model',
                                      'updated_at',
                                      'occurred_at',
                                      'source_kind',
                                      'evidence_state',
                                    ])
                                      if (coreText(row[key], '').isNotEmpty)
                                        coreText(row[key], ''),
                                    for (final key in const [
                                      'mrr_micros',
                                      'monthly_fee_micros',
                                      'amount_micros',
                                      'estimated_cost_micros'
                                    ])
                                      if (row[key] != null)
                                        _displayValue(key, row[key],
                                            currency:
                                                coreText(row['currency'], '')),
                                  ].take(3).join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      title: Text(
          title.isEmpty
              ? isUsage
                  ? 'Recorded model usage'
                  : 'Audit record'
              : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: _ink, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle,
              maxLines: isUsage || isAllowance || isModel ? 5 : 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12)),
      trailing: isAutomation
          ? _StatePill(_humanizeRecordAction(row['state']).isEmpty
              ? 'State unavailable'
              : _humanizeRecordAction(row['state']))
          : isEvidence
              ? isRecordedEvidence
                  ? const _StatePill('Recorded')
                  : null
              : isRelease
                  ? _StatePill(_releaseObservationState(row))
                  : isUsage ||
                          (isAllowance &&
                              row['request_admission_state'] == null)
                      ? null
                      : isAllowance
                          ? _StatePill(_displayValue('request_admission_state',
                              row['request_admission_state']))
                          : isAudit &&
                                  row['state'] == null &&
                                  row['status'] == null &&
                                  row['outcome'] == null
                              ? null
                              : _StatePill(isDecision
                                  ? row['needs_decision'] == true ||
                                          row['state'] == 'needs_decision'
                                      ? 'Needs decision'
                                      : row['state'] ??
                                          row['status'] ??
                                          'Decision state unavailable'
                                  : row['state'] ??
                                      row['status'] ??
                                      row['verification_state'] ??
                                      row['outcome']),
      onTap: onTap,
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line)),
        child: child,
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 9),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _ink, fontSize: 16, fontWeight: FontWeight.w700))),
          if (action != null)
            TextButton(
                onPressed: onAction,
                child: Text(action!, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _Signal extends StatelessWidget {
  const _Signal(this.label, this.value);
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${coreText(value)} $label',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(coreText(value),
              style: const TextStyle(
                  color: _ink, fontSize: 19, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11.5)),
        ]),
      );
}

class _StatePill extends StatelessWidget {
  const _StatePill(this.value);
  final Object? value;
  @override
  Widget build(BuildContext context) {
    final text = coreText(value, 'Not verified').replaceAll('_', ' ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFF23272D),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10.5)),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.label, this.value, {this.preserveExact = false});
  final String label;
  final Object? value;
  final bool preserveExact;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(color: _muted, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
              flex: 3,
              child: Text(
                  preserveExact
                      ? coreText(value)
                      : coreText(value).replaceAll('_', ' '),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: _ink, fontSize: 12))),
        ]),
      );
}

class _Action extends StatelessWidget {
  const _Action(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: plpInk,
          side: const BorderSide(color: _line),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(message,
            style: const TextStyle(color: _muted, height: 1.45, fontSize: 13)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(
      {required this.title, required this.message, this.action, this.onAction});
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(message, style: const TextStyle(color: _muted, height: 1.4)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class _PlpMissing extends StatelessWidget {
  const _PlpMissing(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: const TextStyle(color: plpMuted, fontSize: 13, height: 1.4),
      );
}
