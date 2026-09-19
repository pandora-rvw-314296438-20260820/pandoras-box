
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../simple/ask_pandora_screen.dart';

// workspace_profile controls presentation only; authorization remains server-enforced.
enum BatallaWorkspaceProfile {
  attyBatalla,
  dan,
  secretary,
}

extension BatallaWorkspaceProfilePresentation on BatallaWorkspaceProfile {
  String get key => switch (this) {
        BatallaWorkspaceProfile.attyBatalla => 'atty_batalla',
        BatallaWorkspaceProfile.dan => 'dan',
        BatallaWorkspaceProfile.secretary => 'secretary',
      };

  String get displayName => switch (this) {
        BatallaWorkspaceProfile.attyBatalla => 'Atty. Batalla',
        BatallaWorkspaceProfile.dan => 'Dan',
        BatallaWorkspaceProfile.secretary => 'Secretary',
      };

  String get homeTitle => switch (this) {
        BatallaWorkspaceProfile.attyBatalla => 'Executive Command Center',
        BatallaWorkspaceProfile.dan => "Dan's Desk",
        BatallaWorkspaceProfile.secretary => 'Secretary Quick Desk',
      };
}

BatallaWorkspaceProfile batallaWorkspaceProfileFromKey(String value) =>
    switch (value.trim().toLowerCase()) {
      'dan' => BatallaWorkspaceProfile.dan,
      'secretary' => BatallaWorkspaceProfile.secretary,
      _ => BatallaWorkspaceProfile.attyBatalla,
    };

class BatallaNavItem {
  const BatallaNavItem(
    this.label,
    this.routeSlug,
    this.surface,
    this.icon,
  );

  final String label;
  final String routeSlug;
  final String surface;
  final IconData icon;
}

const batallaNavigation = <BatallaNavItem>[
  BatallaNavItem('Home', 'home', 'enterprise_overview', Icons.home_rounded),
  BatallaNavItem('Today', 'today', 'enterprise_overview', Icons.today_rounded),
  BatallaNavItem('Matters', 'matters', 'enterprise_data', Icons.gavel_rounded),
  BatallaNavItem(
    'Clients & Intake',
    'clients-intake',
    'enterprise_workflows',
    Icons.person_add_alt_1_rounded,
  ),
  BatallaNavItem(
    'Hearings & Calendar',
    'hearings-calendar',
    'enterprise_workflows',
    Icons.calendar_month_rounded,
  ),
  BatallaNavItem(
    'Reviews & Decisions',
    'reviews-decisions',
    'enterprise_workflows',
    Icons.fact_check_rounded,
  ),
  BatallaNavItem(
    'Documents & Evidence',
    'documents-evidence',
    'enterprise_data',
    Icons.description_rounded,
  ),
  BatallaNavItem(
    'Paper Files',
    'paper-files',
    'enterprise_data',
    Icons.folder_copy_rounded,
  ),
  BatallaNavItem(
    'Scan & File',
    'scan-file',
    'enterprise_workflows',
    Icons.document_scanner_rounded,
  ),
  BatallaNavItem(
    'Calls & Communications',
    'calls-communications',
    'enterprise_workflows',
    Icons.call_rounded,
  ),
  BatallaNavItem(
    'Print Center',
    'print-center',
    'enterprise_workflows',
    Icons.print_rounded,
  ),
  BatallaNavItem(
    'Billing & Finance',
    'billing-finance',
    'enterprise_analytics',
    Icons.receipt_long_rounded,
  ),
  BatallaNavItem(
    'Reports',
    'reports',
    'enterprise_analytics',
    Icons.assessment_rounded,
  ),
  BatallaNavItem(
    'Team & Access',
    'team-access',
    'enterprise_security',
    Icons.group_rounded,
  ),
  BatallaNavItem(
    'Activity & Audit',
    'activity-audit',
    'enterprise_logs',
    Icons.history_rounded,
  ),
  BatallaNavItem(
    'Settings',
    'settings',
    'enterprise_settings',
    Icons.settings_rounded,
  ),
  BatallaNavItem(
    'System / Developer',
    'system-developer',
    'enterprise_code',
    Icons.code_rounded,
  ),
];

class BatallaWorkspaceScreen extends StatefulWidget {
  const BatallaWorkspaceScreen({
    super.key,
    this.initialRouteSlug = 'home',
    this.profileKey = 'atty_batalla',
    required this.onBackToWorkspaces,
  });

  final String initialRouteSlug;
  final String profileKey;
  final VoidCallback onBackToWorkspaces;

  @override
  State<BatallaWorkspaceScreen> createState() => _BatallaWorkspaceScreenState();
}

class _BatallaWorkspaceScreenState extends State<BatallaWorkspaceScreen> {
  static const _workspaceKey = 'batalla-associates';
  static const _workspaceName = 'Batalla & Associates';

  late String _selectedSlug;
  bool _recentExpanded = true;
  bool _recentLoading = false;
  bool _recentLoaded = false;
  String? _recentError;
  List<PandoraIntelligenceThread> _recentThreads =
      const <PandoraIntelligenceThread>[];

  BatallaWorkspaceProfile get _profile =>
      batallaWorkspaceProfileFromKey(widget.profileKey);

  BatallaNavItem get _selectedItem => batallaNavigation.firstWhere(
        (item) => item.routeSlug == _selectedSlug,
        orElse: () => batallaNavigation.first,
      );

  @override
  void initState() {
    super.initState();
    _selectedSlug = batallaNavigation.any(
      (item) => item.routeSlug == widget.initialRouteSlug,
    )
        ? widget.initialRouteSlug
        : 'home';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_recentLoaded) {
      _recentLoaded = true;
      unawaited(_loadRecentThreads());
    }
  }

  Future<void> _loadRecentThreads({bool refresh = false}) async {
    if (_recentLoading) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    setState(() {
      _recentLoading = true;
      if (refresh) _recentError = null;
    });
    try {
      final threads = await intelligence.recentThreadsForWorkspace(
        _workspaceKey,
        limit: 8,
      );
      if (!mounted) return;
      setState(() {
        _recentThreads = threads;
        _recentError = null;
      });
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() => _recentError = error.message);
    } finally {
      if (mounted) setState(() => _recentLoading = false);
    }
  }

  Map<String, Object?> _contextFor(BatallaNavItem item) =>
      <String, Object?>{
        'surface': item.surface,
        'route': '/enterprise/workspaces/batalla-associates/' + item.routeSlug,
        'capabilities': const <String>[],
        'identityScope': 'enterprise_workspace',
        'selectedObject': <String, String>{
          'workspaceKey': _workspaceKey,
          'workspaceName': _workspaceName,
          'workspaceProfile': _profile.key,
          'section': item.label,
          'sectionSlug': item.routeSlug,
          'officeKind': 'law_business_office',
        },
      };

  void _select(String routeSlug) {
    if (_selectedSlug == routeSlug) return;
    setState(() => _selectedSlug = routeSlug);
  }

  Future<void> _openPandora({PandoraIntelligenceThread? thread}) async {
    final item = _selectedItem;
    final key = GlobalKey<AskPandoraScreenState>();
    final future = Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => AskPandoraScreen(
          key: key,
          enterpriseContext: _contextFor(item),
          onHome: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    if (thread != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = key.currentState;
        if (state != null) unawaited(state.loadThread(thread.id));
      });
    }
    await future;
    if (mounted) unawaited(_loadRecentThreads(refresh: true));
  }

  Future<void> _showNavigationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0D10),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .92,
        child: _navigationPanel(
          onSelected: (slug) {
            Navigator.of(sheetContext).pop();
            _select(slug);
          },
        ),
      ),
    );
  }

  Widget _navigationPanel({
    required ValueChanged<String> onSelected,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/workspaces/batalla.webp',
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Batalla & Associates',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Law & Business Offices',
                        style: TextStyle(
                          color: Color(0xFFA7A8AC),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'All workspaces',
                  onPressed: widget.onBackToWorkspaces,
                  icon: const Icon(Icons.apps_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x24FFFFFF)),
          ExpansionTile(
            key: const ValueKey<String>('batalla-recent-chats'),
            initiallyExpanded: _recentExpanded,
            onExpansionChanged: (value) =>
                setState(() => _recentExpanded = value),
            tilePadding: const EdgeInsets.symmetric(horizontal: 18),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            leading: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
            title: const Text(
              'Recent chats',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            children: [
              if (_recentLoading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (_recentError != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.refresh_rounded, size: 18),
                  title: const Text('Retry recent chats'),
                  subtitle: Text(
                    _recentError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _loadRecentThreads(refresh: true),
                )
              else if (_recentThreads.isEmpty)
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  title: Text('No Batalla chats yet'),
                  subtitle: Text('Workspace-scoped conversations appear here.'),
                )
              else
                for (final thread in _recentThreads)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.chat_rounded, size: 17),
                    title: Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openPandora(thread: thread),
                  ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 6),
            child: Text(
              'LAW & BUSINESS OFFICE',
              style: TextStyle(
                color: Color(0xFF8F9196),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .9,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                for (final item in batallaNavigation)
                  ListTile(
                    key: ValueKey<String>(
                      'batalla-nav-' + item.routeSlug,
                    ),
                    dense: true,
                    selected: item.routeSlug == _selectedSlug,
                    selectedTileColor: const Color(0x18D5A24F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(item.icon, size: 20),
                    title: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => onSelected(item.routeSlug),
                  ),
              ],
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          final body = _mainContent(showNavigationButton: !wide);
          if (!wide) return body;
          return ColoredBox(
            color: const Color(0xFF080A0D),
            child: Row(
              children: [
                SizedBox(
                  width: 286,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B0D10),
                      border: Border(
                        right: BorderSide(color: Color(0x24FFFFFF)),
                      ),
                    ),
                    child: SafeArea(
                      child: _navigationPanel(onSelected: _select),
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          );
        },
      );

  Widget _mainContent({required bool showNavigationButton}) {
    final item = _selectedItem;
    return ColoredBox(
      color: const Color(0xFF080A0D),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
              child: Row(
                children: [
                  if (showNavigationButton)
                    IconButton(
                      key: const ValueKey<String>('batalla-open-navigation'),
                      tooltip: 'Law office navigation',
                      onPressed: _showNavigationSheet,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _profile.displayName + ' · Batalla & Associates',
                          style: const TextStyle(
                            color: Color(0xFFA7A8AC),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey<String>('batalla-ask-pandora'),
                    onPressed: _openPandora,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Ask Pandora'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x24FFFFFF)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
                child: item.routeSlug == 'home'
                    ? _home(_profile)
                    : _section(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _home(BatallaWorkspaceProfile profile) => switch (profile) {
        BatallaWorkspaceProfile.attyBatalla => _attyHome(),
        BatallaWorkspaceProfile.dan => _danHome(),
        BatallaWorkspaceProfile.secretary => _secretaryHome(),
      };

  Widget _attyHome() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(
            'Executive Command Center',
            'The work item comes first. Counts are secondary.',
          ),
          const SizedBox(height: 16),
          _quickActions(
            const <(String, String)>[
              ('Today', 'today'),
              ('Cases', 'matters'),
              ('Hearings', 'hearings-calendar'),
              ('Review', 'reviews-decisions'),
              ('Print', 'print-center'),
              ('Monthly Report', 'reports'),
            ],
          ),
          const SizedBox(height: 16),
          _panel(
            title: 'What needs my decision?',
            subtitle:
                'Decision items show the actual legal work before summary counts.',
            children: [
              _fieldGrid(const <String>[
                'Client / intake identity',
                "Dan's recommendation",
                'Urgency',
                'Who is waiting',
                'Physical folder location',
                'Who owns the next action',
                'What can be printed now',
              ]),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _select('reviews-decisions'),
                      icon: const Icon(Icons.fact_check_rounded),
                      label: const Text('Open Review'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _select('print-center'),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Print Packet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  Widget _danHome() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(
            "Dan's Desk",
            'Prepared work and recommendations remain visibly separate from final legal decisions.',
          ),
          const SizedBox(height: 16),
          _quickActions(
            const <(String, String)>[
              ('My Cases', 'matters'),
              ('Reviews for Me', 'reviews-decisions'),
              ('Needs Review', 'reviews-decisions'),
              ('My Recommendations', 'reviews-decisions'),
              ('Relationships & Referrals', 'clients-intake'),
              ('Hearings', 'hearings-calendar'),
              ('Knowledge', 'documents-evidence'),
              ('Print My Packet', 'print-center'),
            ],
          ),
          const SizedBox(height: 16),
          _panel(
            title: 'Recommendation authorship',
            subtitle:
                "Dan's author, revision and status stay attached to every recommendation.",
            children: const [
              _InfoLine(
                icon: Icons.edit_note_rounded,
                text:
                    "A recommendation is not Atty. Batalla's final legal decision.",
              ),
              _InfoLine(
                icon: Icons.hub_rounded,
                text:
                    'Relationships and referrals never grant matter access or authorization.',
              ),
            ],
          ),
        ],
      );

  Widget _secretaryHome() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(
            'Secretary Quick Desk',
            'Minimal typing, controlled choices, ordinary-language errors and safe retries.',
          ),
          const SizedBox(height: 16),
          _quickActions(
            const <(String, String)>[
              ('New Client', 'clients-intake'),
              ('Calls', 'calls-communications'),
              ('Schedule', 'hearings-calendar'),
              ('Scan', 'scan-file'),
              ('Print', 'print-center'),
              ('Find Folder', 'paper-files'),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey<String>('batalla-secretary-unsure'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => _select('reviews-decisions'),
            icon: const Icon(Icons.help_outline_rounded),
            label: const Text("I'm not sure — send this for checking"),
          ),
          const SizedBox(height: 16),
          _panel(
            title: 'Front-office safety flow',
            children: const [
              _StepLine(number: '1', text: 'Write it down'),
              _StepLine(number: '2', text: 'Please check'),
              _StepLine(number: '3', text: 'Save and add to the office queue'),
            ],
          ),
        ],
      );

  Widget _section(BatallaNavItem item) {
    final spec = _spec(item.routeSlug);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(item.label, spec.summary),
        const SizedBox(height: 16),
        _panel(
          title: spec.primaryTitle,
          children: [
            for (final value in spec.primary)
              _InfoLine(icon: Icons.chevron_right_rounded, text: value),
          ],
        ),
        if (spec.secondary.isNotEmpty) ...[
          const SizedBox(height: 14),
          _panel(
            title: spec.secondaryTitle,
            children: [
              for (final value in spec.secondary)
                _InfoLine(icon: Icons.chevron_right_rounded, text: value),
            ],
          ),
        ],
        if (spec.boundary != null) ...[
          const SizedBox(height: 14),
          _boundaryCard(spec.boundary!),
        ],
      ],
    );
  }

  _BatallaSectionSpec _spec(String slug) => switch (slug) {
        'today' => const _BatallaSectionSpec(
            summary:
                'A daily operating sheet, not a decorative dashboard.',
            primaryTitle: 'Today',
            primary: <String>[
              'Pending decisions',
              'Hearings and deadlines',
              'Waiting consultations',
              'Calls to return',
              'Folders out',
              'Documents waiting for scan or clearance',
              'Dan reviews',
              'Overdue work',
            ],
          ),
        'matters' => const _BatallaSectionSpec(
            summary:
                'Matter is the canonical legal object. Cases remains familiar wording inside personal Home views.',
            primaryTitle: 'Matter Cover Sheet',
            primary: <String>[
              'Client',
              'Matter number',
              'Responsible lawyer',
              'Stage',
              'Next action and owner',
              'Next deadline',
              'Confidentiality',
              'Physical-folder location and holder',
              'Print Complete File',
            ],
            secondaryTitle: 'Inside a Matter',
            secondary: <String>[
              'Cover Sheet',
              'Parties',
              'Team & Access',
              'Chronology',
              'Deadlines & Events',
              'Tasks',
              'Documents',
              'Evidence',
              'Notes',
              'Communications',
              'Paper Folder',
              'Client Sharing',
              'Time & Expenses',
              'Billing',
              'History / Audit',
              'Print Packet',
              'Close Matter',
            ],
            boundary:
                'Client sharing is managed inside the Matter. The Client Portal remains a separate security and visual boundary.',
          ),
        'clients-intake' => const _BatallaSectionSpec(
            summary:
                'One front-office journey from inquiry through consultation and conflict preparation.',
            primaryTitle: 'Client & intake flow',
            primary: <String>[
              'Inquiries',
              'Prospective clients',
              'Consultations',
              'Contacts and organizations',
              'Adverse parties',
              'Referrals',
              'Conflict preparation',
            ],
            secondaryTitle: 'Conflict checking',
            secondary: <String>[
              'Broader approved legal search',
              'Candidate matches, not automatic conclusions',
              'Recommendation with evidence',
              'Authorized lawyer records the final decision',
            ],
            boundary:
                'Conflict checking is a legal review workflow, not ordinary search. Candidate matches never become automatic conflict conclusions.',
          ),
        'hearings-calendar' => const _BatallaSectionSpec(
            summary:
                'Hearings, consultations, deadlines and ownership of every next calendar action.',
            primaryTitle: 'Calendar work',
            primary: <String>[
              'Hearings',
              'Consultations',
              'Deadlines',
              'Required preparation',
              'Responsible lawyer or staff owner',
              'Confirmation state',
              'Next action',
            ],
          ),
        'reviews-decisions' => const _BatallaSectionSpec(
            summary:
                'Preparing, recommending, recording and making a legally significant decision remain distinct acts.',
            primaryTitle: 'Decision work',
            primary: <String>[
              "Atty. Batalla's decision queue",
              "Dan's recommendations",
              'Office Needs Review items',
              'Conflict reviews',
              'Work awaiting lawyer authority',
            ],
            boundary:
                "Recommendation authorship and revision history stay separate from Atty. Batalla's final decision.",
          ),
        'documents-evidence' => const _BatallaSectionSpec(
            summary:
                'Digital documents and evidence stay tied to the Matter, source, version and handling history.',
            primaryTitle: 'Document & evidence work',
            primary: <String>[
              'Matter documents',
              'Evidence index',
              'Drafts and final versions',
              'Source and provenance',
              'Confidentiality',
              'Review state',
              'Client-sharing state',
            ],
          ),
        'paper-files' => const _BatallaSectionSpec(
            summary:
                'Physical folders are first-class office records, not attachments to a document module.',
            primaryTitle: 'Physical folder control',
            primary: <String>[
              'Physical folder code and volume',
              'Cabinet / drawer / shelf',
              'Current holder',
              'Check-out and return',
              'Relocation',
              'Missing / found',
              'Working copies',
              'Archived retrieval',
              'Court or client-held originals',
              'Folder movements',
              'QR and labels',
              'Reconciliation against digital records',
            ],
          ),
        'scan-file' => const _BatallaSectionSpec(
            summary:
                'The incoming-paper workflow is direct, retry-safe and duplicate-aware.',
            primaryTitle: 'Scan → File',
            primary: <String>[
              'Scan',
              'Preview',
              'Identify the correct Matter and folder',
              'Classify',
              'Confirm',
              'Quarantine / security check',
              'File',
              'Safe retry without accidental duplication',
            ],
          ),
        'calls-communications' => const _BatallaSectionSpec(
            summary:
                'Calls, callbacks and secure communications stay attached to the right client, intake or Matter.',
            primaryTitle: 'Communications',
            primary: <String>[
              'Incoming and outgoing calls',
              'Callbacks with a real owner',
              'Callback due time',
              'Secure messages',
              'Matter-linked communication history',
              'Client / intake identity',
            ],
          ),
        'print-center' => const _BatallaSectionSpec(
            summary:
                'Printing is an office operating service with attribution and version integrity.',
            primaryTitle: 'Packets',
            primary: <String>[
              "Today's Decision Packet",
              'Intake & Conflict Review Packet',
              'Dan Recommendation Packet',
              'Consultation Packet',
              'Complete Matter Packet',
              'Hearing Packet',
              'Full Chronology',
              'Task & Deadline List',
              'Document & Evidence Index',
              'Physical Folder cover / movement record',
              'Billing statements / receipts',
              'Monthly Office Report',
            ],
            secondaryTitle: 'Every important packet preserves',
            secondary: <String>[
              'Matter identity',
              'Version and print date',
              'Confidentiality',
              'Preparer',
              'Reviewer',
              'Decision-maker attribution',
            ],
          ),
        'billing-finance' => const _BatallaSectionSpec(
            summary:
                'Finance remains available without overwhelming the present legal-work priorities.',
            primaryTitle: 'Billing & finance',
            primary: <String>[
              'Retainers',
              'Arrangements and rates',
              'Time and expenses',
              'Invoices',
              'Receipts',
              'Payments',
              'Balances',
              'Financial reporting',
            ],
          ),
        'reports' => const _BatallaSectionSpec(
            summary:
                'Operational reconciliation comes before decorative analytics.',
            primaryTitle: 'Daily Reconciliation',
            primary: <String>[
              'Folders checked out or overdue',
              'Relocated / missing / found folders',
              'Scanned documents still quarantined',
              'Paper not yet scanned',
              'Callbacks outstanding',
              'Consultations awaiting confirmation',
              'Decisions awaiting Atty. Batalla',
              'Work awaiting Dan',
              'Overdue tasks and deadlines',
            ],
            secondaryTitle: 'Other reports',
            secondary: <String>[
              'Monthly Office Report',
              'Matter reports',
              'Financial reports',
              'Management reports',
            ],
          ),
        'team-access' => const _BatallaSectionSpec(
            summary:
                'Office relationships and roles never silently become authorization.',
            primaryTitle: 'Team & access',
            primary: <String>[
              'Matter-level access',
              'Role and responsibility',
              'Confidentiality boundaries',
              'Explicit sharing',
              'Access review',
            ],
            boundary:
                'Personalized workspace presentation never grants or expands authorization. Access remains server-enforced.',
          ),
        'activity-audit' => const _BatallaSectionSpec(
            summary:
                'A chronological record of meaningful office actions, reviews, decisions and physical-file movements.',
            primaryTitle: 'Activity & audit',
            primary: <String>[
              'Who prepared',
              'Who reviewed',
              'Who decided',
              'What changed',
              'When it changed',
              'Physical-folder movement',
              'Print and scan events',
              'Verification evidence',
            ],
          ),
        'settings' => const _BatallaSectionSpec(
            summary:
                'Office-level preferences, numbering, labels, printing and controlled workflow configuration.',
            primaryTitle: 'Settings',
            primary: <String>[
              'Office preferences',
              'Matter numbering',
              'Paper-file labels',
              'Print defaults',
              'Notification preferences',
              'Workflow defaults',
            ],
          ),
        'system-developer' => const _BatallaSectionSpec(
            summary:
                'Technical configuration stays out of ordinary legal work but remains available to authorized operators.',
            primaryTitle: 'System / Developer',
            primary: <String>[
              'Integrations',
              'Data contracts',
              'Diagnostics',
              'Runtime evidence',
              'Developer configuration',
            ],
          ),
        _ => const _BatallaSectionSpec(
            summary: 'Batalla & Associates workspace.',
            primaryTitle: 'Workspace',
            primary: <String>['Select a law-office destination.'],
          ),
      };

  Widget _hero(String title, String subtitle) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF101317),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFB9BABE),
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _panel({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0E1115),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x20FFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA7A8AC),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              if (children.isNotEmpty) const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _quickActions(List<(String, String)> actions) => Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final action in actions)
            ActionChip(
              label: Text(action.$1),
              onPressed: () => _select(action.$2),
              avatar: const Icon(Icons.arrow_forward_rounded, size: 17),
            ),
        ],
      );

  Widget _fieldGrid(List<String> fields) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final field in fields)
            Chip(
              avatar: const Icon(Icons.check_circle_outline_rounded, size: 17),
              label: Text(field),
            ),
        ],
      );

  Widget _boundaryCard(String text) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x16D5A24F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x44D5A24F)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFFD5A24F)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFE5E1D8),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _BatallaSectionSpec {
  const _BatallaSectionSpec({
    required this.summary,
    required this.primaryTitle,
    required this.primary,
    this.secondaryTitle = '',
    this.secondary = const <String>[],
    this.boundary,
  });

  final String summary;
  final String primaryTitle;
  final List<String> primary;
  final String secondaryTitle;
  final List<String> secondary;
  final String? boundary;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFBFC0C4)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFFE2E2E5),
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StepLine extends StatelessWidget {
  const _StepLine({
    required this.number,
    required this.text,
  });

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0x22D5A24F),
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFFD5A24F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
