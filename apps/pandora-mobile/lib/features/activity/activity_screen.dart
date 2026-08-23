import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';

enum ActivityFilter {
  all('All'),
  attention('Needs attention'),
  provider('Provider activity');

  const ActivityFilter(this.label);
  final String label;
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ScreenController<List<AuditEvent>>? _controller;
  final _search = TextEditingController();
  ActivityFilter _filter = ActivityFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<AuditEvent>>(
      () => repository.activity(allowCached: true),
    )..load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  List<AuditEvent> _visible(List<AuditEvent> events) {
    final query = _search.text.trim().toLowerCase();
    final visible = events.where((event) {
      final matchesQuery = query.isEmpty ||
          '${event.summary} ${event.type} ${event.actor} ${event.project ?? ''} ${event.provider ?? ''}'
              .toLowerCase()
              .contains(query);
      if (!matchesQuery) return false;
      return switch (_filter) {
        ActivityFilter.all => true,
        ActivityFilter.attention => _eventNeedsAttention(event),
        ActivityFilter.provider => event.provider != null,
      };
    }).toList(growable: true);
    visible.sort((left, right) {
      final leftTime =
          left.happenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.happenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    return List<AuditEvent>.unmodifiable(visible);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Activity',
        subtitle: 'What changed, who acted, and what the result was.',
        actions: [
          IconButton(
            tooltip: 'Refresh Activity',
            onPressed: () => _controller?.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        onRefresh: () => _controller!.refresh(),
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, _) {
            final controller = _controller!;
            if (controller.isLoading && controller.data == null) {
              return const ContentSkeleton(lines: 7);
            }
            if (controller.error != null && controller.data == null) {
              return ErrorContent(
                title: 'Activity could not load',
                message: _safeError(controller.error),
                onRetry: controller.load,
              );
            }
            final allEvents = controller.data ?? const <AuditEvent>[];
            final events = _visible(allEvents);
            final providers = allEvents
                .map((event) => event.provider?.trim().toLowerCase())
                .whereType<String>()
                .where((provider) => provider.isNotEmpty)
                .toSet()
                .length;
            final attention = allEvents.where(_eventNeedsAttention).length;
            final groups = _groupEvents(events);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.degradedReason != null ||
                    controller.error != null) ...[
                  DegradedContentNotice(
                    message: _degradedMessage(controller),
                    onRetry: controller.refresh,
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                ],
                OwnerMetricGrid(
                  metrics: [
                    OwnerMetric(
                      label: 'Events',
                      value: '${allEvents.length}',
                      icon: Icons.history_rounded,
                      tone: PandoraStatusTone.informative,
                    ),
                    OwnerMetric(
                      label: 'Providers',
                      value: '$providers',
                      icon: Icons.cable_rounded,
                      tone: PandoraStatusTone.neutral,
                    ),
                    OwnerMetric(
                      label: 'Needs attention',
                      value: '$attention',
                      icon: Icons.warning_amber_rounded,
                      tone: attention > 0
                          ? PandoraStatusTone.attention
                          : PandoraStatusTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: PandoraSpacing.md),
                PandoraSurface(
                  title: 'Find activity',
                  subtitle: 'Search owner-readable outcomes and actors.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Search activity',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: PandoraSpacing.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final filter in ActivityFilter.values) ...[
                              FilterChip(
                                label: Text(filter.label),
                                selected: _filter == filter,
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                              ),
                              if (filter != ActivityFilter.values.last)
                                const SizedBox(width: PandoraSpacing.xs),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PandoraSpacing.xl),
                OwnerSectionHeading(
                  title: 'Timeline',
                  subtitle: events.isEmpty
                      ? 'No activity matches this view.'
                      : '${events.length} event${events.length == 1 ? '' : 's'} · newest first',
                ),
                const SizedBox(height: PandoraSpacing.sm),
                if (events.isEmpty)
                  EmptyContent(
                    title: 'No matching activity',
                    message: _search.text.trim().isEmpty &&
                            _filter == ActivityFilter.all
                        ? 'Pandora returned no verified activity.'
                        : 'Try another search or filter.',
                  )
                else
                  for (var index = 0; index < groups.length; index++) ...[
                    _ActivityGroup(group: groups[index]),
                    if (index != groups.length - 1)
                      const SizedBox(height: PandoraSpacing.sm),
                  ],
              ],
            );
          },
        ),
      );
}

class _ActivityGroup extends StatelessWidget {
  const _ActivityGroup({required this.group});

  final _EventGroup group;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        title: group.label,
        child: Column(
          children: [
            for (var index = 0; index < group.events.length; index++) ...[
              _ActivityRow(event: group.events[index]),
              if (index != group.events.length - 1) const Divider(),
            ],
          ],
        ),
      );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (event.project != null) event.project!,
      if (event.provider != null) event.provider!,
      event.actor,
      ownerRelativeTime(event.happenedAt),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              providerIconFor(event.provider ?? event.type),
              size: 20,
            ),
          ),
          const SizedBox(width: PandoraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.summary,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: PandoraSpacing.xxs),
                Text(
                  metadata.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (event.result != null || event.risk != null) ...[
                  const SizedBox(height: PandoraSpacing.xs),
                  Wrap(
                    spacing: PandoraSpacing.xs,
                    runSpacing: PandoraSpacing.xs,
                    children: [
                      if (event.result != null)
                        StatusBadge(
                          label: event.result!,
                          tone: statusToneFor(event.result!),
                          compact: true,
                        ),
                      if (event.risk != null)
                        StatusBadge(
                          label: event.risk!.label,
                          tone: statusToneFor(event.risk!.label),
                          compact: true,
                        ),
                    ],
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

class _EventGroup {
  const _EventGroup({required this.label, required this.events});

  final String label;
  final List<AuditEvent> events;
}

List<_EventGroup> _groupEvents(List<AuditEvent> events) {
  final grouped = <String, List<AuditEvent>>{};
  for (final event in events) {
    final label = _dayLabel(event.happenedAt);
    grouped.putIfAbsent(label, () => <AuditEvent>[]).add(event);
  }
  return grouped.entries
      .map(
        (entry) => _EventGroup(
          label: entry.key,
          events: List<AuditEvent>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
}

String _dayLabel(DateTime? value) {
  if (value == null) return 'Time not verified';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final days = today.difference(date).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return '$days days ago';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

bool _eventNeedsAttention(AuditEvent event) {
  final resultTone = statusToneFor(event.result ?? '');
  final riskTone = statusToneFor(event.risk?.label ?? '');
  return resultTone == PandoraStatusTone.attention ||
      resultTone == PandoraStatusTone.critical ||
      riskTone == PandoraStatusTone.attention ||
      riskTone == PandoraStatusTone.critical;
}

String _safeError(Object? error) {
  if (error is PandoraRepositoryException) return error.message;
  return 'Pandora could not verify activity. Try again.';
}

String _degradedMessage(ScreenController<List<AuditEvent>> controller) {
  final reason = controller.degradedReason ?? controller.error!.message;
  if (!controller.isCached || controller.snapshot == null) return reason;
  final capturedAt = controller.snapshot!.fetchedAt.toLocal().toIso8601String();
  return '$reason Cached snapshot from $capturedAt.';
}
