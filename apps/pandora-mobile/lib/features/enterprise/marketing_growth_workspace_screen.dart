import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/pandora_navigation.dart';
import '../../pandora_config.dart';
import '../simple/ask_pandora_screen.dart';

class MarketingGrowthWorkspaceScreen extends StatefulWidget {
  const MarketingGrowthWorkspaceScreen({
    super.key,
    required this.initialRouteSlug,
    required this.enterpriseContext,
    required this.onHome,
    required this.onApprovals,
  });

  final String initialRouteSlug;
  final Map<String, Object?> enterpriseContext;
  final VoidCallback onHome;
  final VoidCallback onApprovals;

  @override
  State<MarketingGrowthWorkspaceScreen> createState() =>
      _MarketingGrowthWorkspaceScreenState();
}

class _MarketingGrowthWorkspaceScreenState
    extends State<MarketingGrowthWorkspaceScreen> {
  Map<String, Object?>? _data;
  String? _error;
  bool _loading = true;

  static const _canvas = Color(0xFF07111B);
  static const _paper = Color(0xFF0D1722);
  static const _line = Color(0xFF223144);
  static const _ink = Color(0xFFF3F6FA);
  static const _muted = Color(0xFF9DAABD);
  static const _accent = Color(0xFF8CB4FF);

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List) return const [];
    return value.map(_map).where((row) => row.isNotEmpty).toList();
  }

  String _text(Object? value, {String fallback = 'Unknown'}) {
    final raw = value?.toString().trim();
    return raw == null || raw.isEmpty ? fallback : raw;
  }

  bool _bool(Object? value) => value == true || value?.toString() == 'true';

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await Supabase.instance.client.rpc(
        'pandora_marketing_growth_command_center_v2',
        params: const <String, Object?>{
          'p_organization_id': PandoraConfig.organizationId,
        },
      );
      if (!mounted) return;
      setState(() {
        _data = _map(raw);
        _loading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Marketing & Growth could not be refreshed.';
        _loading = false;
      });
    }
  }

  void _openPandora() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (routeContext) => AskPandoraScreen(
        enterpriseContext: widget.enterpriseContext,
        onHome: () => Navigator.of(routeContext).pop(),
      ),
    ));
  }

  String get _sectionTitle {
    final route = widget.initialRouteSlug;
    if (route == 'home' || route == 'overview') return 'Overview';
    if (route == 'leads') return 'Leads & Outcomes';
    if (route == 'system-developer') return 'System / Developer';
    return route
        .split('-')
        .map((part) => part.isEmpty
            ? ''
            : part.substring(0, 1).toUpperCase() + part.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final navigation = PandoraNavigationScope.maybeOf(context);
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
            children: [
              Row(
                children: [
                  PandoraMenuButton(
                    key: const ValueKey('marketing-growth-navigation'),
                    onPressed: navigation?.openDrawer ?? widget.onHome,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Marketing & Growth',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('marketing-growth-refresh'),
                    onPressed: _loading ? null : _load,
                    tooltip: 'Refresh verified growth data',
                    icon: const Icon(Icons.refresh_rounded, color: _ink),
                  ),
                  IconButton(
                    tooltip: 'Back to Home',
                    onPressed: widget.onHome,
                    icon: const Icon(Icons.home_outlined, color: _ink),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'MARKETING & GROWTH',
                style: TextStyle(
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _sectionTitle,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 32,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Verified acquisition, outcomes, costs, learning and approvals. Missing evidence stays unknown; test traffic never becomes a business KPI.',
                style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 26),
              if (_loading) _loadingState(),
              if (!_loading && _error != null) _errorState(),
              if (!_loading && _error == null && _data != null)
                ..._sectionContent(_data!),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: _canvas,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Material(
            color: const Color(0xFFF2F5F9),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const ValueKey('marketing-growth-command-bar'),
              onTap: _openPandora,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, color: Colors.black),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Message Pandora about Marketing & Growth',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: Colors.black),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingState() => Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );

  Widget _errorState() => _card(
        'Growth data unavailable',
        [
          Text(_error!, style: const TextStyle(color: _muted, height: 1.45)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      );

  List<Widget> _sectionContent(Map<String, Object?> data) {
    final route = widget.initialRouteSlug;
    if (route == 'campaigns') return _campaigns(data);
    if (route == 'leads') return _outcomes(data);
    if (route == 'experiments') return _experiments(data);
    if (route == 'learning') return _learning(data);
    if (route == 'approvals') return _approvals(data);
    if (route == 'activity') return _activity(data);
    if (route == 'settings' || route == 'system-developer') {
      return _settings(data);
    }
    return _overview(data);
  }

  List<Widget> _overview(Map<String, Object?> data) {
    final campaigns = _rows(data['campaigns']);
    final daily = _rows(data['businessDaily']);
    final gates = _rows(data['approvalGates']);
    final test = _map(data['testAcceptance']);
    final businessCampaigns =
        campaigns.where((row) => _bool(row['businessKpi'])).toList();
    final latest = daily.isEmpty ? null : daily.first;
    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _metric('Business campaigns', businessCampaigns.length.toString(),
              'Only businessKpi=true campaigns'),
          _metric('Latest spend', latest == null ? 'Unknown' : _text(latest['spend']),
              latest == null ? 'No verified business row yet' : _text(latest['day'])),
          _metric('Latest sales', latest == null ? 'Unknown' : _text(latest['sales']),
              latest == null ? 'No verified outcome row yet' : 'Business traffic only'),
          _metric('Needs approval',
              gates.where((row) => row['state'] != 'approved').length.toString(),
              'Spend and client gates stay explicit'),
        ],
      ),
      const SizedBox(height: 16),
      _card('Test traffic boundary', [
        _lineRow('Controlled clicks', _text(test['clicks'], fallback: '0')),
        _lineRow('Controlled events', _text(test['events'], fallback: '0')),
        _lineRow('Controlled outcomes', _text(test['outcomes'], fallback: '0')),
        _lineRow('Included in business KPIs',
            _bool(test['includedInBusinessKpis']) ? 'Yes' : 'No'),
      ]),
      const SizedBox(height: 14),
      _card('Current authority', _authorityRows(data)),
    ];
  }

  List<Widget> _campaigns(Map<String, Object?> data) {
    final campaigns = _rows(data['campaigns']);
    if (campaigns.isEmpty) {
      return [_empty('No campaign records are verified for this tenant yet.')];
    }
    return campaigns.map((row) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(_text(row['name']), [
        _lineRow('Purpose', _text(row['purpose'])),
        _lineRow('Business KPI', _bool(row['businessKpi']) ? 'Included' : 'Excluded'),
        _lineRow('Binding', _text(row['bindingState'])),
        _lineRow('Campaign ID', _text(row['providerCampaignId'])),
        _lineRow('Ad set ID', _text(row['providerAdsetId'])),
        _lineRow('Ad ID', _text(row['providerAdId'])),
        _lineRow('Pixel ID', _text(row['pixelId'])),
        _lineRow('Currency', _text(row['currency'])),
      ]),
    )).toList();
  }

  List<Widget> _outcomes(Map<String, Object?> data) {
    final outcomes = _rows(data['outcomes']);
    final leadStages = _rows(data['leadStages']);
    return [
      if (outcomes.isEmpty)
        _empty('No verified business outcomes yet. Test outcomes are excluded.')
      else
        _card(
          'Verified business outcomes',
          outcomes.map((row) => Column(
            children: [
              _lineRow(_text(row['eventName']), _text(row['count'])),
              _lineRow('Latest', _text(row['latestOccurredAt'])),
              _lineRow('Currency', _text(row['currency'])),
              _lineRow('Known amount (minor units)', _text(row['knownAmountMinor'])),
              const SizedBox(height: 8),
            ],
          )).toList(),
        ),
      const SizedBox(height: 14),
      if (leadStages.isEmpty)
        _empty('No reviewed lead stages yet. Raw identifiers remain hidden.')
      else
        _card(
          'Operational lead records',
          leadStages.take(40).map((row) => Column(
            children: [
              _lineRow(_text(row['eventName']), _text(row['stage'])),
              _lineRow('Outcome receipt', _text(row['outcomeReceiptId'])),
              _lineRow('Occurred', _text(row['occurredAt'])),
              _lineRow('Amount', _bool(row['amountKnown']) ? 'Known' : 'Unknown'),
              _lineRow('Evidence', _text(row['evidenceRef'])),
              const SizedBox(height: 8),
            ],
          )).toList(),
        ),
    ];
  }

  List<Widget> _experiments(Map<String, Object?> data) {
    final runs = _rows(data['experimentRuns']);
    return [
      _card('Evidence before winners', const [
        Text(
          'Pandora does not name a winner from attribution alone or from a small sample. Experiment runs preserve sample size, uncertainty, spend state and inconclusive outcomes.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
      ]),
      const SizedBox(height: 14),
      if (runs.isEmpty)
        _empty('No verified business experiment data yet.')
      else
        ...runs.take(40).map((row) {
          final result = _map(row['result']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _card(_text(row['experimentKey']), [
              _lineRow('Status', _text(row['status'])),
              _lineRow('Window', _text(row['windowStart']) + ' → ' + _text(row['windowEnd'])),
              _lineRow('Denominator', _text(row['denominator'])),
              _lineRow('Conversions', _text(row['conversions'])),
              _lineRow('Spend state', _text(row['spendState'])),
              _lineRow('Conversion delay', _text(row['conversionDelayState'])),
              _lineRow('Winner', _text(result['winner'], fallback: 'None claimed')),
              _lineRow('Causal claim', _bool(result['causalClaim']) ? 'Yes' : 'No'),
              _lineRow('Result hash', _text(row['resultSha256'])),
            ]),
          );
        }),
    ];
  }

  List<Widget> _learning(Map<String, Object?> data) {
    final approved = _rows(data['approvedMemory']);
    return [
      _card('Review-gated learning', const [
        Text(
          'Only approved-current Memory retrieval receipts are exposed to this workspace. Pending, rejected or superseded learning is never treated as current evidence.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
      ]),
      const SizedBox(height: 14),
      if (approved.isEmpty)
        _empty('No approved-current Memory lesson has been retrieved for this workspace yet.')
      else
        _card(
          'Approved Memory evidence',
          approved.take(30).map((row) => Column(
            children: [
              _lineRow('Record', _text(row['memoryRecordId'])),
              _lineRow('Version', _text(row['memoryVersionId'])),
              _lineRow('Review item', _text(row['reviewItemId'])),
              _lineRow('Observed', _text(row['observedAt'])),
              _lineRow('Evidence', _text(row['evidenceRef'])),
              const SizedBox(height: 8),
            ],
          )).toList(),
        ),
    ];
  }

  List<Widget> _approvals(Map<String, Object?> data) {
    final gates = _rows(data['approvalGates']);
    return [
      _card('Consequential actions stay gated', [
        for (final gate in gates)
          _lineRow(
            _text(gate['taskId']) + ' · ' + _text(gate['kind']),
            _text(gate['state']),
          ),
        if (gates.isEmpty)
          const Text('No consequential growth gate is currently registered.',
              style: TextStyle(color: _muted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('marketing-growth-open-approvals'),
          onPressed: widget.onApprovals,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Open Needs You'),
        ),
      ]),
    ];
  }

  List<Widget> _activity(Map<String, Object?> data) {
    final rows = _rows(data['activity']);
    if (rows.isEmpty) {
      return [_empty('No direct growth evidence events yet.')];
    }
    return [
      _card('Direct growth evidence', rows.take(40).map((row) =>
        _lineRow(
          _text(row['subject']) + ' · ' + _text(row['eventType']),
          _text(row['occurredAt']),
        )
      ).toList()),
    ];
  }

  List<Widget> _settings(Map<String, Object?> data) {
    final privacy = _rows(data['privacy']);
    return [
      _card('Privacy authorization', [
        for (final row in privacy) ...[
          _lineRow(_text(row['policyVersion']), _text(row['allowedFlows'])),
          _lineRow('Evidence', _text(row['evidenceRef'])),
        ],
        if (privacy.isEmpty)
          const Text('No active growth privacy authorization.',
              style: TextStyle(color: _muted)),
      ]),
      const SizedBox(height: 14),
      _card('Authority boundary', _authorityRows(data)),
    ];
  }

  List<Widget> _authorityRows(Map<String, Object?> data) {
    final authority = _map(data['authority']);
    return [
      _lineRow('Dashboard', _bool(authority['readOnly']) ? 'Read-only' : 'Unknown'),
      _lineRow('Owner/admin only', _bool(authority['ownerAdminOnly']) ? 'Yes' : 'Unknown'),
      _lineRow('Staff access', _bool(authority['staffAccess']) ? 'Granted' : 'Not granted'),
      _lineRow('Campaign mutation', _bool(authority['campaignMutationGranted']) ? 'Granted' : 'Not granted'),
      _lineRow('Spend', _bool(authority['spendAuthorized']) ? 'Authorized' : 'Not authorized'),
      _lineRow('Publishing', _bool(authority['publishingAuthorized']) ? 'Authorized' : 'Not authorized'),
      _lineRow('Exports', _bool(authority['exportsAllowed']) ? 'Allowed' : 'Disabled'),
      _lineRow('Raw PII', _bool(authority['rawPiiVisible']) ? 'Visible' : 'Hidden'),
      _lineRow('Memory can grant spend', _bool(authority['memoryCanGrantSpend']) ? 'Yes' : 'No'),
      _lineRow('Operations Room', _bool(authority['operationsRoomRequired']) ? 'Required' : 'Not required'),
      _lineRow('Test traffic in business KPIs',
          _bool(authority['testTrafficIncludedInBusinessKpis']) ? 'Included' : 'Excluded'),
    ];
  }

  Widget _empty(String message) => _card('No verified data', [
        Text(message, style: const TextStyle(color: _muted, height: 1.45)),
      ]);

  Widget _metric(String label, String value, String note) => SizedBox(
        width: 172,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(note, style: const TextStyle(color: _muted, fontSize: 11, height: 1.3)),
            ],
          ),
        ),
      );

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _lineRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 13))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.right,
                style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
