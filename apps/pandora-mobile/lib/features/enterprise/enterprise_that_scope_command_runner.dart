import '../../core/activity/pandora_activity_projection.dart';
import '../../core/data/enterprise_code_api.dart';
import 'enterprise_inline_theatre.dart';
import 'enterprise_page_context.dart';

/// Injectable that-scope provider port (Code surface).
///
/// Default production adapter wraps [EnterpriseCodeApi] (inspect / status /
/// deploy). Tests inject fakes — never call live Supabase from widget tests.
abstract class EnterpriseThatScopeProviderPort {
  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  });
}

/// Production port — thin wrap of [EnterpriseCodeApi].
class EnterpriseCodeApiThatScopePort
    implements EnterpriseThatScopeProviderPort {
  const EnterpriseCodeApiThatScopePort([
    this._api = const EnterpriseCodeApi(),
  ]);

  final EnterpriseCodeApi _api;

  @override
  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  }) =>
      _api.invoke(
        action,
        repositoryUrl: repositoryUrl,
        deploymentId: deploymentId,
      );
}

/// Runs accepted Enterprise command submits through that-scope theatre.
///
/// - `app_users`: no-op (P0-019 — no invented owner/App Users mutations).
/// - `code`: live provider mutation-or-refresh → readback → Success|Failed|Needs You.
/// - other surfaces: no fake Success (leave idle).
class EnterpriseThatScopeCommandRunner {
  EnterpriseThatScopeCommandRunner({
    EnterpriseThatScopeProviderPort? provider,
  }) : _provider = provider ?? const EnterpriseCodeApiThatScopePort();

  final EnterpriseThatScopeProviderPort _provider;

  /// Visible for tests — which provider port is bound.
  EnterpriseThatScopeProviderPort get provider => _provider;

  Future<void> run({
    required EnterpriseCommandSubmission submission,
    required EnterpriseInlineTheatreController theatre,
  }) async {
    if (!submission.accepted) return;

    final surface = submission.envelope.surface;
    if (surface == 'app_users') {
      // P0-019: never invent App Users / owner-identity mutations.
      return;
    }
    if (surface != 'code') {
      // Code is the acceptance path; do not fake Success on other surfaces.
      return;
    }

    await _runCodeThatScope(submission: submission, theatre: theatre);
  }

  Future<void> _runCodeThatScope({
    required EnterpriseCommandSubmission submission,
    required EnterpriseInlineTheatreController theatre,
  }) async {
    const thatScopeName = 'Code';
    final identityScope = submission.envelope.identityScope;
    final repositoryUrl = resolveRepositoryUrl(submission);
    final deploymentId = resolveDeploymentId(submission);

    if ((repositoryUrl == null || repositoryUrl.isEmpty) &&
        (deploymentId == null || deploymentId.isEmpty)) {
      theatre.admitIdentityNeedsYou(
        reason:
            'Provide a GitHub repository URL or deployment id before Code that-scope can continue.',
        identityScope: identityScope,
        requiredAction:
            'Enter a repository URL such as https://github.com/owner/repository, or a deployment id, then retry.',
      );
      return;
    }

    final at = DateTime.now().toUtc();
    final jobId = 'enterprise-code-${at.microsecondsSinceEpoch}';
    var sequence = 0;

    theatre.admit(
      _event(
        jobId: jobId,
        sequence: ++sequence,
        state: PandoraActivityState.acting,
        message:
            'Running Code that-scope on $thatScopeName (surface+route+identityScope).',
        occurredAt: at,
        evidence: const [
          PandoraActivityEvidenceRef(
            type: 'runtime_event',
            relation: 'source',
            ref: 'enterprise-code-acting',
          ),
        ],
      ),
      identityScope: identityScope,
    );

    final action = (deploymentId != null && deploymentId.isNotEmpty)
        ? 'status'
        : 'inspect';

    try {
      final payload = await _provider.invoke(
        action,
        repositoryUrl: repositoryUrl ?? '',
        deploymentId: deploymentId,
      );

      if (payload['ok'] != true) {
        final code = '${payload['code'] ?? 'PROVIDER_ERROR'}';
        theatre.admit(
          _event(
            jobId: jobId,
            sequence: ++sequence,
            state: PandoraActivityState.failed,
            message: 'Code that-scope provider rejected the request ($code).',
            occurredAt: DateTime.now().toUtc(),
            evidence: [
              PandoraActivityEvidenceRef(
                type: 'provider_receipt',
                relation: 'failure',
                ref: 'enterprise-code-fail-$code',
              ),
            ],
          ),
          identityScope: identityScope,
        );
        return;
      }

      final receiptRef = _verificationRef(
        action: action,
        repositoryUrl: repositoryUrl,
        deploymentId: deploymentId,
        payload: payload,
      );
      final summary =
          'Code that-scope verified on $thatScopeName ($action readback).';

      theatre.admit(
        _event(
          jobId: jobId,
          sequence: ++sequence,
          state: PandoraActivityState.result,
          message: summary,
          occurredAt: DateTime.now().toUtc(),
          evidence: [
            PandoraActivityEvidenceRef(
              type: 'verification_receipt',
              relation: 'verification',
              ref: receiptRef,
            ),
            PandoraActivityEvidenceRef(
              type: 'provider_receipt',
              relation: 'readback',
              ref: '$receiptRef-readback',
            ),
          ],
          outcome: PandoraActivityOutcome(
            summary: summary,
            physicalDevice: false,
          ),
        ),
        identityScope: identityScope,
      );
    } catch (error) {
      final cleaned = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      theatre.admit(
        _event(
          jobId: jobId,
          sequence: ++sequence,
          state: PandoraActivityState.failed,
          message: cleaned.isEmpty
              ? 'Code that-scope provider call failed.'
              : cleaned,
          occurredAt: DateTime.now().toUtc(),
          evidence: const [
            PandoraActivityEvidenceRef(
              type: 'provider_receipt',
              relation: 'failure',
              ref: 'enterprise-code-provider-exception',
            ),
          ],
        ),
        identityScope: identityScope,
      );
    }
  }

  /// Extract https://github.com/owner/repo from message or selectedObject.
  static String? resolveRepositoryUrl(EnterpriseCommandSubmission submission) {
    final candidates = <String>[
      if (submission.envelope.selectedObject != null)
        submission.envelope.selectedObject!,
      submission.message,
    ];
    final pattern = RegExp(
      r'https://github\.com/[\w.-]+/[\w.-]+',
      caseSensitive: false,
    );
    for (final text in candidates) {
      final match = pattern.firstMatch(text.trim());
      if (match != null) {
        var url = match.group(0)!;
        if (url.endsWith('.git')) {
          url = url.substring(0, url.length - 4);
        }
        return url;
      }
    }
    return null;
  }

  /// Extract deployment id (dpl_…) from selectedObject or message.
  static String? resolveDeploymentId(EnterpriseCommandSubmission submission) {
    final candidates = <String>[
      if (submission.envelope.selectedObject != null)
        submission.envelope.selectedObject!,
      submission.message,
    ];
    final pattern = RegExp(r'\bdpl_[A-Za-z0-9]+\b');
    for (final text in candidates) {
      final match = pattern.firstMatch(text.trim());
      if (match != null) return match.group(0);
    }
    return null;
  }

  static String _verificationRef({
    required String action,
    required String? repositoryUrl,
    required String? deploymentId,
    required Map<String, dynamic> payload,
  }) {
    final deployment = payload['deployment'];
    if (deployment is Map && '${deployment['id'] ?? ''}'.trim().isNotEmpty) {
      return 'enterprise-code-verify-${deployment['id']}'.trim();
    }
    if (deploymentId != null && deploymentId.isNotEmpty) {
      return 'enterprise-code-verify-$deploymentId';
    }
    if (repositoryUrl != null && repositoryUrl.isNotEmpty) {
      return 'enterprise-code-verify-$action-${repositoryUrl.hashCode.abs()}';
    }
    return 'enterprise-code-verify-$action';
  }

  static PandoraActivityProjection _event({
    required String jobId,
    required int sequence,
    required PandoraActivityState state,
    required String message,
    required DateTime occurredAt,
    required List<PandoraActivityEvidenceRef> evidence,
    PandoraActivityOutcome? outcome,
  }) {
    return PandoraActivityProjection(
      eventId: '$jobId-$sequence',
      jobId: jobId,
      sequence: sequence,
      state: state,
      message: message,
      occurredAt: occurredAt,
      admittedAt: occurredAt,
      domain: 'enterprise',
      capability: 'enterprise_code',
      executionId: jobId,
      source: PandoraActivitySource(
        sourceType: 'provider',
        sourceId: 'enterprise-that-scope-runner',
        sourceEventId: '$jobId-src-$sequence',
        observedAt: occurredAt,
      ),
      evidenceRefs: evidence,
      outcome: outcome,
    );
  }
}
