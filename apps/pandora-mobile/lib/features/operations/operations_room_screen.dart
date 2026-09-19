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
import 'operations_room_roles.dart';

export 'operations_room_roles.dart';

enum OperationsRoomMode { execution, council, incident }

const _roomThreadPrefix = 'Operations Room';
const _internalRoomMarker = '[OPERATIONS_ROOM_INTERNAL]';
const operationsRoomActiveArchitecture =
    'Phone-resident local AI first when appropriate. '
    'Qwen2.5 3B Q4_K_M is the primary phone-local candidate. '
    'Escalate to Gemini or another approved cloud model only when the phone '
    'should not handle the workload. No RDP-hosted LLMs, AWS, Bedrock, or '
    'continuously available desktop compute. GitHub, Supabase, and Vercel '
    'are the active infrastructure and control providers. GPU/NPU '
    'acceleration remains unverified until measured on the physical phone.';

class OperationsRoomParsedMessage {
  const OperationsRoomParsedMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;
}

List<OperationsRoomParsedMessage> parseOperationsRoomReply(String reply) {
  final trimmed = reply.trim();
  if (trimmed.isEmpty) return const <OperationsRoomParsedMessage>[];
  final names = operationsRoomRoles.map((role) => role.name).join('|');
  final marker = RegExp(
    '\\[\\[ROLE:($names)\\]\\]',
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
          OperationsRoomParsedMessage(role: 'ATHENA', text: trimmed),
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

List<String> operationsRoomRecommendedRoles(
  String message,
  OperationsRoomMode mode,
) {
  final direct = operationsRoomMentions(message);
  if (direct.isNotEmpty) {
    return operationsRoomRoles
        .where((role) => direct.contains(role.name) && role.name != 'ATHENA')
        .map((role) => role.name)
        .toList(growable: false);
  }

  if (mode == OperationsRoomMode.incident) {
    return const <String>[
      'HEPHAESTUS',
      'THEMIS',
      'ARTEMIS',
      'ASCLEPIUS',
      'HESTIA',
    ];
  }
  if (mode == OperationsRoomMode.council) {
    return const <String>[
      'APOLLO',
      'HERMES',
      'HEPHAESTUS',
      'THEMIS',
      'ARTEMIS',
    ];
  }

  final lower = message.toLowerCase();
  final selected = <String>[];

  void add(Iterable<String> roles) {
    for (final role in roles) {
      if (!selected.contains(role)) selected.add(role);
    }
  }

  bool hasAny(List<String> terms) => terms.any(lower.contains);

  if (hasAny(<String>[
    'ui',
    'ux',
    'screen',
    'layout',
    'design',
    'mobile',
    'android',
    'chat',
    'navigation',
    'composer',
  ])) {
    add(const <String>['APOLLO', 'HEPHAESTUS', 'HERMES', 'ARTEMIS']);
  }
  if (hasAny(<String>[
    'slow',
    'performance',
    'crash',
    'offline',
    'reliability',
    'device',
    'latency',
    'stuck',
    'recovery',
  ])) {
    add(const <String>['HEPHAESTUS', 'HESTIA', 'ASCLEPIUS', 'ARTEMIS']);
  }
  if (hasAny(<String>[
    'phone local',
    'phone-local',
    'on-device',
    'local ai',
    'local inference',
    'qwen',
    'q4_k_m',
    'gguf',
    'gpu',
    'npu',
  ])) {
    add(const <String>['HECATE', 'HEPHAESTUS', 'ARTEMIS', 'THEMIS']);
  }
  if (hasAny(<String>[
    'model',
    'provider',
    'routing',
    'llm',
    'local ai',
    'automation',
    'fallback',
    'token cost',
  ])) {
    add(const <String>['HECATE', 'NIKE', 'PROMETHEUS']);
  }
  if (hasAny(<String>[
    'memory',
    'remember',
    'learn',
    'lesson',
    'history',
    'knowledge',
  ])) {
    add(const <String>['MNEMOSYNE', 'HECATE']);
  }
  if (hasAny(<String>[
    'email',
    'message',
    'notification',
    'workspace',
    'integration',
    'webhook',
    'slack',
    'gmail',
  ])) {
    add(const <String>['IRIS', 'HERMES', 'THEMIS']);
  }
  if (hasAny(<String>[
    'data',
    'database',
    'schema',
    'etl',
    'supabase',
    'query',
    'table',
  ])) {
    add(const <String>['DEMETER', 'HEPHAESTUS', 'THEMIS', 'ARTEMIS']);
  }
  if (hasAny(<String>[
    'analytics',
    'conversion',
    'kpi',
    'outcome',
    'retention',
    'posthog',
    'experiment',
  ])) {
    add(const <String>['NIKE', 'APOLLO', 'DEMETER']);
  }
  if (hasAny(<String>[
    'security',
    'auth',
    'permission',
    'credential',
    'secret',
    'governance',
    'risk',
  ])) {
    add(const <String>['THEMIS', 'HEPHAESTUS', 'ARTEMIS']);
  }
  if (hasAny(<String>[
    'research',
    'new capability',
    'innovation',
    'prototype',
    'emerging',
  ])) {
    add(const <String>['PROMETHEUS', 'HECATE', 'NIKE']);
  }
  if (selected.isEmpty &&
      hasAny(<String>[
        'build',
        'fix',
        'deploy',
        'release',
        'code',
        'repo',
        'github',
        'apk',
      ])) {
    add(const <String>['APOLLO', 'HERMES', 'HEPHAESTUS', 'ARTEMIS']);
  }

  return selected.take(4).toList(growable: false);
}

String operationsRoomRoleText(String reply, String expectedRole) {
  final parsed = parseOperationsRoomReply(reply);
  for (final item in parsed) {
    if (item.role == expectedRole.toUpperCase()) return item.text;
  }
  if (parsed.length == 1 && parsed.single.text.trim().isNotEmpty) {
    return parsed.single.text.trim();
  }
  return reply.trim();
}

class PandoraOperationsRoomScreen extends StatefulWidget {
  const PandoraOperationsRoomScreen({
    super.key,
    this.onHome,
  });

  final VoidCallback? onHome;

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
  bool _restoreStarted = false;
  bool _restoring = false;
  bool _expandedRoster = false;
  Set<String> _activeRoles = const <String>{};

  @override
  void initState() {
    super.initState();
    _activity.addListener(_onActivityChanged);
    _messages.add(
      _RoomMessage.agent(
        role: 'ATHENA',
        text:
            'The Operations Room is ready. Tell the room what you want done, @mention a specialist, or use @room and I will summon the smallest useful team.',
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoreStarted) return;
    _restoreStarted = true;
    unawaited(_restoreRoom());
  }

  void _onActivityChanged() {
    if (mounted) {
      setState(() {});
      _scheduleScroll();
    }
  }

  @override
  void dispose() {
    _activity.removeListener(_onActivityChanged);
    _activity.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _threadTitle(OperationsRoomMode mode) =>
      '$_roomThreadPrefix · ${mode.name}';

  OperationsRoomMode _modeFromTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.endsWith('· council')) return OperationsRoomMode.council;
    if (lower.endsWith('· incident')) return OperationsRoomMode.incident;
    return OperationsRoomMode.execution;
  }

  Future<void> _restoreRoom() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    setState(() => _restoring = true);
    try {
      final threads = await intelligence.recentThreads(limit: 100);
      PandoraIntelligenceThread? room;
      for (final thread in threads) {
        if (thread.title == _roomThreadPrefix ||
            thread.title.startsWith('$_roomThreadPrefix · ')) {
          room = thread;
          break;
        }
      }
      if (room == null) return;
      final saved = await intelligence.messages(room.id, limit: 500);
      final restored = <_RoomMessage>[];
      for (final message in saved) {
        if (message.isUser) {
          if (message.content.contains(_internalRoomMarker)) continue;
          restored.add(
            _RoomMessage.owner(
              message.content,
              createdAt: message.createdAt,
            ),
          );
          continue;
        }
        for (final parsed in parseOperationsRoomReply(message.content)) {
          restored.add(
            _RoomMessage.agent(
              role: parsed.role,
              text: parsed.text,
              createdAt: message.createdAt,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _threadId = room!.id;
        _mode = _modeFromTitle(room.title);
        if (restored.isNotEmpty) {
          _messages
            ..clear()
            ..addAll(restored);
        }
      });
      _scheduleScroll();
    } on PandoraIntelligenceException {
      // A room can still operate when history is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _setMode(OperationsRoomMode mode) {
    if (_submitting || mode == _mode) return;
    setState(() => _mode = mode);
    final intelligence = PandoraDependencies.of(context).intelligence;
    final threadId = _threadId;
    if (intelligence != null && threadId != null) {
      unawaited(
        intelligence
            .renameThread(threadId, _threadTitle(mode))
            .catchError((Object _) {}),
      );
    }
  }

  void _mentionRole(OperationsRoomRole role) {
    if (_submitting) return;
    final mention = '@${role.id}';
    final current = _composer.text.trimRight();
    if (current.toLowerCase().contains(mention)) return;
    final next = current.isEmpty ? '$mention ' : '$current $mention ';
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _setActive(String role) {
    if (!mounted) return;
    setState(() => _activeRoles = <String>{role});
  }

  Future<PandoraIntelligenceTurn> _runRoomTurn({
    required PandoraIntelligenceApi intelligence,
    required String message,
    required String stage,
    required String targetRole,
    required Set<String> mentions,
  }) async {
    final previousThread = _threadId;
    final execution = await intelligence.startChatExecution(
      message: message,
      requestId:
          _keys.create('operations-room-$stage-${targetRole.toLowerCase()}'),
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
          'orchestrationStage': stage,
          'targetRole': targetRole,
          'roomRosterVersion': 'operations-room-v2-14',
          'architectureVersion': 'phone-local-v1',
          'executionTopology': 'phone-local-first-cloud-escalation',
          'localModelCandidate': 'Qwen2.5 3B Q4_K_M',
          'infrastructurePolicy': 'github-supabase-vercel-only',
          'accelerationPolicy': 'physical-device-verification-required',
          'forbiddenCompute': 'rdp-hosted-llm,aws,bedrock,desktop-hosted-llm',
        },
      },
    );
    await _activity.bind(jobId: execution.jobId, stream: execution.events);
    final turn = await execution.turn;
    if (mounted) {
      setState(() => _threadId = turn.threadId);
    }
    if (previousThread == null && turn.threadId.isNotEmpty) {
      try {
        await intelligence.renameThread(turn.threadId, _threadTitle(_mode));
      } on PandoraIntelligenceException {
        // Persistence remains valid even when the friendly room title cannot update.
      }
    }
    return turn;
  }

  String _specialistPrompt({
    required String objective,
    required String role,
    required List<String> priorFindings,
  }) {
    final handoff = priorFindings.isEmpty
        ? ''
        : '\n\nVisible room handoff from specialists who already spoke:\n'
            '${priorFindings.join('\n\n')}';
    return '$objective\n\n$_internalRoomMarker\n'
        'Take the next real Operations Room turn as $role. '
        'Respond only from $role authority. Do not claim actions that did not run. '
        'Active architecture constraint: $operationsRoomActiveArchitecture'
        '$handoff';
  }

  String _athenaPrompt({
    required String objective,
    required List<String> findings,
    required bool allowExecution,
  }) =>
      '$objective\n\n$_internalRoomMarker\n'
      'Specialist messages already produced in this same room:\n'
      '${findings.join('\n\n')}\n\n'
      'ATHENA: coordinate these real specialist findings into the next owner-facing result. '
      '${allowExecution ? 'Execution mode is active: use only real admitted capability routes when the owner objective requires action, and report provider/runtime evidence rather than promises.' : 'This is an advisory synthesis turn. Preserve material disagreement and do not execute capabilities.'} '
      'Active architecture constraint: $operationsRoomActiveArchitecture';

  Future<void> _submit(String value) async {
    final message = value.trim();
    if (message.isEmpty || _submitting) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) {
      setState(() => _error = 'Pandora intelligence is not connected.');
      return;
    }

    final mentions = operationsRoomMentions(message);
    final roles = operationsRoomRecommendedRoles(message, _mode);
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
      if (roles.isEmpty) {
        _setActive('ATHENA');
        final turn = await _runRoomTurn(
          intelligence: intelligence,
          message: message,
          stage: 'lead',
          targetRole: 'ATHENA',
          mentions: mentions,
        );
        if (!mounted) return;
        final parsed = parseOperationsRoomReply(turn.reply);
        setState(() {
          for (final item in parsed) {
            _messages.add(_RoomMessage.agent(role: item.role, text: item.text));
          }
        });
        _scheduleScroll();
        return;
      }

      final findings = <String>[];
      for (var index = 0; index < roles.length; index += 1) {
        final role = roles[index];
        _setActive(role);
        final turn = await _runRoomTurn(
          intelligence: intelligence,
          message: index == 0
              ? message
              : _specialistPrompt(
                  objective: message,
                  role: role,
                  priorFindings: _mode == OperationsRoomMode.execution
                      ? findings
                      : const <String>[],
                ),
          stage: 'specialist_analysis',
          targetRole: role,
          mentions: mentions,
        );
        if (!mounted) return;
        final roleText = operationsRoomRoleText(turn.reply, role);
        findings.add('$role: $roleText');
        setState(() {
          _messages.add(_RoomMessage.agent(role: role, text: roleText));
        });
        _scheduleScroll();
      }

      _setActive('ATHENA');
      final allowExecution = _mode == OperationsRoomMode.execution;
      final athena = await _runRoomTurn(
        intelligence: intelligence,
        message: _athenaPrompt(
          objective: message,
          findings: findings,
          allowExecution: allowExecution,
        ),
        stage: allowExecution ? 'lead' : 'athena_synthesis',
        targetRole: 'ATHENA',
        mentions: mentions,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          _RoomMessage.agent(
            role: 'ATHENA',
            text: operationsRoomRoleText(athena.reply, 'ATHENA'),
          ),
        );
      });
      _scheduleScroll();
    } on PandoraIntelligenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The Operations Room could not complete this turn.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _activeRoles = const <String>{};
        });
      }
    }
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = pandoraLatestPresentableActivity(_activity.events);
    final itemCount = _messages.length + (latest == null ? 0 : 1);
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            PandoraPageHeader(title: 'Operations Room'),
            _RoomHeader(
              mode: _mode,
              activeRoles: _activeRoles,
              expandedRoster: _expandedRoster,
              onModeChanged: _setMode,
              onRosterToggle: () =>
                  setState(() => _expandedRoster = !_expandedRoster),
              onMention: _mentionRole,
              onHome: widget.onHome,
            ),
            Expanded(
              child: ListView.builder(
                key: const ValueKey<String>('operations-room-chat'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index < _messages.length) {
                    return _RoomMessageBubble(message: _messages[index]);
                  }
                  return Container(
                    key: const ValueKey<String>('operations-room-live-event'),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PandoraV2Colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: PandoraV2Colors.line),
                    ),
                    child: PandoraActivityTimelineView(
                      events: <PandoraActivityProjection>[latest!],
                    ),
                  );
                },
              ),
            ),
            if (_restoring)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Restoring room history…',
                  style: TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                label: _error,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.danger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: PandoraV2Colors.danger.withValues(alpha: .25),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: PandoraV2Colors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
  const _RoomHeader({
    required this.mode,
    required this.activeRoles,
    required this.expandedRoster,
    required this.onModeChanged,
    required this.onRosterToggle,
    required this.onMention,
    required this.onHome,
  });

  final OperationsRoomMode mode;
  final Set<String> activeRoles;
  final bool expandedRoster;
  final ValueChanged<OperationsRoomMode> onModeChanged;
  final VoidCallback onRosterToggle;
  final ValueChanged<OperationsRoomRole> onMention;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final visible = <OperationsRoomRole>[
      ...operationsRoomRoles.where((role) => role.core),
    ];
    if (expandedRoster) {
      for (final role in operationsRoomRoles.where((role) => !role.core)) {
        if (!visible.contains(role)) visible.add(role);
      }
    } else {
      for (final role in operationsRoomRoles) {
        if (activeRoles.contains(role.name) && !visible.contains(role)) {
          visible.add(role);
        }
      }
    }
    final hiddenCount = operationsRoomRoles.length - visible.length;
    final working = activeRoles.isEmpty
        ? null
        : '${activeRoles.join(' + ')} ${activeRoles.length == 1 ? 'is' : 'are'} working…';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PandoraV2Colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onHome != null)
                IconButton(
                  key: const ValueKey<String>('operations-room-home'),
                  tooltip: 'Home',
                  visualDensity: VisualDensity.compact,
                  onPressed: onHome,
                  icon: const Icon(
                    Icons.home_rounded,
                    size: 19,
                    color: PandoraV2Colors.ink,
                  ),
                )
              else
                const Icon(
                  Icons.hub_rounded,
                  size: 18,
                  color: PandoraV2Colors.ink,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  working ?? '14 specialists · shared team thread',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: working == null
                        ? PandoraV2Colors.muted
                        : PandoraV2Colors.ink,
                    fontSize: 12.5,
                    fontWeight:
                        working == null ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SingleChildScrollView(
            key: const ValueKey<String>('operations-room-roster'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final role in visible) ...[
                  _RoleChip(
                    role: role,
                    active: activeRoles.contains(role.name),
                    onTap: () => onMention(role),
                  ),
                  const SizedBox(width: 6),
                ],
                _RosterToggleChip(
                  label: expandedRoster
                      ? 'Core only'
                      : '+$hiddenCount specialists',
                  onTap: onRosterToggle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final option in OperationsRoomMode.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option == OperationsRoomMode.incident ? 0 : 6,
                    ),
                    child: _ModeButton(
                      mode: option,
                      selected: mode == option,
                      onTap: () => onModeChanged(option),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final OperationsRoomMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (mode) {
      OperationsRoomMode.execution => ('Execution', Icons.play_arrow_rounded),
      OperationsRoomMode.council => ('Council', Icons.forum_outlined),
      OperationsRoomMode.incident => ('Incident', Icons.emergency_outlined),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? PandoraV2Colors.ink : PandoraV2Colors.soft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PandoraV2Colors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.black : PandoraV2Colors.ink,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: selected ? Colors.black : PandoraV2Colors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.role,
    required this.active,
    required this.onTap,
  });

  final OperationsRoomRole role;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${role.name} — ${role.title}',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? PandoraV2Colors.ink.withValues(alpha: .12)
                  : PandoraV2Colors.soft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? PandoraV2Colors.ink : PandoraV2Colors.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(role.icon, size: 13, color: PandoraV2Colors.ink),
                const SizedBox(width: 5),
                Text(
                  role.name,
                  style: const TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RosterToggleChip extends StatelessWidget {
  const _RosterToggleChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: PandoraV2Colors.canvas,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: PandoraV2Colors.line),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: PandoraV2Colors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _RoomMessageBubble extends StatelessWidget {
  const _RoomMessageBubble({required this.message});
  final _RoomMessage message;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(message.createdAt.toLocal())
        .format(context);
    if (message.isOwner) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.only(bottom: 12, left: 36),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          decoration: BoxDecoration(
            color: PandoraV2Colors.ink,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'YOU · $time',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: .55),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final role = operationsRoomRole(message.role);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12, right: 18),
        padding: const EdgeInsets.fromLTRB(11, 10, 12, 11),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: PandoraV2Colors.soft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PandoraV2Colors.line),
              ),
              child: Icon(role.icon, size: 16, color: PandoraV2Colors.ink),
            ),
            const SizedBox(width: 9),
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
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${role.title} · $time',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    message.text,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 14,
                      height: 1.43,
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
    required this.createdAt,
  });

  factory _RoomMessage.owner(
    String text, {
    DateTime? createdAt,
  }) =>
      _RoomMessage._(
        text: text,
        role: 'OWNER',
        isOwner: true,
        createdAt: createdAt ?? DateTime.now(),
      );

  factory _RoomMessage.agent({
    required String role,
    required String text,
    DateTime? createdAt,
  }) =>
      _RoomMessage._(
        text: text,
        role: role,
        isOwner: false,
        createdAt: createdAt ?? DateTime.now(),
      );

  final String text;
  final String role;
  final bool isOwner;
  final DateTime createdAt;
}

String _modeHint(OperationsRoomMode mode) => switch (mode) {
      OperationsRoomMode.execution =>
        'Message the room, @mention a specialist, or use @room…',
      OperationsRoomMode.council => 'Ask the council for independent views…',
      OperationsRoomMode.incident => 'Describe the incident…',
    };
