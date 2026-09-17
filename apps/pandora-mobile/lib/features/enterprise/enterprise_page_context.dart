import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Dual-scope identity namespaces (OD-1 = C). Never infer from role alone.
abstract final class EnterpriseIdentityScope {
  static const pandoraOrg = 'pandora_org';
  static const plpStaff = 'plp_staff';

  static const values = <String>{pandoraOrg, plpStaff};
}

/// Canonical Enterprise page envelope attached to every command-bar submit.
///
/// Non-secret only — never put credentials, tokens, or passwords here.
@immutable
class EnterprisePageContext {
  const EnterprisePageContext({
    required this.project,
    required this.surface,
    required this.route,
    this.selectedObject,
    this.actorRole,
    this.capabilities = const <String>{},
    this.identityScope,
  });

  /// Workspace / project identity (slug or id) — never credentials.
  final String project;

  /// Enterprise surface key, e.g. `overview`, `app_users`.
  final String surface;

  /// Stable route id, e.g. `enterprise_overview`.
  final String route;

  /// Optional selected object on the page (may be null).
  final String? selectedObject;

  /// Provider-verified actor role in the active scope, when known.
  final String? actorRole;

  /// Capability tokens available to the actor on this surface.
  final Set<String> capabilities;

  /// Explicit `{pandora_org | plp_staff}` when identity commands are in scope.
  final String? identityScope;

  bool get hasActorIdentity =>
      actorRole != null && actorRole!.trim().isNotEmpty;

  bool get hasIdentityScope =>
      identityScope != null && EnterpriseIdentityScope.values.contains(identityScope);

  /// Incomplete identity/capability → Needs You (no silent invent).
  bool get isReadyForCommand {
    if (!hasActorIdentity) return false;
    if (surface == 'app_users' && !hasIdentityScope) return false;
    return true;
  }

  String? get readinessGap {
    if (!hasActorIdentity) {
      return 'Actor role is not verified for this page. Confirm identity before Pandora can continue.';
    }
    if (surface == 'app_users' && !hasIdentityScope) {
      return 'Choose an identity scope (Pandora org or PLP staff) before App Users commands.';
    }
    return null;
  }

  EnterprisePageContext copyWith({
    String? project,
    String? surface,
    String? route,
    String? selectedObject,
    bool clearSelectedObject = false,
    String? actorRole,
    bool clearActorRole = false,
    Set<String>? capabilities,
    String? identityScope,
    bool clearIdentityScope = false,
  }) =>
      EnterprisePageContext(
        project: project ?? this.project,
        surface: surface ?? this.surface,
        route: route ?? this.route,
        selectedObject:
            clearSelectedObject ? null : (selectedObject ?? this.selectedObject),
        actorRole: clearActorRole ? null : (actorRole ?? this.actorRole),
        capabilities: capabilities ?? this.capabilities,
        identityScope: clearIdentityScope
            ? null
            : (identityScope ?? this.identityScope),
      );

  /// Diagnostics-safe map — surface + project only as non-secret context.
  Map<String, Object?> toDiagnosticsMap() => <String, Object?>{
        'project': project,
        'surface': surface,
        'route': route,
        'selectedObject': selectedObject,
        'actorRole': actorRole,
        'capabilities': capabilities.toList()..sort(),
        'identityScope': identityScope,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnterprisePageContext &&
          project == other.project &&
          surface == other.surface &&
          route == other.route &&
          selectedObject == other.selectedObject &&
          actorRole == other.actorRole &&
          setEquals(capabilities, other.capabilities) &&
          identityScope == other.identityScope;

  @override
  int get hashCode => Object.hash(
        project,
        surface,
        route,
        selectedObject,
        actorRole,
        Object.hashAll(capabilities),
        identityScope,
      );
}

/// Result of a bar submit — never implies navigation to AskPandora.
@immutable
class EnterpriseCommandSubmission {
  const EnterpriseCommandSubmission({
    required this.message,
    required this.envelope,
    required this.accepted,
    this.needsYouReason,
  });

  final String message;
  final EnterprisePageContext envelope;
  final bool accepted;
  final String? needsYouReason;
}

/// The 15 Enterprise destinations (WAVE1 P0-001).
abstract final class EnterpriseDestinations {
  static const entries = <EnterpriseDestination>[
    EnterpriseDestination(
      label: 'Overview',
      surface: 'overview',
      route: 'enterprise_overview',
      destinationIndex: 8,
    ),
    EnterpriseDestination(
      label: 'App Users',
      surface: 'app_users',
      route: 'enterprise_app_users',
      destinationIndex: 9,
    ),
    EnterpriseDestination(
      label: 'Data',
      surface: 'data',
      route: 'enterprise_data',
      destinationIndex: 10,
    ),
    EnterpriseDestination(
      label: 'Analytics',
      surface: 'analytics',
      route: 'enterprise_analytics',
      destinationIndex: 11,
    ),
    EnterpriseDestination(
      label: 'Marketing',
      surface: 'marketing',
      route: 'enterprise_marketing',
      destinationIndex: 12,
    ),
    EnterpriseDestination(
      label: 'Domains',
      surface: 'domains',
      route: 'enterprise_domains',
      destinationIndex: 13,
    ),
    EnterpriseDestination(
      label: 'Integrations',
      surface: 'integrations',
      route: 'enterprise_integrations',
      destinationIndex: 14,
    ),
    EnterpriseDestination(
      label: 'Security',
      surface: 'security',
      route: 'enterprise_security',
      destinationIndex: 15,
    ),
    EnterpriseDestination(
      label: 'Code',
      surface: 'code',
      route: 'enterprise_code',
      destinationIndex: 16,
    ),
    EnterpriseDestination(
      label: 'Agents',
      surface: 'agents',
      route: 'enterprise_agents',
      destinationIndex: 17,
    ),
    EnterpriseDestination(
      label: 'Workflows',
      surface: 'workflows',
      route: 'enterprise_workflows',
      destinationIndex: 18,
    ),
    EnterpriseDestination(
      label: 'Logs',
      surface: 'logs',
      route: 'enterprise_logs',
      destinationIndex: 19,
    ),
    EnterpriseDestination(
      label: 'API',
      surface: 'api',
      route: 'enterprise_api',
      destinationIndex: 20,
    ),
    EnterpriseDestination(
      label: 'Settings',
      surface: 'settings',
      route: 'enterprise_settings',
      destinationIndex: 21,
    ),
    EnterpriseDestination(
      label: 'MCP',
      surface: 'mcp',
      route: 'enterprise_mcp',
      destinationIndex: 22,
    ),
  ];

  static const count = 15;

  static EnterpriseDestination? byIndex(int index) {
    for (final entry in entries) {
      if (entry.destinationIndex == index) return entry;
    }
    return null;
  }

  static bool isEnterpriseIndex(int index) => byIndex(index) != null;
}

@immutable
class EnterpriseDestination {
  const EnterpriseDestination({
    required this.label,
    required this.surface,
    required this.route,
    required this.destinationIndex,
  });

  final String label;
  final String surface;
  final String route;
  final int destinationIndex;
}

/// Owns the live [EnterprisePageContext] for the Enterprise shell.
class EnterprisePageContextController extends ChangeNotifier {
  EnterprisePageContextController({
    String project = 'plp-boracay',
    EnterprisePageContext? initial,
  }) : _envelope = initial ??
            EnterprisePageContext(
              project: project,
              surface: EnterpriseDestinations.entries.first.surface,
              route: EnterpriseDestinations.entries.first.route,
            );

  EnterprisePageContext _envelope;
  EnterpriseCommandSubmission? _lastSubmission;
  String? _needsYouReason;

  EnterprisePageContext get envelope => _envelope;
  EnterpriseCommandSubmission? get lastSubmission => _lastSubmission;
  String? get needsYouReason => _needsYouReason;

  void updateForDestination(EnterpriseDestination destination) {
    final next = _envelope.copyWith(
      surface: destination.surface,
      route: destination.route,
      // Selection is page-local; clear on surface change to avoid stale object.
      clearSelectedObject: true,
    );
    if (next == _envelope) return;
    _envelope = next;
    _needsYouReason = null;
    notifyListeners();
  }

  void setSelectedObject(String? selectedObject) {
    final next = selectedObject == null
        ? _envelope.copyWith(clearSelectedObject: true)
        : _envelope.copyWith(selectedObject: selectedObject);
    if (next == _envelope) return;
    _envelope = next;
    notifyListeners();
  }

  void setActor({
    String? actorRole,
    Set<String>? capabilities,
    String? identityScope,
    bool clearActorRole = false,
    bool clearIdentityScope = false,
  }) {
    final next = _envelope.copyWith(
      actorRole: actorRole,
      clearActorRole: clearActorRole,
      capabilities: capabilities,
      identityScope: identityScope,
      clearIdentityScope: clearIdentityScope,
    );
    if (next == _envelope) return;
    _envelope = next;
    _needsYouReason = null;
    notifyListeners();
  }

  void setIdentityScope(String? scope) {
    if (scope != null && !EnterpriseIdentityScope.values.contains(scope)) {
      _needsYouReason =
          'Identity scope must be pandora_org or plp_staff — not invented.';
      notifyListeners();
      return;
    }
    final clearingCrossDomain = scope != _envelope.identityScope;
    final next = _envelope.copyWith(
      identityScope: scope,
      clearIdentityScope: scope == null,
      clearSelectedObject: clearingCrossDomain,
    );
    if (next == _envelope && _needsYouReason == null) return;
    _envelope = next;
    _needsYouReason = null;
    notifyListeners();
  }

  void clearNeedsYou() {
    if (_needsYouReason == null) return;
    _needsYouReason = null;
    notifyListeners();
  }

  /// Attach current envelope to the command. Does not navigate.
  /// Incomplete identity/capability → Needs You stub (no silent invent).
  EnterpriseCommandSubmission submit(String rawMessage) {
    final message = rawMessage.trim();
    final snapshot = _envelope;
    if (message.isEmpty) {
      final empty = EnterpriseCommandSubmission(
        message: message,
        envelope: snapshot,
        accepted: false,
        needsYouReason: 'Enter a command for Pandora on this page.',
      );
      _lastSubmission = empty;
      _needsYouReason = empty.needsYouReason;
      notifyListeners();
      return empty;
    }

    final gap = snapshot.readinessGap;
    if (gap != null) {
      final blocked = EnterpriseCommandSubmission(
        message: message,
        envelope: snapshot,
        accepted: false,
        needsYouReason: gap,
      );
      _lastSubmission = blocked;
      _needsYouReason = gap;
      notifyListeners();
      return blocked;
    }

    final accepted = EnterpriseCommandSubmission(
      message: message,
      envelope: snapshot,
      accepted: true,
    );
    _lastSubmission = accepted;
    _needsYouReason = null;
    notifyListeners();
    return accepted;
  }
}

class EnterprisePageContextScope extends InheritedNotifier<EnterprisePageContextController> {
  const EnterprisePageContextScope({
    super.key,
    required EnterprisePageContextController controller,
    required super.child,
  }) : super(notifier: controller);

  static EnterprisePageContextController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EnterprisePageContextScope>();
    assert(scope != null, 'EnterprisePageContextScope missing above this widget.');
    return scope!.notifier!;
  }

  static EnterprisePageContextController? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EnterprisePageContextScope>();
    return scope?.notifier;
  }
}
