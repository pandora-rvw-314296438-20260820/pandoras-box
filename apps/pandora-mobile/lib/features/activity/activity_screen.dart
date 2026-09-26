import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/activity/pandora_activity_projection.dart';
import '../../core/activity/pandora_activity_presentation_policy.dart';
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

enum ActivityHistoryView {
  activity('Activity'),
  logs('Activity Logs');

  const ActivityHistoryView(this.label);
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
  ActivityHistoryView _view = ActivityHistoryView.activity;
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
  Widget build(BuildContext context) {
    final theatre = _theatreGroups(_items);
    return PandoraPage(
      title: 'Activity',
      subtitle: _view == ActivityHistoryView.activity
          ? 'What Pandora is actually doing for the business.'
          : 'Canonical execution records for audit and troubleshooting.',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh Activity',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: PandoraSpacing.xs,
            children: <Widget>[
              for (final view in ActivityHistoryView.values)
                ChoiceChip(
                  label: Text(view.label),
                  selected: _view == view,
                  onSelected: (_) => setState(() => _view = view),
                ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
          PandoraSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: _view == ActivityHistoryView.activity
                        ? 'Search business activity'
                        : 'Search Activity Logs',
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
              title: 'Activity could not load',
              message: _error!,
              onRetry: _load,
            )
          else if (_loading && _items.isEmpty)
            const ContentSkeleton(lines: 7)
          else if (_view == ActivityHistoryView.activity)
            _ActivityTheatreList(
              groups: theatre,
              loading: _loading,
              hasMore: _hasMore,
              onLoadMore: () => _load(append: true),
            )
          else
            _ActivityLogList(
              items: _items,
              loading: _loading,
              hasMore: _hasMore,
              onLoadMore: () => _load(append: true),
            ),
        ],
      ),
    );
  }
}

class _ActivityTheatreList extends StatelessWidget {
  const _ActivityTheatreList({
    required this.groups,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<_ActivityWorkGroup> groups;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const EmptyContent(
        title: 'No business activity yet',
        message:
            'Pandora will show the exact business work it performs here. Technical routing stays in Activity Logs.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${groups.length} recent work session${groups.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        for (final group in groups) ...<Widget>[
          _ActivityWorkCard(group: group),
          const SizedBox(height: PandoraSpacing.sm),
        ],
        if (hasMore)
          Center(
            child: OutlinedButton.icon(
              onPressed: loading ? null : onLoadMore,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _ActivityWorkCard extends StatelessWidget {
  const _ActivityWorkCard({required this.group});

  final _ActivityWorkGroup group;

  @override
  Widget build(BuildContext context) {
    final events = group.events;
    PandoraActivityProjection? acting;
    for (final event in events) {
      if (event.state == PandoraActivityState.acting) {
        acting = event;
        break;
      }
    }
    final latest = events.last;
    final headline = (acting ?? events.first).message;
    return PandoraSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(headline, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: PandoraSpacing.xs),
          Text(
            '${group.anchor.personLabel} · ${_timeLabel(latest.occurredAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: PandoraSpacing.sm),
          for (var index = 0; index < events.length; index += 1) ...<Widget>[
            _ActivityStep(event: events[index]),
            if (index != events.length - 1)
              const SizedBox(height: PandoraSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _ActivityStep extends StatelessWidget {
  const _ActivityStep({required this.event});

  final PandoraActivityProjection event;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_activityIcon(event.state), size: 18),
          ),
          const SizedBox(width: PandoraSpacing.sm),
          Expanded(
            child: Text(
              pandoraActivityPresentationText(event),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
}

class _ActivityLogList extends StatelessWidget {
  const _ActivityLogList({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<PandoraActivityHistoryRecord> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyContent(
        title: 'No matching logs',
        message: 'No retained canonical events match this view.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${items.length} retained canonical event${items.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        for (final item in items) ...<Widget>[
          _CanonicalActivityRow(item: item),
          const SizedBox(height: PandoraSpacing.sm),
        ],
        if (hasMore)
          Center(
            child: OutlinedButton.icon(
              onPressed: loading ? null : onLoadMore,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
          ),
      ],
    );
  }
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
                child: Text(
                  event.message,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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

class _ActivityWorkGroup {
  const _ActivityWorkGroup({required this.anchor, required this.events});
  final PandoraActivityHistoryRecord anchor;
  final List<PandoraActivityProjection> events;
}

List<_ActivityWorkGroup> _theatreGroups(
  List<PandoraActivityHistoryRecord> items,
) {
  final byJob = <String, List<PandoraActivityHistoryRecord>>{};
  for (final item in items) {
    byJob
        .putIfAbsent(item.activity.jobId, () => <PandoraActivityHistoryRecord>[])
        .add(item);
  }
  final groups = <_ActivityWorkGroup>[];
  for (final records in byJob.values) {
    final events = records
        .map((record) => record.activity)
        .where(_theatreVisible)
        .toList(growable: false)
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final deduped = <PandoraActivityProjection>[];
    for (final event in events) {
      if (deduped.isNotEmpty &&
          deduped.last.message.trim() == event.message.trim() &&
          deduped.last.state == event.state) {
        continue;
      }
      deduped.add(event);
    }
    if (deduped.isNotEmpty) {
      groups.add(
        _ActivityWorkGroup(
          anchor: records.first,
          events: List<PandoraActivityProjection>.unmodifiable(deduped),
        ),
      );
    }
  }
  return List<_ActivityWorkGroup>.unmodifiable(groups);
}

bool _theatreVisible(PandoraActivityProjection event) {
  if (event.source.sourceId == 'pandora-business-theatre') return true;
  if (event.source.sourceType == 'tool' ||
      event.source.sourceType == 'device') {
    return true;
  }
  final capability = event.capability?.trim().toLowerCase();
  if (capability != null &&
      capability.isNotEmpty &&
      capability != 'intelligence.chat' &&
      capability != 'chat') {
    return true;
  }
  return event.state == PandoraActivityState.needsYou ||
      event.state == PandoraActivityState.failed ||
      event.state == PandoraActivityState.cancelled;
}

IconData _activityIcon(PandoraActivityState state) => switch (state) {
      PandoraActivityState.understanding => Icons.visibility_outlined,
      PandoraActivityState.planning => Icons.route_outlined,
      PandoraActivityState.acting => Icons.play_arrow_rounded,
      PandoraActivityState.checking ||
      PandoraActivityState.verifying =>
        Icons.fact_check_outlined,
      PandoraActivityState.result => Icons.check_circle_outline_rounded,
      PandoraActivityState.needsYou => Icons.priority_high_rounded,
      PandoraActivityState.retrying ||
      PandoraActivityState.fallback ||
      PandoraActivityState.resuming =>
        Icons.refresh_rounded,
      PandoraActivityState.paused => Icons.pause_circle_outline_rounded,
      PandoraActivityState.failed => Icons.error_outline_rounded,
      PandoraActivityState.cancelled => Icons.cancel_outlined,
    };

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
