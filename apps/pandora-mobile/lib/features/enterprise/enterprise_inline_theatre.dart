import 'package:flutter/material.dart';

import '../../core/activity/pandora_activity_presentation_policy.dart';
import '../../core/activity/pandora_activity_projection.dart';
import '../../core/activity/pandora_activity_timeline.dart';
import '../../core/design/pandora_tokens.dart';
import '../simple/pandora_v2_ui.dart';

/// Owner-facing theatre phases for Enterprise inline Activity Theatre (P0-006).
enum EnterpriseTheatrePhase {
  /// No validated activity — theatre must be fully hidden.
  idle,
  running,
  needsYou,
  success,
  failed,
}

/// Compact verified receipt model after provider readback (P0-007).
@immutable
class EnterpriseTheatreReceipt {
  const EnterpriseTheatreReceipt({
    required this.summary,
    required this.history,
    this.identityScope,
  });

  final String summary;
  final List<String> history;
  final String? identityScope;
}

/// Projects validated [PandoraActivityProjection] events into theatre UI state.
///
/// Success is allowed only after the provider readback / verification gate.
/// Decorative Thinking / Analyzing / Resolving copy is never admitted.
class EnterpriseInlineTheatreController extends ChangeNotifier {
  final PandoraActivityTimelineReducer _reducer =
      PandoraActivityTimelineReducer();

  bool _historyExpanded = false;
  String? _identityScope;
  bool _disposed = false;

  List<PandoraActivityProjection> get events => _reducer.events;

  bool get isHistoryExpanded => _historyExpanded;

  String? get identityScope => _identityScope;

  EnterpriseTheatrePhase get phase {
    final visible = _visibleEvents;
    if (visible.isEmpty) return EnterpriseTheatrePhase.idle;
    final latest = visible.last;
    switch (latest.state) {
      case PandoraActivityState.needsYou:
        return EnterpriseTheatrePhase.needsYou;
      case PandoraActivityState.failed:
      case PandoraActivityState.cancelled:
        return EnterpriseTheatrePhase.failed;
      case PandoraActivityState.result:
        return enterpriseActivityHasReadbackGate(latest)
            ? EnterpriseTheatrePhase.success
            : EnterpriseTheatrePhase.failed;
      case PandoraActivityState.understanding:
      case PandoraActivityState.planning:
      case PandoraActivityState.acting:
      case PandoraActivityState.checking:
      case PandoraActivityState.retrying:
      case PandoraActivityState.fallback:
      case PandoraActivityState.verifying:
      case PandoraActivityState.paused:
      case PandoraActivityState.resuming:
        return EnterpriseTheatrePhase.running;
    }
  }

  bool get isActive => phase != EnterpriseTheatrePhase.idle;

  List<PandoraActivityProjection> get _visibleEvents {
    final out = <PandoraActivityProjection>[];
    for (final event in _reducer.events) {
      if (_isDecorativeTheatreCopy(event.message)) continue;
      if (!_isPresentableEnterpriseEvent(event)) continue;
      out.add(event);
    }
    return out;
  }

  String get statusLabel => switch (phase) {
        EnterpriseTheatrePhase.idle => '',
        EnterpriseTheatrePhase.running => 'Running',
        EnterpriseTheatrePhase.needsYou => 'Needs You',
        EnterpriseTheatrePhase.success => 'Success',
        EnterpriseTheatrePhase.failed => 'Failed',
      };

  String get liveAnnouncement {
    if (!isActive) return '';
    final latest = _visibleEvents.last;
    final body = _stepCopy(latest);
    final scope = _identityScope;
    final scopeSuffix = scope == null || scope.isEmpty ? '' : ' Scope $scope.';
    return 'Activity Theatre. $statusLabel. $body.$scopeSuffix';
  }

  String get primaryMessage {
    final visible = _visibleEvents;
    if (visible.isEmpty) return '';
    final latest = visible.last;
    if (phase == EnterpriseTheatrePhase.success) {
      return latest.outcome?.summary.trim().isNotEmpty == true
          ? latest.outcome!.summary.trim()
          : _stepCopy(latest);
    }
    if (phase == EnterpriseTheatrePhase.needsYou) {
      final blocker = latest.blocker;
      if (blocker != null) {
        return '${blocker.reason} ${blocker.requiredAction}'.trim();
      }
    }
    return _stepCopy(latest);
  }

  String? get requiredAction => phase == EnterpriseTheatrePhase.needsYou
      ? _visibleEvents.lastOrNull?.blocker?.requiredAction
      : null;

  EnterpriseTheatreReceipt? get receipt {
    if (phase != EnterpriseTheatrePhase.success &&
        phase != EnterpriseTheatrePhase.failed) {
      return null;
    }
    final history = _visibleEvents.map(_stepCopy).toList(growable: false);
    return EnterpriseTheatreReceipt(
      summary: primaryMessage,
      history: history,
      identityScope: _identityScope,
    );
  }

  /// Replace theatre content from validated fixture / stream projections.
  void replaceWith(
    Iterable<PandoraActivityProjection> events, {
    String? identityScope,
  }) {
    _ensureActive();
    _reducer.reset();
    _historyExpanded = false;
    _identityScope = identityScope;
    for (final event in events) {
      if (_isDecorativeTheatreCopy(event.message)) {
        // Fail closed: never admit decorative theatre steps.
        continue;
      }
      _reducer.merge(<PandoraActivityProjection>[event]);
    }
    notifyListeners();
  }

  /// Admit one validated Activity projection (deterministic timeline).
  void admit(PandoraActivityProjection event, {String? identityScope}) {
    _ensureActive();
    if (_isDecorativeTheatreCopy(event.message)) return;
    if (identityScope != null) _identityScope = identityScope;
    _reducer.merge(<PandoraActivityProjection>[event]);
    notifyListeners();
  }

  void setIdentityScope(String? scope) {
    _ensureActive();
    if (_identityScope == scope) return;
    _identityScope = scope;
    notifyListeners();
  }

  void toggleHistoryExpanded() {
    _ensureActive();
    if (receipt == null) return;
    _historyExpanded = !_historyExpanded;
    notifyListeners();
  }

  void setHistoryExpanded(bool expanded) {
    _ensureActive();
    if (_historyExpanded == expanded) return;
    _historyExpanded = expanded;
    notifyListeners();
  }

  /// Project incomplete identity / capability into Theatre Needs You (P0-003/P0-006).
  ///
  /// Uses a validated Needs You Activity projection — never invents Success.
  void admitIdentityNeedsYou({
    required String reason,
    String? identityScope,
    String requiredAction =
        'Confirm identity or choose the required scope, then retry.',
  }) {
    _ensureActive();
    final at = DateTime.now().toUtc();
    final jobId = 'enterprise-identity-${at.microsecondsSinceEpoch}';
    final message = reason.trim().isEmpty
        ? 'Identity is incomplete for this command.'
        : reason.trim();
    replaceWith([
      PandoraActivityProjection(
        eventId: '$jobId-1',
        jobId: jobId,
        sequence: 1,
        state: PandoraActivityState.needsYou,
        message: message,
        occurredAt: at,
        admittedAt: at,
        domain: 'enterprise',
        capability: 'enterprise_command',
        executionId: jobId,
        source: PandoraActivitySource(
          sourceType: 'runtime',
          sourceId: 'enterprise-command-host',
          sourceEventId: '$jobId-src',
          observedAt: at,
        ),
        evidenceRefs: const [
          PandoraActivityEvidenceRef(
            type: 'user_control',
            relation: 'accepted_control',
            ref: 'enterprise-identity-needs-you',
          ),
        ],
        blocker: PandoraActivityBlocker(
          reasonCode: 'missing_consequential_user_choice',
          reason: message,
          requiredAction: requiredAction,
          approvalRequired: true,
        ),
      ),
    ], identityScope: identityScope ?? _identityScope);
  }

  /// Dismiss / clear theatre — does not reverse any mutation (P0-007).
  void clear() {
    _ensureActive();
    _reducer.reset();
    _historyExpanded = false;
    _identityScope = null;
    notifyListeners();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('EnterpriseInlineTheatreController is disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// True when Success may be painted — provider verification / readback gate.
bool enterpriseActivityHasReadbackGate(PandoraActivityProjection event) {
  if (event.state != PandoraActivityState.result) return false;
  final hasVerification = event.evidenceRefs.any(
    (ref) =>
        ref.relation == 'verification' && ref.type == 'verification_receipt',
  );
  final hasReadback = event.evidenceRefs.any(
    (ref) =>
        ref.relation == 'readback' ||
        (ref.type == 'provider_receipt' && ref.relation == 'verification'),
  );
  // Outcome alone is never enough; verification or readback evidence required.
  return hasVerification || hasReadback;
}

bool _isPresentableEnterpriseEvent(PandoraActivityProjection event) {
  if (pandoraHasMeaningfulActivity(<PandoraActivityProjection>[event])) {
    return true;
  }
  final message = event.message.trim();
  if (message.isEmpty || _isDecorativeTheatreCopy(message)) return false;
  return event.state == PandoraActivityState.understanding ||
      event.state == PandoraActivityState.planning ||
      event.state == PandoraActivityState.acting ||
      event.state == PandoraActivityState.checking ||
      event.state == PandoraActivityState.verifying ||
      event.state == PandoraActivityState.needsYou ||
      event.state == PandoraActivityState.result ||
      event.state == PandoraActivityState.failed ||
      event.state == PandoraActivityState.cancelled;
}

bool _isDecorativeTheatreCopy(String message) {
  final normalized = message
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (normalized.isEmpty) return true;
  const banned = <String>{
    'thinking',
    'analyzing',
    'resolving',
    'thinking through the request',
    'analyzing the request',
    'resolving the request',
  };
  return banned.contains(normalized);
}

String _stepCopy(PandoraActivityProjection event) {
  final presented = pandoraActivityPresentationText(event).trim();
  if (presented.isNotEmpty && !_isDecorativeTheatreCopy(presented)) {
    return presented;
  }
  return event.message.trim();
}

extension on List<PandoraActivityProjection> {
  PandoraActivityProjection? get lastOrNull =>
      isEmpty ? null : this[length - 1];
}

/// Inline Activity Theatre mounted directly above the Enterprise command bar.
///
/// Idle = zero height and not an empty accessibility region (P0-004).
class EnterpriseInlineTheatre extends StatefulWidget {
  const EnterpriseInlineTheatre({super.key, required this.controller});

  final EnterpriseInlineTheatreController controller;

  static const theatreKey = ValueKey<String>('enterprise-inline-theatre');
  static const statusKey = ValueKey<String>('enterprise-inline-theatre-status');
  static const receiptKey = ValueKey<String>(
    'enterprise-inline-theatre-receipt',
  );
  static const viewKey = ValueKey<String>('enterprise-inline-theatre-view');
  static const historyKey = ValueKey<String>(
    'enterprise-inline-theatre-history',
  );
  static const liveRegionKey = ValueKey<String>(
    'enterprise-inline-theatre-live',
  );

  @override
  State<EnterpriseInlineTheatre> createState() =>
      _EnterpriseInlineTheatreState();
}

class _EnterpriseInlineTheatreState extends State<EnterpriseInlineTheatre> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant EnterpriseInlineTheatre oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.isActive) {
      // Idle: fully hidden — zero height, not an empty a11y region.
      return const SizedBox.shrink();
    }

    final phase = controller.phase;
    final receipt = controller.receipt;
    final isTerminal = phase == EnterpriseTheatrePhase.success ||
        phase == EnterpriseTheatrePhase.failed;
    final statusColor = switch (phase) {
      EnterpriseTheatrePhase.success => PandoraV2Colors.success,
      EnterpriseTheatrePhase.failed => PandoraV2Colors.danger,
      EnterpriseTheatrePhase.needsYou => PandoraV2Colors.warning,
      EnterpriseTheatrePhase.running => PandoraV2Colors.ink,
      EnterpriseTheatrePhase.idle => PandoraV2Colors.muted,
    };
    final statusIcon = switch (phase) {
      EnterpriseTheatrePhase.success => Icons.check_circle_outline_rounded,
      EnterpriseTheatrePhase.failed => Icons.error_outline_rounded,
      EnterpriseTheatrePhase.needsYou => Icons.priority_high_rounded,
      EnterpriseTheatrePhase.running => Icons.bolt_outlined,
      EnterpriseTheatrePhase.idle => Icons.circle_outlined,
    };

    return Material(
      key: EnterpriseInlineTheatre.theatreKey,
      color: PandoraV2Colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: EnterpriseInlineTheatre.liveRegionKey,
            liveRegion: true,
            container: true,
            label: controller.liveAnnouncement,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: DecoratedBox(
                key: isTerminal
                    ? EnterpriseInlineTheatre.receiptKey
                    : EnterpriseInlineTheatre.statusKey,
                decoration: BoxDecoration(
                  color: PandoraV2Colors.soft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PandoraV2Colors.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  controller.primaryMessage,
                                  style: const TextStyle(
                                    color: PandoraV2Colors.ink,
                                    fontSize: 13.5,
                                    height: 1.35,
                                  ),
                                ),
                                if (controller.identityScope != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Scope ${controller.identityScope}',
                                    style: const TextStyle(
                                      color: PandoraV2Colors.muted,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isTerminal && receipt != null)
                            TextButton(
                              key: EnterpriseInlineTheatre.viewKey,
                              onPressed: controller.toggleHistoryExpanded,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  PandoraSize.compactMark,
                                  PandoraSize.compactMark,
                                ),
                                foregroundColor: PandoraV2Colors.ink,
                              ),
                              child: Text(
                                controller.isHistoryExpanded ? 'Hide' : 'View',
                              ),
                            ),
                        ],
                      ),
                      if (controller.isHistoryExpanded && receipt != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          key: EnterpriseInlineTheatre.historyKey,
                          label: 'Activity history',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < receipt.history.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${i + 1}. ${receipt.history[i]}',
                                    style: const TextStyle(
                                      color: PandoraV2Colors.muted,
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
