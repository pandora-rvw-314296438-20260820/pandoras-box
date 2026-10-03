import 'package:flutter/material.dart';

import '../../core/data/pandora_core_api.dart';
import '../../core/data/pandora_core_memory_api.dart';

class PandoraCoreMemoryPanel extends StatefulWidget {
  const PandoraCoreMemoryPanel({super.key, this.gateway});

  final PandoraCoreMemoryGateway? gateway;

  @override
  State<PandoraCoreMemoryPanel> createState() => _PandoraCoreMemoryPanelState();
}

class _PandoraCoreMemoryPanelState extends State<PandoraCoreMemoryPanel> {
  late PandoraCoreMemoryGateway _gateway;
  PandoraCoreMemoryContext? _context;
  PandoraCoreFailure? _failure;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? HttpPandoraCoreMemoryGateway();
    _load();
  }

  @override
  void didUpdateWidget(covariant PandoraCoreMemoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _gateway = widget.gateway ?? HttpPandoraCoreMemoryGateway();
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
      _context = null;
    });
    try {
      final result = await _gateway.load();
      if (!mounted || generation != _generation) return;
      setState(() => _context = result);
    } on PandoraCoreFailure catch (failure) {
      if (mounted && generation == _generation) {
        setState(() => _failure = failure);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failure = const PandoraCoreFailure('MEMORY_UNAVAILABLE',
            'Memory is unavailable right now. Try again.'));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _kind(PandoraCoreRecord row) => switch (row['recordType']) {
        'failure_lesson' => 'Reviewed lesson',
        'fact' => 'Reviewed fact',
        'outcome' => 'Reviewed outcome',
        'provider_performance' => 'Provider evidence',
        'policy' => 'Approved policy',
        'procedure' => 'Reviewed procedure',
        _ => 'Reviewed Memory',
      };

  void _open(PandoraCoreRecord row) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(coreText(row['title'], _kind(row))),
              content: SingleChildScrollView(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(coreText(row['summary'], 'No summary is available.')),
                  if (coreText(row['promotionBasis'], '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(coreText(row['promotionBasis'])),
                  ],
                  const SizedBox(height: 16),
                  Text(_kind(row),
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final records = _context?.records ?? const <PandoraCoreRecord>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Approved Memory',
                style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
            tooltip: 'Refresh Memory',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_loading)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator())
      else if (_failure != null) ...[
        Text(_failure!.message),
        TextButton(onPressed: _load, child: const Text('Try again')),
      ] else if (records.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No approved lessons match this owner view.'))
      else ...[
        if (_context!.degraded)
          const Text('Showing the available approved records.'),
        for (final row in records) ...[
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(coreText(row['title'], _kind(row)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_kind(row)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(row)),
          const Divider(height: 1),
        ],
      ],
      const SizedBox(height: 20),
    ]);
  }
}
