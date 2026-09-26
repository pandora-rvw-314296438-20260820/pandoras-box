
import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_operations_events.dart';

class OperationsExecutionFeed extends StatefulWidget {
  const OperationsExecutionFeed({super.key});
  @override
  State<OperationsExecutionFeed> createState() => _OperationsExecutionFeedState();
}
class _OperationsExecutionFeedState extends State<OperationsExecutionFeed> with WidgetsBindingObserver {
  PandoraDependencies? _dependencies;
  PandoraOperationsEventReader? _reader;
  PandoraOperationsFeed? _feed;
  StreamSubscription<dynamic>? _auth;
  Timer? _timer;
  bool _expanded = false;
  bool _foreground = true;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = PandoraDependencies.of(context);
    if (identical(dependencies, _dependencies)) return;
    _timer?.cancel(); _auth?.cancel(); _feed?.dispose(); _reader?.dispose();
    _dependencies = dependencies;
    final reader = dependencies.intelligence?.operationsEventReader();
    _reader = reader; _feed = null;
    if (reader == null || !reader.canonicalScope) return;
    final feed = PandoraOperationsFeed(readPage: reader.read, cancelRead: reader.cancel);
    _feed = feed;
    feed.reset(reader.sessionKey, canonicalOperationsProject);
    _auth = dependencies.auth.changes.listen((_) {
      feed.updateSession(reader.sessionKey, canonicalOperationsProject);
      if (_expanded && _foreground) { unawaited(feed.refresh()); }
    });
  }
  void _setExpanded(bool value) {
    _expanded = value; _timer?.cancel();
    if (!_expanded || !_foreground) { _feed?.pause(); return; }
    unawaited(_feed?.refresh());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _expanded && _foreground) unawaited(_feed?.refresh());
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _setExpanded(_expanded);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); _auth?.cancel();
    _feed?.dispose(); _reader?.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    if (feed == null) return const SizedBox.shrink();
    return ExpansionTile(
      key: const ValueKey('operations-execution-feed'),
      title: const Text('Execution events'),
      subtitle: const Text('Recorded scheduler activity, separate from team discussion'),
      onExpansionChanged: _setExpanded,
      children: [OperationsExecutionPanel(feed: feed)],
    );
  }
}

class OperationsExecutionPanel extends StatelessWidget {
  const OperationsExecutionPanel({super.key, required this.feed});
  final PandoraOperationsFeed feed;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (feed.loading) const Text('Reading recorded events...'),
        if (feed.error != null) Text(feed.error!, key: const ValueKey('operations-event-error')),
        if (!feed.loading && feed.error == null && feed.events.isEmpty)
          const Text('No recorded execution events.'),
        if (feed.events.isNotEmpty)
          SizedBox(height: 210, child: ListView.builder(
            key: const ValueKey('operations-event-records'),
            itemCount: feed.events.length,
            itemBuilder: (context, index) {
              final event = feed.events[feed.events.length - 1 - index];
              return ListTile(dense: true,
                title: Text(event.label),
                subtitle: Text('${event.taskId ?? 'Workspace'} · ${event.occurredAt.toLocal()}\n${event.receiptRef ?? 'No external receipt recorded'}'),
              );
            },
          )),
        TextButton(
          onPressed: feed.loading ? null : () => unawaited(feed.refresh()),
          child: Text(feed.hasMore ? 'Load more recorded events' : 'Refresh execution events'),
        ),
        const Text('A provider response is not task completion. Acceptance requires a verification receipt.'),
      ]),
    ),
  );
}
