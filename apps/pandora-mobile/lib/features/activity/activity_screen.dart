import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_activity_history_api.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';

enum ActivityHistoryFilter {
  all('All'),
  needsYou('Needs You'),
  failed('Failed'),
  completed('Completed'),
  device('Device'),
  provider('Provider'),
  tool('Tool'),
  chat('Chat');

  const ActivityHistoryFilter(this.label);
  final String label;
}

enum ActivityHistoryRange {
  day('24h'),
  week('7d'),
  month('30d'),
  retained('All retained');

  const ActivityHistoryRange(this.label);
  final String label;
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.source});

  final PandoraActivityHistorySource? source;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final TextEditingController _search = TextEditingController();
  PandoraActivityHistorySource? _source;
  List<PandoraActivityHistoryRecord> _items =
      const <PandoraActivityHistoryRecord>[];
  PandoraActivityHistoryCursor? _cursor;
  ActivityHistoryFilter _filter = ActivityHistoryFilter.all;
  ActivityHistoryRange _range = ActivityHistoryRange.month;
  String? _error;
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??=
        widget.source ?? PandoraDependencies.of(context).activityHistory;
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final source = _source;
    if (source == null || _loading) {
      if (source == null && mounted) {
        setState(() => _error = 'Activity History is not available.');
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await source.search(
        PandoraActivityHistoryQuery(
          text: _search.text,
          states: _statesFor(_filter),
          domains: _domainsFor(_filter),
          sourceTypes: _sourcesFor(_filter),
          from: _fromFor(_range),
          cursor: append ? _cursor : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = append
            ? List<PandoraActivityHistoryRecord>.unmodifiable(
                <PandoraActivityHistoryRecord>[..._items, ...page.items],
              )
            : page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } on PandoraActivityHistoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pandora could not verify Activity History.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeFilter(ActivityHistoryFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _load();
  }

  void _changeRange(ActivityHistoryRange range) {
    if (_range == range) return;
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Activity',
        subtitle: 'The same verified execution events Pandora showed live.',
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Activity History',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PandoraSurface(
              title: 'Find activity',
              subtitle:
                  'Search person, organization, action, device, job, app, or result.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Search Activity History',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Run search',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final filter in ActivityHistoryFilter.values) ...[
                          FilterChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => _changeFilter(filter),
                          ),
                          const SizedBox(width: PandoraSpacing.xs),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.xs),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final range in ActivityHistoryRange.values) ...[
                          ChoiceChip(
                            label: Text(range.label),
                            selected: _range == range,
                            onSelected: (_) => _changeRange(range),
                          ),
                          const SizedBox(width: PandoraSpacing.xs),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            if (_error != null)
              ErrorContent(
                title: 'Activity History could not load',
                message: _error!,
                onRetry: _load,
              )
            else if (_loading && _items.isEmpty)
              const ContentSkeleton(lines: 7)
            else if (_items.isEmpty)
              const EmptyContent(
                title: 'No matching activity',
                message: 'No retained canonical events match this view.',
              )
            else ...<Widget>[
              Text(
                '${_items.length} retained canonical event${_items.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: PandoraSpacing.sm),
              for (final item in _items) ...<Widget>[
                _CanonicalActivityRow(item: item),
                const SizedBox(height: PandoraSpacing.sm),
              ],
              if (_hasMore)
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _load(append: true),
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: const Text('Load more'),
                  ),
                ),
              const SizedBox(height: PandoraSpacing.sm),
              Text(
                'History reflects the canonical event retention window; expired events are not reconstructed.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      );
}

class _CanonicalActivityRow extends StatelessWidget {
  const _CanonicalActivityRow({required this.item});

  final PandoraActivityHistoryRecord item;

  @override
  Widget build(BuildContext context) {
    final event = item.activity;
    final metadata = <String>[
      item.personLabel,
      item.organizationName,
      event.source.sourceType,
      if (event.domain != null) event.domain!,
      'job ${_shortId(event.jobId)}',
      _timeLabel(event.occurredAt),
    ];
    return PandoraSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(event.message,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              const SizedBox(width: PandoraSpacing.sm),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(event.state.wireName.replaceAll('_', ' ')),
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.xs),
          Text(
            metadata.join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (event.outcome != null) ...<Widget>[
            const SizedBox(height: PandoraSpacing.xs),
            Text(event.outcome!.summary),
          ],
          if (event.blocker != null) ...<Widget>[
            const SizedBox(height: PandoraSpacing.xs),
            Text('Needs you: ${event.blocker!.requiredAction}'),
          ],
          if (event.evidenceRefs.isNotEmpty) ...<Widget>[
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              '${event.evidenceRefs.length} evidence reference${event.evidenceRefs.length == 1 ? '' : 's'} · event ${_shortId(event.eventId)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _statesFor(ActivityHistoryFilter filter) => switch (filter) {
      ActivityHistoryFilter.needsYou => const <String>['needs_you'],
      ActivityHistoryFilter.failed => const <String>['failed'],
      ActivityHistoryFilter.completed => const <String>['result'],
      _ => const <String>[],
    };

List<String> _domainsFor(ActivityHistoryFilter filter) =>
    filter == ActivityHistoryFilter.chat
        ? const <String>['chat']
        : const <String>[];

List<String> _sourcesFor(ActivityHistoryFilter filter) => switch (filter) {
      ActivityHistoryFilter.device => const <String>['device'],
      ActivityHistoryFilter.provider => const <String>['provider'],
      ActivityHistoryFilter.tool => const <String>['tool'],
      _ => const <String>[],
    };

DateTime? _fromFor(ActivityHistoryRange range) {
  final now = DateTime.now().toUtc();
  return switch (range) {
    ActivityHistoryRange.day => now.subtract(const Duration(days: 1)),
    ActivityHistoryRange.week => now.subtract(const Duration(days: 7)),
    ActivityHistoryRange.month => now.subtract(const Duration(days: 30)),
    ActivityHistoryRange.retained => null,
  };
}

String _shortId(String value) => value.length <= 12
    ? value
    : '${value.substring(0, 8)}…${value.substring(value.length - 4)}';

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}
