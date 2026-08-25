import '../models/pandora_models.dart';
import '../network/pandora_api_error.dart';
import 'owner_projection.dart';

typedef PandoraRepositoryException = PandoraApiError;

enum RepositorySource { network, memoryCache }

class RepositorySnapshot<T> {
  const RepositorySnapshot({
    required this.data,
    required this.source,
    required this.fetchedAt,
    this.verifiedAt,
    this.staleAfter,
    this.requestId,
    this.degradedReason,
  });

  final T data;
  final RepositorySource source;
  final DateTime fetchedAt;
  final DateTime? verifiedAt;
  final DateTime? staleAfter;
  final String? requestId;
  final String? degradedReason;

  bool get isCached => source == RepositorySource.memoryCache;

  bool isStaleAt(DateTime now) =>
      isCached || (staleAfter != null && !staleAfter!.isAfter(now));

  RepositorySnapshot<T> asDegradedCache(String reason) => RepositorySnapshot<T>(
    data: data,
    source: RepositorySource.memoryCache,
    fetchedAt: fetchedAt,
    verifiedAt: verifiedAt,
    staleAfter: staleAfter,
    requestId: requestId,
    degradedReason: reason,
  );
}

enum ApprovalDecision {
  approve,
  reject;

  String get wireValue => name;
}

enum WorkerJobClass {
  nodeRegression('node_regression', 'Node regression'),
  supabaseMigrationReplay(
    'supabase_migration_replay',
    'Supabase migration replay',
  );

  const WorkerJobClass(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

class ApprovalDecisionResult {
  const ApprovalDecisionResult({
    required this.decision,
    required this.approval,
    this.requestId,
  });

  final String decision;
  final ApprovalSummary approval;
  final String? requestId;
}

class SafetyOverview {
  const SafetyOverview({
    required this.state,
    required this.status,
    required this.auditChain,
    required this.sections,
    required this.extraIdentityCheckAdvertised,
  });

  final String state;
  final String status;
  final AuditChainStatus auditChain;
  final List<SafetySection> sections;
  final bool extraIdentityCheckAdvertised;

  factory SafetyOverview.fromJson(Object? value) {
    final json = asJsonMap(value);
    final suppliedSections = asJsonList(json['sections']);
    final sections = suppliedSections.isNotEmpty
        ? suppliedSections.map(SafetySection.fromJson).toList(growable: false)
        : _integrationSections(json['integrations']);
    return SafetyOverview(
      state: jsonText(json['state'], fallback: 'not_checked'),
      status: jsonText(json['plainStatus'], fallback: 'Not checked'),
      auditChain: AuditChainStatus.fromJson(json['auditIntegrity']),
      sections: List<SafetySection>.unmodifiable(sections),
      extraIdentityCheckAdvertised: jsonBool(json['mfaRequiredForApproval']),
    );
  }

  static List<SafetySection> _integrationSections(Object? value) {
    final integrations = asJsonList(value);
    if (integrations.isEmpty) return const <SafetySection>[];
    final unique = <String, JsonMap>{};
    for (final entry in integrations) {
      final json = asJsonMap(entry);
      final provider = jsonText(json['provider'], fallback: 'Service');
      final key = normalizeProviderKey(provider);
      final existing = unique[key];
      if (existing == null ||
          _integrationAttentionRank(json) >
              _integrationAttentionRank(existing)) {
        unique[key] = json;
      }
    }
    final ordered = unique.values.toList(growable: true)
      ..sort(
        (left, right) =>
            _integrationAttentionRank(right)
                .compareTo(_integrationAttentionRank(left)),
      );
    final items = ordered
        .map((json) {
          final provider = jsonText(json['provider'], fallback: 'Service');
          final truth = _integrationTruth(json);
          final explanation = switch (truth) {
            ProviderTruthState.healthy =>
              'Fresh verification says this service is healthy.',
            ProviderTruthState.degraded =>
              'Fresh verification shows partial impairment.',
            ProviderTruthState.down =>
              'Fresh verification shows this service is failing.',
            ProviderTruthState.stale =>
              'A previous state exists, but its verification has expired.',
            ProviderTruthState.unknown =>
              'No reliable current health state is available.',
            ProviderTruthState.notConfigured =>
              'This service is intentionally not configured here.',
          };
          return SafetyItem.fromJson(<String, Object?>{
            'id': 'integration-${normalizeProviderKey(provider)}',
            'title': provider,
            'plainStatus': truth.label,
            'explanation': explanation,
          });
        })
        .toList(growable: false);
    return <SafetySection>[
      SafetySection(
        id: 'integrations',
        title: 'Connected services',
        items: List<SafetyItem>.unmodifiable(items),
      ),
    ];
  }

  static ProviderTruthState _integrationTruth(JsonMap integration) {
    final status = jsonText(integration['status']).toLowerCase();
    final freshness = FreshnessState.parse(integration['freshness']);
    if (status.contains('not configured') ||
        status.contains('not_configured')) {
      return ProviderTruthState.notConfigured;
    }
    if (freshness == FreshnessState.stale) return ProviderTruthState.stale;
    if (freshness == FreshnessState.notChecked) {
      return ProviderTruthState.unknown;
    }
    if (status.contains('down') ||
        status.contains('failed') ||
        status.contains('critical') ||
        status.contains('unhealthy') ||
        status.contains('unreachable')) {
      return ProviderTruthState.down;
    }
    if (status.contains('degraded') ||
        status.contains('warning') ||
        status.contains('partial') ||
        status.contains('impaired')) {
      return ProviderTruthState.degraded;
    }
    if (status.contains('healthy') ||
        status.contains('connected') ||
        status.contains('ready') ||
        status.contains('active')) {
      return ProviderTruthState.healthy;
    }
    return ProviderTruthState.unknown;
  }

  static int _integrationAttentionRank(JsonMap integration) =>
      switch (_integrationTruth(integration)) {
        ProviderTruthState.down => 5,
        ProviderTruthState.degraded => 4,
        ProviderTruthState.stale => 3,
        ProviderTruthState.unknown => 2,
        ProviderTruthState.notConfigured => 1,
        ProviderTruthState.healthy => 0,
      };
}

abstract interface class PandoraRepository {
  Future<RepositorySnapshot<HomeSummary>> home();

  Future<RepositorySnapshot<List<ProjectSummary>>> projects({
    bool allowCached = false,
  });

  Future<RepositorySnapshot<ProjectDetail>> project(
    String id, {
    bool allowCached = false,
  });

  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  });

  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals();

  Future<RepositorySnapshot<List<AuditEvent>>> activity({
    bool allowCached = false,
  });

  Future<RepositorySnapshot<SafetyOverview>> safety();

  Future<RepositorySnapshot<List<ActionDefinition>>> actions();

  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  });

  Future<IntakeReceipt> runAction({
    required String actionId,
    String? projectId,
    String? message,
    String? idempotencyKey,
  });

  Future<IntakeReceipt> verifyExactSource({
    required String projectId,
    required String exactSha,
    required WorkerJobClass jobClass,
    int? maxRuntimeSeconds,
    String? idempotencyKey,
  });

  Future<WorkerExecutionStatus> workerExecution({required String planId});

  Future<ApprovalDecisionResult> decideApproval({
    required String approvalId,
    required ApprovalDecision decision,
    String reason = '',
  });

  void clearReadOnlyCache();

  void dispose();
}

abstract interface class AuthorizationInvalidationSource {
  Stream<AuthorizationInvalidation> get authorizationInvalidations;
}

abstract interface class AuthenticatedIdentityBoundary {
  void beginAuthenticatedIdentityEpoch();
}

class StaleAuthenticatedIdentityException implements Exception {
  const StaleAuthenticatedIdentityException();
}

class AuthorizationInvalidation {
  const AuthorizationInvalidation({
    required this.generation,
    required this.kind,
    required this.message,
  });

  final int generation;
  final PandoraApiErrorKind kind;
  final String message;
}
