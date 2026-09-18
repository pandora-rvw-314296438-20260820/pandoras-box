import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/activity/pandora_activity_presentation_policy.dart';
import '../../core/activity/pandora_activity_projection.dart';
import '../../core/activity/pandora_activity_timeline_controller.dart';
import '../../core/activity/pandora_activity_timeline_view.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../simple/pandora_v2_ui.dart';

enum OperationsRoomMode { execution, council, incident }

class OperationsRoomRole {
  const OperationsRoomRole({
    required this.id,
    required this.name,
    required this.title,
    required this.icon,
  });

  final String id;
  final String name;
  final String title;
  final IconData icon;
}

const operationsRoomRoles = <OperationsRoomRole>[
  OperationsRoomRole(
      id: 'athena',
      name: 'ATHENA',
      title: 'Chief of Staff',
      icon: Icons.account_balance_rounded),
  OperationsRoomRole(
      id: 'apollo',
      name: 'APOLLO',
      title: 'Product & UX',
      icon: Icons.auto_awesome_rounded),
  OperationsRoomRole(
      id: 'hermes',
      name: 'HERMES',
      title: 'Source & Project',
      icon: Icons.account_tree_rounded),
  OperationsRoomRole(
      id: 'hephaestus',
      name: 'HEPHAESTUS',
      title: 'Engineering',
      icon: Icons.handyman_rounded),
  OperationsRoomRole(
      id: 'themis',
      name: 'THEMIS',
      title: 'Security & Governance',
      icon: Icons.shield_rounded),
  OperationsRoomRole(
      id: 'artemis',
      name: 'ARTEMIS',
      title: 'Verification & Release',
      icon: Icons.verified_rounded),
];

class OperationsRoomParsedMessage {
  const OperationsRoomParsedMessage({required this.role, required this.text});
  final String role;
  final String text;
}

List<OperationsRoomParsedMessage> parseOperationsRoomReply(String reply) {
  final trimmed = reply.trim();
  if (trimmed.isEmpty) return const <OperationsRoomParsedMessage>[];
  final marker = RegExp(
    r'\[\[ROLE:(ATHENA|APOLLO|HERMES|HEPHAESTUS|THEMIS|ARTEMIS)\]\]',
    caseSensitive: false,
  );
  final matches = marker.allMatches(trimmed).toList(growable: false);
  if (matches.isEmpty) {
    return <OperationsRoomParsedMessage>[
      OperationsRoomParsedMessage(role: 'ATHENA', text: trimmed),
    ];
  }
  final result = <OperationsRoomParsedMessage>[];
  for (var index = 0; index < matches.length; index += 1) {
    final current = matches[index];
    final start = current.end;
    final end =
        index + 1 < matches.length ? matches[index + 1].start : trimmed.length;
    final body = trimmed.substring(start, end).trim();
    if (body.isEmpty) continue;
    result.add(
      OperationsRoomParsedMessage(
        role: (current.group(1) ?? 'ATHENA').toUpperCase(),
        text: body,
      ),
    );
  }
  return result.isEmpty
      ? <OperationsRoomParsedMessage>[
          OperationsRoomParsedMessage(role: 'ATHENA', text: trimmed)
        ]
      : result;
}

Set<String> operationsRoomMentions(String message) {
  final lower = message.toLowerCase();
  return operationsRoomRoles
      .where((role) => lower.contains('@${role.id}'))
      .map((role) => role.name)
      .toSet();
}

class PandoraOperationsRoomScreen extends StatefulWidget {
  const PandoraOperationsRoomScreen({super.key});

  @override
  State<PandoraOperationsRoomScreen> createState() =>
      _PandoraOperationsRoomScreenState();
}

class _PandoraOperationsRoomScreenState
    extends State<PandoraOperationsRoomScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final PandoraActivityTimelineController _activity =
      PandoraActivityTimelineController();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  final List<_RoomMessage> _messages = <_RoomMessage>[];

  OperationsRoomMode _mode = OperationsRoomMode.execution;
  String? _threadId;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _activity.addListener(_onActivityChanged);
    _messages.add(
      _RoomMessage.agent(
        role: 'ATHENA',
        text:
            'Operations Room is ready. Give me the objective, or @mention a specialist. '
            'Execution keeps me in the lead; Council asks the specialists for independent views; '
            'Incident narrows the room to engineering, security, verification, and me.',
      ),
    );
  }

  void _onActivityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _activity.removeListener(_onActivityChanged);
    _activity.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setMode(OperationsRoomMode mode) {
    if (_submitting || mode == _mode) return;
    setState(() => _mode = mode);
  }

  Future<void> _submit(String value) async {
    final message = value.trim();
    if (message.isEmpty || _submitting) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) {
      setState(() => _error = 'Pandora intelligence is not connected.');
      return;
    }

    final mentions = operationsRoomMentions(message);
    await _activity.clear();
    if (!mounted) return;
    setState(() {
      _messages.add(_RoomMessage.owner(message));
      _submitting = true;
      _error = null;
      _composer.clear();
    });
    _scheduleScroll();

    try {
      final execution = await intelligence.startChatExecution(
        message: message,
        requestId: _keys.create('operations-room'),
        threadId: _threadId,
        enterpriseContext: <String, Object?>{
          'surface': 'enterprise_operations_room',
          'route': '/enterprise/operations-room',
          'identityScope': 'enterprise_workspace',
          'capabilities': const <String>[
            'operations.room.read',
            'operations.room.coordinate',
          ],
          'selectedObject': <String, Object?>{
            'roomMode': _mode.name,
            'mentions': mentions.isEmpty ? 'none' : mentions.join(','),
          },
        },
      );
      await _activity.bind(jobId: execution.jobId, stream: execution.events);
      final turn = await execution.turn;
      if (!mounted) return;
      final parsed = parseOperationsRoomReply(turn.reply);
      setState(() {
        _threadId = turn.threadId;
        for (final item in parsed) {
          _messages.add(_RoomMessage.agent(role: item.role, text: item.text));
        }
      });
      _scheduleScroll();
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'The Operations Room could not complete this turn.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = pandoraLatestPresentableActivity(_activity.events);
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const PandoraPageHeader(title: 'Operations Room'),
            _RoomHeader(mode: _mode, onModeChanged: _setMode),
            Expanded(
              child: ListView.builder(
                key: const ValueKey<String>('operations-room-chat'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: _messages.length,
                itemBuilder: (context, index) =>
                    _RoomMessageBubble(message: _messages[index]),
              ),
            ),
            if (latest != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: PandoraV2Colors.line)),
                ),
                child: PandoraActivityTimelineView(
                  events: <PandoraActivityProjection>[latest],
                ),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                label: _error,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.danger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: PandoraV2Colors.danger.withValues(alpha: .25),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: PandoraV2Colors.danger, fontSize: 13),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: PandoraV2IntentSurface(
                key: const ValueKey<String>('operations-room-composer'),
                controller: _composer,
                hintText: _modeHint(_mode),
                onSubmit: _submit,
                enabled: !_submitting,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.mode, required this.onModeChanged});

  final OperationsRoomMode mode;
  final ValueChanged<OperationsRoomMode> onModeChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_rounded, size: 18, color: PandoraV2Colors.ink),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ATHENA leads the room',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'The team shares one conversation. Mention a specialist directly, or choose a room mode.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final role in operationsRoomRoles) ...[
                    _RoleChip(role: role),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<OperationsRoomMode>(
              segments: const <ButtonSegment<OperationsRoomMode>>[
                ButtonSegment(
                  value: OperationsRoomMode.execution,
                  label: Text('Execution'),
                  icon: Icon(Icons.play_arrow_rounded),
                ),
                ButtonSegment(
                  value: OperationsRoomMode.council,
                  label: Text('Council'),
                  icon: Icon(Icons.forum_outlined),
                ),
                ButtonSegment(
                  value: OperationsRoomMode.incident,
                  label: Text('Incident'),
                  icon: Icon(Icons.emergency_outlined),
                ),
              ],
              selected: <OperationsRoomMode>{mode},
              showSelectedIcon: false,
              onSelectionChanged: (values) {
                if (values.isNotEmpty) onModeChanged(values.first);
              },
            ),
          ],
        ),
      );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final OperationsRoomRole role;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${role.name} — ${role.title}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: PandoraV2Colors.soft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: PandoraV2Colors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(role.icon, size: 14, color: PandoraV2Colors.ink),
              const SizedBox(width: 6),
              Text(
                role.name,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .25,
                ),
              ),
            ],
          ),
        ),
      );
}

class _RoomMessageBubble extends StatelessWidget {
  const _RoomMessageBubble({required this.message});
  final _RoomMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isOwner) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.only(bottom: 14, left: 44),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: PandoraV2Colors.ink,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            message.text,
            style:
                const TextStyle(color: Colors.black, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }

    final role = _role(message.role);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 14, right: 24),
        padding: const EdgeInsets.fromLTRB(13, 12, 14, 13),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PandoraV2Colors.soft,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: PandoraV2Colors.line),
              ),
              child: Icon(role.icon, size: 17, color: PandoraV2Colors.ink),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        role.name,
                        style: const TextStyle(
                          color: PandoraV2Colors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          role.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    message.text,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomMessage {
  const _RoomMessage._({
    required this.text,
    required this.role,
    required this.isOwner,
  });

  factory _RoomMessage.owner(String text) =>
      _RoomMessage._(text: text, role: 'OWNER', isOwner: true);

  factory _RoomMessage.agent({required String role, required String text}) =>
      _RoomMessage._(text: text, role: role, isOwner: false);

  final String text;
  final String role;
  final bool isOwner;
}

OperationsRoomRole _role(String name) {
  final upper = name.toUpperCase();
  for (final role in operationsRoomRoles) {
    if (role.name == upper) return role;
  }
  return operationsRoomRoles.first;
}

String _modeHint(OperationsRoomMode mode) => switch (mode) {
      OperationsRoomMode.execution =>
        'Message Athena or @mention a specialist…',
      OperationsRoomMode.council => 'Ask the full council…',
      OperationsRoomMode.incident => 'Describe the incident…',
    };
