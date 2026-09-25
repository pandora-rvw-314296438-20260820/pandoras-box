import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/pandora_navigation.dart';
import '../../pandora_config.dart';
import '../simple/ask_pandora_screen.dart';

class TaxComplianceScreen extends StatefulWidget {
  const TaxComplianceScreen({
    super.key,
    required this.workspaceKey,
    required this.workspaceName,
    required this.enterpriseContext,
    required this.onHome,
  });

  final String workspaceKey;
  final String workspaceName;
  final Map<String, Object?> enterpriseContext;
  final VoidCallback onHome;

  @override
  State<TaxComplianceScreen> createState() => _TaxComplianceScreenState();
}

class _TaxComplianceScreenState extends State<TaxComplianceScreen> {
  Map<String, Object?>? _data;
  String? _error;
  bool _loading = true;

  bool get _isPlp => widget.workspaceKey == 'plp-boracay';

  Color get _canvas => _isPlp ? const Color(0xFFFAF7F1) : const Color(0xFF090909);
  Color get _paper => _isPlp ? const Color(0xFFFFFDFC) : const Color(0xFF151515);
  Color get _ink => _isPlp ? const Color(0xFF171512) : const Color(0xFFF5F2EC);
  Color get _muted => _isPlp ? const Color(0xFF746F67) : const Color(0xFFAAA49C);
  Color get _line => _isPlp ? const Color(0xFFE1DBD1) : const Color(0xFF2B2B2B);
  Color get _accent => _isPlp ? const Color(0xFF70643F) : const Color(0xFFC7A868);

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

  int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  String _text(Object? value, {String fallback = '—'}) {
    final raw = value?.toString().trim();
    return raw == null || raw.isEmpty ? fallback : raw;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final value = await Supabase.instance.client.rpc(
        'pandora_tax_command_center_v1',
        params: const <String, Object?>{
          'p_organization_id': PandoraConfig.organizationId,
        },
      );
      if (!mounted) return;
      setState(() {
        _data = _map(value);
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
        _error = 'Tax & Compliance could not be refreshed.';
        _loading = false;
      });
    }
  }

  void _openPandora() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => AskPandoraScreen(
          enterpriseContext: widget.enterpriseContext,
          onHome: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  String _periodLabel(Map<String, Object?> period) {
    final start = _text(period['period_start'], fallback: '');
    final end = _text(period['period_end'], fallback: '');
    if (start.isEmpty && end.isEmpty) return 'No active period';
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return start + ' — ' + end;
  }

  @override
  Widget build(BuildContext context) {
    final navigation = PandoraNavigationScope.maybeOf(context);
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    children: [
                      PandoraMenuButton(
                        key: const ValueKey<String>('tax-compliance-navigation'),
                        onPressed: navigation?.openDrawer ?? widget.onHome,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.workspaceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey<String>('tax-compliance-refresh'),
                        tooltip: 'Refresh tax workspace',
                        onPressed: _loading ? null : _load,
                        icon: Icon(Icons.refresh_rounded, color: _ink),
                      ),
                      IconButton(
                        tooltip: 'Back to Home',
                        onPressed: widget.onHome,
                        icon: Icon(Icons.home_outlined, color: _ink),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 124),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'TAX & COMPLIANCE',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Know what is ready.\nKnow what still needs proof.',
                      style: TextStyle(
                        color: _ink,
                        fontSize: _isPlp ? 34 : 32,
                        height: 1.08,
                        fontFamily: _isPlp ? 'serif' : null,
                        fontWeight: _isPlp ? FontWeight.w500 : FontWeight.w700,
                        letterSpacing: _isPlp ? -.8 : -.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Evidence, ledger treatment, reconciliation, rules, calculations, review and filing readiness stay tied to their source records.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_loading) _loadingState(),
                    if (!_loading && _error != null) _errorState(),
                    if (!_loading && _error == null && _data != null)
                      ..._content(_data!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: _canvas,
            border: Border(top: BorderSide(color: _line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Material(
            color: _isPlp ? const Color(0xFF171512) : const Color(0xFFF0ECE4),
            borderRadius: BorderRadius.circular(_isPlp ? 2 : 14),
            child: InkWell(
              key: const ValueKey<String>('tax-message-pandora'),
              onTap: _openPandora,
              borderRadius: BorderRadius.circular(_isPlp ? 2 : 14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 20,
                      color: _isPlp ? Colors.white : Colors.black,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Message Pandora about taxes',
                        style: TextStyle(
                          color: _isPlp ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: _isPlp ? Colors.white : Colors.black,
                    ),
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
        ),
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );

  Widget _errorState() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tax workspace unavailable', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: _muted, height: 1.45)),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );

  List<Widget> _content(Map<String, Object?> data) {
    final evidence = _map(data['evidence']);
    final ledger = _map(data['ledger']);
    final exceptions = _map(data['exceptions']);
    final rules = _map(data['rules']);
    final period = _map(data['latestPeriod']);
    final reconciliation = _map(data['latestReconciliation']);
    final calculation = _map(data['latestCalculation']);
    final filingPackage = _map(data['latestFilingPackage']);
    final capabilities = _map(data['capabilities']);
    final calcEnabled = _bool(capabilities['deterministicCalculation']);
    final filingEnabled = _bool(capabilities['filingSubmission']);
    final paymentEnabled = _bool(capabilities['paymentExecution']);

    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _metric('Evidence verified', _int(evidence['verified']).toString(), _int(evidence['needsReview']).toString() + ' need review'),
          _metric('Ledger verified', _int(ledger['verified']).toString(), _int(ledger['needsReview']).toString() + ' need treatment'),
          _metric('Open exceptions', _int(exceptions['open']).toString(), _int(exceptions['high']).toString() + ' high · ' + _int(exceptions['critical']).toString() + ' critical'),
          _metric('Rule engine', calcEnabled ? 'Enabled' : 'Review gate', calcEnabled ? 'Approved rule pack active' : 'No approved live pack'),
        ],
      ),
      const SizedBox(height: 26),
      _section(
        'CURRENT PERIOD',
        period.isEmpty ? 'No tax period has been prepared yet.' : _periodLabel(period),
        [
          _row('Status', _text(period['status'])),
          _row('Jurisdiction', _text(period['jurisdiction_code'])),
          _row('Source sync', _text(period['source_sync_state'])),
          _row('Rule pack', _text(period['rule_pack_id'], fallback: 'Not approved')),
        ],
      ),
      const SizedBox(height: 14),
      _section(
        'RECONCILIATION',
        reconciliation.isEmpty ? 'No completed reconciliation yet.' : 'Latest reconciliation is ' + _text(reconciliation['status']) + '.',
        [
          _row('Matched', _text(reconciliation['matched_count'], fallback: '0')),
          _row('Exceptions', _text(reconciliation['exception_count'], fallback: '0')),
          _row('Calculation', calculation.isEmpty ? 'Not run' : _text(calculation['status'])),
        ],
      ),
      const SizedBox(height: 14),
      _section(
        'FILING READINESS',
        filingPackage.isEmpty ? 'No filing package prepared yet.' : 'Package ' + _text(filingPackage['package_version']) + ' · ' + _text(filingPackage['status']),
        [
          _row('Professional review', filingPackage['accountant_review_id'] == null ? 'Required' : 'Recorded'),
          _row('Owner approval', filingPackage['owner_approval_id'] == null ? 'Required' : 'Recorded'),
          _row('Submission', filingEnabled ? 'Verified adapter enabled' : 'Disabled'),
          _row('Tax payment', paymentEnabled ? 'Verified execution enabled' : 'Disabled'),
        ],
      ),
      const SizedBox(height: 14),
      _section(
        'RULE AUTHORITY',
        calcEnabled
            ? 'An approved deterministic rule pack is active.'
            : 'The Philippines rule pack is still under professional review.',
        [
          _row('PH jurisdiction', _text(rules['jurisdictionStatus'])),
          _row('Approved pack', _text(rules['approvedPackId'], fallback: 'None')),
          _row('Pack in review', _text(rules['inReviewPackId'], fallback: 'None')),
        ],
      ),
    ];
  }

  Widget _metric(String label, String value, String detail) => SizedBox(
        width: 162,
        child: Container(
          constraints: const BoxConstraints(minHeight: 122),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(_isPlp ? 2 : 14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
              const Spacer(),
              Text(value, style: TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail, style: TextStyle(color: _muted, fontSize: 11.5, height: 1.3)),
            ],
          ),
        ),
      );

  Widget _section(String label, String intro, List<Widget> rows) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(_isPlp ? 2 : 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: _accent, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 9),
            Text(intro, style: TextStyle(color: _ink, fontSize: 17, height: 1.35, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Divider(height: 1, color: _line),
            for (final row in rows) row,
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: _muted, fontSize: 13))),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
