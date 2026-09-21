import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/pandora_navigation.dart';

typedef PlpBusinessActivityLoader = Future<Map<String, Object?>> Function();
typedef PlpPandoraActivityLogLoader = Future<Map<String, Object?>> Function({
  String? beforeAt,
  String? beforeJobId,
  int? beforeSequence,
  String? query,
});

class PlpActivityScreen extends StatefulWidget {
  const PlpActivityScreen({
    super.key,
    required this.onOpenNavigation,
    this.organizationId,
    this.businessLoader,
    this.logLoader,
  });

  final VoidCallback onOpenNavigation;
  final String? organizationId;
  final PlpBusinessActivityLoader? businessLoader;
  final PlpPandoraActivityLogLoader? logLoader;

  @override
  State<PlpActivityScreen> createState() => _PlpActivityScreenState();
}

class _PlpActivityScreenState extends State<PlpActivityScreen> {
  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171B29);
  static const _muted = Color(0xFF77736D);
  static const _gold = Color(0xFF99682C);
  static const _goldSoft = Color(0xFFF3EADF);
  static const _line = Color(0xFFE5DDD2);
  static const _green = Color(0xFF2AA65A);
  static const _red = Color(0xFFB94B43);

  final TextEditingController _search = TextEditingController();
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeReloadDebounce;
  String? _realtimeOrganizationId;

  int _tab = 0;
  bool _searching = false;
  bool _businessLoading = false;
  bool _logsLoading = false;
  bool _logsLoaded = false;
  String? _businessError;
  String? _logsError;
  String? _nextBeforeAt;
  String? _nextBeforeJobId;
  int? _nextBeforeSequence;
  bool _logsHasMore = false;
  List<Map<String, Object?>> _business =
      const <Map<String, Object?>>[];
  List<Map<String, Object?>> _logs = const <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    _bindRealtime();
    scheduleMicrotask(_loadBusiness);
  }

  @override
  void didUpdateWidget(covariant PlpActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      _bindRealtime();
    }
  }

  @override
  void dispose() {
    _realtimeReloadDebounce?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) {
      unawaited(channel.unsubscribe().then<void>((_) {}));
    }
    _search.dispose();
    super.dispose();
  }

  void _bindRealtime() {
    final organizationId = widget.organizationId?.trim();
    if (organizationId == null || organizationId.isEmpty) return;
    if (_realtimeOrganizationId == organizationId) return;

    final previous = _realtimeChannel;
    if (previous != null) {
      unawaited(previous.unsubscribe().then<void>((_) {}));
    }

    _realtimeOrganizationId = organizationId;
    _realtimeChannel = Supabase.instance.client
        .channel('plp-activity-live-$organizationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'enterprise_realtime_signals',
          callback: (payload) {
            final eventOrganizationId =
                payload.newRecord['organization_id']?.toString();
            if (eventOrganizationId == organizationId) {
              _scheduleRealtimeReload();
            }
          },
        )
        .subscribe();
  }

  void _scheduleRealtimeReload() {
    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(
      const Duration(milliseconds: 220),
      () {
        if (!mounted) return;
        unawaited(_loadBusiness());
        if (_logsLoaded) unawaited(_loadLogs());
      },
    );
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    return const {'true', '1', 'yes'}
        .contains(value?.toString().trim().toLowerCase());
  }

  int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _date(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<Map<String, Object?>> _providerBusinessLoader() async {
    final value = await Supabase.instance.client.rpc(
      'plp_recent_business_activity_v1',
      params: const <String, Object?>{'p_limit': 80},
    );
    return _map(value);
  }

  Future<Map<String, Object?>> _providerLogLoader({
    String? beforeAt,
    String? beforeJobId,
    int? beforeSequence,
    String? query,
  }) async {
    final value = await Supabase.instance.client.rpc(
      'plp_pandora_activity_logs_v2',
      params: <String, Object?>{
        'p_before_at': beforeAt,
        'p_before_job_id': beforeJobId,
        'p_before_sequence': beforeSequence,
        'p_limit': 60,
        'p_query': query,
      },
    );
    return _map(value);
  }

  Future<void> _loadBusiness() async {
    if (_businessLoading) return;
    setState(() {
      _businessLoading = true;
      _businessError = null;
    });
    try {
      final payload = await (widget.businessLoader ?? _providerBusinessLoader)();
      if (!mounted) return;
      setState(() => _business = _maps(payload['items']));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _businessError = 'Recent resort activity could not be verified.',
      );
    } finally {
      if (mounted) setState(() => _businessLoading = false);
    }
  }

  Future<void> _loadLogs({bool append = false}) async {
    if (_logsLoading) return;
    setState(() {
      _logsLoading = true;
      _logsError = null;
    });
    try {
      final query = _search.text.trim();
      final payload = await (widget.logLoader ?? _providerLogLoader)(
        beforeAt: append ? _nextBeforeAt : null,
        beforeJobId: append ? _nextBeforeJobId : null,
        beforeSequence: append ? _nextBeforeSequence : null,
        query: query.isEmpty ? null : query,
      );
      if (!mounted) return;
      final page = _maps(payload['items']);
      setState(() {
        _logs = append
            ? <Map<String, Object?>>[..._logs, ...page]
            : page;
        _logsHasMore = _bool(payload['hasMore']);
        _nextBeforeAt = payload['nextBeforeAt']?.toString();
        _nextBeforeJobId = payload['nextBeforeJobId']?.toString();
        _nextBeforeSequence = _int(payload['nextBeforeSequence']);
        _logsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _logsError = 'Pandora activity logs could not be verified.',
      );
    } finally {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  Future<void> _refreshActive() =>
      _tab == 3 ? _loadLogs() : _loadBusiness();

  void _selectTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    if (index == 3 && !_logsLoaded) {
      unawaited(_loadLogs());
    }
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _search.clear();
      if (_tab == 3 && _logsLoaded) {
        unawaited(_loadLogs());
      }
    }
  }

  void _runSearch() {
    if (_tab == 3) {
      unawaited(_loadLogs());
    } else {
      setState(() {});
    }
  }

  List<Map<String, Object?>> get _visibleBusiness {
    final query = _search.text.trim().toLowerCase();
    return _business.where((item) {
      final audience = _text(item['audience'], fallback: 'all').toLowerCase();
      final tabMatches = switch (_tab) {
        1 => audience == 'team',
        2 => audience == 'guests',
        _ => true,
      };
      if (!tabMatches) return false;
      if (query.isEmpty) return true;
      return _text(item['title']).toLowerCase().contains(query) ||
          _text(item['summary']).toLowerCase().contains(query) ||
          _text(item['category']).toLowerCase().contains(query) ||
          _text(item['sourceLabel']).toLowerCase().contains(query);
    }).toList(growable: false);
  }

  bool _isToday(Map<String, Object?> item, String key) {
    final value = _date(item[key]);
    if (value == null) return false;
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _canvas,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refreshActive,
            child: ListView(
              key: const ValueKey<String>('plp-activity-light-page'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 26),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                  child: _ActivityHeader(
                    onOpenNavigation: widget.onOpenNavigation,
                    onSearch: _toggleSearch,
                  ),
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      key: const ValueKey<String>('plp-activity-search-field'),
                      controller: _search,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) {
                        if (_tab != 3) setState(() {});
                      },
                      onSubmitted: (_) => _runSearch(),
                      style: const TextStyle(color: _ink),
                      decoration: InputDecoration(
                        hintText: _tab == 3
                            ? 'Search Pandora actions'
                            : 'Search resort activity',
                        hintStyle: const TextStyle(color: _muted),
                        prefixIcon:
                            const Icon(Icons.search_rounded, color: _gold),
                        suffixIcon: IconButton(
                          onPressed: () {
                            _search.clear();
                            _runSearch();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                        filled: true,
                        fillColor: _paper,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _gold),
                        ),
                      ),
                    ),
                  ),
                const _ActivityHero(),
                _ActivityTabs(
                  selected: _tab,
                  onSelect: _selectTab,
                ),
                if (_tab == 3)
                  _buildLogs()
                else
                  _buildBusiness(),
              ],
            ),
          ),
        ),
      );

  Widget _buildBusiness() {
    final items = _visibleBusiness;
    if (_businessLoading && items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_businessError != null && items.isEmpty) {
      return _ActivityEmptyState(
        icon: Icons.sync_problem_rounded,
        title: 'Activity unavailable',
        detail: _businessError!,
        actionLabel: 'Retry',
        onAction: _loadBusiness,
      );
    }
    if (items.isEmpty) {
      final label = switch (_tab) {
        1 => 'team',
        2 => 'guest',
        _ => 'resort',
      };
      return _ActivityEmptyState(
        icon: Icons.history_rounded,
        title: 'No matching $label activity',
        detail: 'Verified activity will appear here as the resort operates.',
      );
    }

    final today =
        items.where((item) => _isToday(item, 'occurredAt')).toList();
    final earlier =
        items.where((item) => !_isToday(item, 'occurredAt')).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 6),
      child: Container(
        decoration: BoxDecoration(
          color: _paper.withValues(alpha: .82),
          border: Border.all(color: const Color(0xFFD8CFC3)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (today.isNotEmpty) ...[
              const _SectionTitle('Today'),
              const SizedBox(height: 7),
              for (var i = 0; i < today.length; i++) ...[
                _BusinessActivityRow(
                  item: today[i],
                  dateFor: _date,
                  textFor: _text,
                  boolFor: _bool,
                ),
                if (i != today.length - 1)
                  const Divider(height: 1, color: _line),
              ],
            ],
            if (today.isNotEmpty && earlier.isNotEmpty)
              const SizedBox(height: 24),
            if (earlier.isNotEmpty) ...[
              const _SectionTitle('Earlier'),
              const SizedBox(height: 7),
              for (var i = 0; i < earlier.length; i++) ...[
                _BusinessActivityRow(
                  item: earlier[i],
                  dateFor: _date,
                  textFor: _text,
                  boolFor: _bool,
                ),
                if (i != earlier.length - 1)
                  const Divider(height: 1, color: _line),
              ],
            ],
            const SizedBox(height: 13),
            const Divider(height: 1, color: _line),
            TextButton.icon(
              key: const ValueKey<String>('plp-activity-open-logs'),
              onPressed: () {
                _selectTab(3);
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF75501F),
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 10,
                ),
              ),
              label: const Text('View Pandora activity logs'),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogs() {
    if (_logsLoading && _logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_logsError != null && _logs.isEmpty) {
      return _ActivityEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Activity logs unavailable',
        detail: _logsError!,
        actionLabel: 'Retry',
        onAction: _loadLogs,
      );
    }
    if (_logs.isEmpty) {
      return const _ActivityEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No matching Pandora actions',
        detail: 'No retained Pandora audit event matches this search.',
      );
    }

    final today =
        _logs.where((item) => _isToday(item, 'occurredAt')).toList();
    final earlier =
        _logs.where((item) => !_isToday(item, 'occurredAt')).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 11),
            child: Text(
              'Provider-backed audit trail of actions recorded inside Pandora.',
              style: TextStyle(
                color: _muted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _paper.withValues(alpha: .82),
              border: Border.all(color: const Color(0xFFD8CFC3)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (today.isNotEmpty) ...[
                  const _SectionTitle('Today'),
                  const SizedBox(height: 7),
                  for (var i = 0; i < today.length; i++) ...[
                    _PandoraLogRow(
                      item: today[i],
                      dateFor: _date,
                      textFor: _text,
                    ),
                    if (i != today.length - 1)
                      const Divider(height: 1, color: _line),
                  ],
                ],
                if (today.isNotEmpty && earlier.isNotEmpty)
                  const SizedBox(height: 24),
                if (earlier.isNotEmpty) ...[
                  const _SectionTitle('Earlier'),
                  const SizedBox(height: 7),
                  for (var i = 0; i < earlier.length; i++) ...[
                    _PandoraLogRow(
                      item: earlier[i],
                      dateFor: _date,
                      textFor: _text,
                    ),
                    if (i != earlier.length - 1)
                      const Divider(height: 1, color: _line),
                  ],
                ],
                if (_logsHasMore) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: _line),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey<String>('plp-activity-load-more-logs'),
                      onPressed:
                          _logsLoading ? null : () => _loadLogs(append: true),
                      icon: _logsLoading
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: const Text('Load more activity logs'),
                      style: TextButton.styleFrom(foregroundColor: _gold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({
    required this.onOpenNavigation,
    required this.onSearch,
  });

  final VoidCallback onOpenNavigation;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          PandoraMenuButton(
            key: const ValueKey<String>('plp-activity-open-navigation'),
            onPressed: onOpenNavigation,
          ),
          const SizedBox(width: 5),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF68401F),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/workspaces/plp.webp',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text(
                    'PLP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'PUEBLO\nLA PERLA\nBORACAY',
              maxLines: 3,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: Color(0xFF4C3020),
                fontSize: 8.5,
                height: 1.06,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('plp-activity-search'),
            tooltip: 'Search activity',
            onPressed: onSearch,
            style: IconButton.styleFrom(
              foregroundColor: _PlpActivityScreenState._ink,
              backgroundColor: Colors.white.withValues(alpha: .74),
              side: const BorderSide(color: Color(0xFFF0EBE3)),
            ),
            icon: const Icon(Icons.search_rounded, size: 26),
          ),
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8FC7C3), Color(0xFFC6A06A)],
              ),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.villa_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      );
}

class _ActivityHero extends StatelessWidget {
  const _ActivityHero();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 260,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 350;
            return Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFFFEFA),
                        Color(0xFFF9F4EB),
                        Color(0xFFDDEDEF),
                      ],
                      stops: [0, .54, 1],
                    ),
                  ),
                ),
                Positioned(
                  right: -35,
                  bottom: 3,
                  child: Container(
                    width: 250,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(58),
                      color: const Color(0xFF9FCFD0).withValues(alpha: .50),
                    ),
                  ),
                ),
                Positioned(
                  right: 35,
                  bottom: 26,
                  child: Icon(
                    Icons.villa_rounded,
                    size: compact ? 100 : 122,
                    color: const Color(0xFFAD8A63).withValues(alpha: .25),
                  ),
                ),
                Positioned(
                  right: 40,
                  top: 10,
                  child: Icon(
                    Icons.park_rounded,
                    size: compact ? 128 : 150,
                    color: const Color(0xFF718B67).withValues(alpha: .28),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 22 : 28,
                    30,
                    compact ? 104 : 135,
                    22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'A C T I V I T Y',
                          maxLines: 1,
                          style: TextStyle(
                            color: Color(0xFF8D642E),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 13 : 18),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recent activity',
                          maxLines: 1,
                          style: TextStyle(
                            color: _PlpActivityScreenState._ink,
                            fontSize: compact ? 38 : 47,
                            height: .96,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 11 : 15),
                      Text(
                        'A quiet view of what has been happening across the resort.',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF595A5C),
                          fontSize: compact ? 13.5 : 15.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _ActivityTabs extends StatelessWidget {
  const _ActivityTabs({
    required this.selected,
    required this.onSelect,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  static const labels = <String>[
    'All',
    'Team',
    'Guests',
    'Activity Logs',
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFEFC),
          border: Border(
            bottom: BorderSide(color: _PlpActivityScreenState._line),
          ),
        ),
        child: Row(
          children: List<Widget>.generate(labels.length, (index) {
            final active = selected == index;
            final label = labels[index];
            return Expanded(
              child: InkWell(
                key: ValueKey<String>(
                  'plp-activity-tab-${label.toLowerCase().replaceAll(' ', '-')}',
                ),
                onTap: () => onSelect(index),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: active
                                ? _PlpActivityScreenState._ink
                                : const Color(0xFF5D5D60),
                            fontSize: index == 3 ? 12.5 : 14.5,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 13),
                      color: active
                          ? _PlpActivityScreenState._gold
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: _PlpActivityScreenState._ink,
          fontSize: 23,
          fontWeight: FontWeight.w500,
          letterSpacing: -.4,
        ),
      );
}

class _BusinessActivityRow extends StatelessWidget {
  const _BusinessActivityRow({
    required this.item,
    required this.dateFor,
    required this.textFor,
    required this.boolFor,
  });

  final Map<String, Object?> item;
  final DateTime? Function(Object?) dateFor;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  IconData _icon(String category, String audience) {
    final value = category.toLowerCase();
    if (value.contains('payment') || value.contains('finance')) {
      return Icons.receipt_long_outlined;
    }
    if (value.contains('house')) return Icons.home_outlined;
    if (value.contains('maintenance')) return Icons.handyman_outlined;
    if (value.contains('arrival') || value.contains('transport')) {
      return Icons.flight_rounded;
    }
    if (value.contains('booking')) return Icons.calendar_month_outlined;
    if (audience == 'team') return Icons.groups_2_outlined;
    if (audience == 'guests') return Icons.person_outline_rounded;
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final title = textFor(item['title'], fallback: 'Resort activity');
    final summary = textFor(item['summary'], fallback: 'Verified PLP update');
    final category = textFor(item['category'], fallback: 'activity');
    final audience = textFor(item['audience'], fallback: 'all');
    final occurredAt = dateFor(item['occurredAt']);
    final mock = boolFor(item['isMock']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _PlpActivityScreenState._goldSoft,
            ),
            child: Icon(
              _icon(category, audience),
              color: _PlpActivityScreenState._gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _PlpActivityScreenState._ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _PlpActivityScreenState._muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    if (mock) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6E5C9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'QA',
                          style: TextStyle(
                            color: Color(0xFF8C5F1E),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _relativeTime(occurredAt),
            style: const TextStyle(
              color: _PlpActivityScreenState._muted,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PandoraLogRow extends StatelessWidget {
  const _PandoraLogRow({
    required this.item,
    required this.dateFor,
    required this.textFor,
  });

  final Map<String, Object?> item;
  final DateTime? Function(Object?) dateFor;
  final String Function(Object?, {String fallback}) textFor;

  IconData _icon(String resourceType, String eventType) {
    final value = '$resourceType $eventType'.toLowerCase();
    if (value.contains('build')) return Icons.build_circle_outlined;
    if (value.contains('deploy')) return Icons.cloud_done_outlined;
    if (value.contains('verification')) return Icons.verified_outlined;
    if (value.contains('policy') || value.contains('approval')) {
      return Icons.shield_outlined;
    }
    if (value.contains('project')) return Icons.folder_open_outlined;
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final eventType = textFor(item['eventType'], fallback: 'pandora.activity');
    final message = textFor(item['message'], fallback: _eventLabel(eventType));
    final capability = textFor(
      item['capability'] ?? item['resourceType'],
      fallback: 'Pandora',
    );
    final domain = textFor(item['domain'], fallback: 'activity');
    final actor = textFor(item['actorLabel'], fallback: 'Pandora');
    final status = textFor(item['status'], fallback: 'recorded').toLowerCase();
    final occurredAt = dateFor(item['occurredAt']);
    final failed = status == 'failed';
    final completed = status == 'result' || status == 'completed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: failed
                  ? const Color(0xFFF7E6E3)
                  : _PlpActivityScreenState._goldSoft,
            ),
            child: Icon(
              _icon(capability, domain),
              color: failed
                  ? _PlpActivityScreenState._red
                  : _PlpActivityScreenState._gold,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        failed ? _PlpActivityScreenState._red : _PlpActivityScreenState._ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$actor · ${_resourceLabel(capability)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _PlpActivityScreenState._muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _relativeTime(occurredAt),
                style: const TextStyle(
                  color: _PlpActivityScreenState._muted,
                  fontSize: 10.5,
                ),
              ),
              if (failed) ...[
                const SizedBox(height: 4),
                const Text(
                  'Failed',
                  style: TextStyle(
                    color: _PlpActivityScreenState._red,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (completed) ...[
                const SizedBox(height: 4),
                const Icon(
                  Icons.check_circle_rounded,
                  color: _PlpActivityScreenState._green,
                  size: 13,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _PlpActivityScreenState._paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _PlpActivityScreenState._line),
          ),
          child: Row(
            children: [
              Icon(icon, color: _PlpActivityScreenState._gold, size: 27),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _PlpActivityScreenState._ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: _PlpActivityScreenState._muted,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => unawaited(onAction!()),
                        style: TextButton.styleFrom(
                          foregroundColor: _PlpActivityScreenState._gold,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

String _eventLabel(String raw) {
  var value = raw.trim();
  value = value.replaceFirst('pandora_control_plane.', '');
  value = value.replaceFirst(RegExp(r'^pandora_'), '');
  final parts = value.split('.');
  final resource = parts.first
      .replaceFirst(RegExp(r'^pandora_'), '')
      .replaceAll('_', ' ')
      .trim();
  final action = parts.length > 1 ? parts.last.toLowerCase() : '';
  final verb = switch (action) {
    'insert' => 'created',
    'update' => 'updated',
    'delete' => 'deleted',
    'completed' => 'completed',
    'failed' => 'failed',
    _ => action.replaceAll('_', ' '),
  };
  final text = verb.isEmpty ? resource : '$resource $verb';
  if (text.isEmpty) return 'Pandora activity recorded';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _resourceLabel(String raw) {
  final value = raw
      .replaceFirst(RegExp(r'^pandora_'), '')
      .replaceAll('_', ' ')
      .replaceAll('.', ' · ')
      .trim();
  if (value.isEmpty) return 'Pandora';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _relativeTime(DateTime? value) {
  if (value == null) return '—';
  final diff = DateTime.now().difference(value);
  if (diff.isNegative) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day';
}
