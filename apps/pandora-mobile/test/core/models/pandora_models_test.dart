import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/owner_api/$name.json').readAsStringSync());

Map<String, Object?> canonicalIntakeReceipt() => <String, Object?>{
      'reply': 'Pandora recorded the request and will prepare a plan.',
      'needsApproval': false,
      'actionId': 'action-fixture-1',
      'approvalId': null,
      'status': <String, Object?>{
        'whatChanged': 'A governed intake record was created.',
        'whereWeAre': 'Planning',
        'whatIsDone': 'The request was accepted.',
        'whatIsHappeningNow': 'Pandora is checking preconditions.',
        'whatIsStoppingUs': null,
        'whatIWillDoNext': 'Show the plan before any protected change.',
      },
    };

void expectContractField(Object? value, String field) {
  expect(
    () => IntakeReceipt.fromJson(value),
    throwsA(
      isA<PandoraModelContractException>().having(
        (error) => error.field,
        'field',
        field,
      ),
    ),
  );
}

void main() {
  test(
    'canonical project fixture parses without claiming unverified progress',
    () {
      final projects = asJsonList(fixture('projects'));
      final project = ProjectSummary.fromJson(projects.single);

      expect(project.name, 'Pandora Mobile');
      expect(project.progressPercent, 42);
      expect(project.progressVerified, isFalse);
      expect(project.progressLabel, 'Progress not verified');
      expect(project.freshness.state, FreshnessState.fresh);
    },
  );

  test(
    'out-of-range progress fails closed instead of inventing completion',
    () {
      final project = ProjectSummary.fromJson(<String, Object?>{
        'id': 'fixture',
        'name': 'Fixture',
        'progressPercent': 900,
        'progressVerified': true,
        'dataFreshness': 'future_state',
        'lastVerifiedAt': 'not-a-date',
      });

      expect(project.progressPercent, isNull);
      expect(project.progressVerified, isFalse);
      expect(project.freshness.state, FreshnessState.notChecked);
      expect(project.freshness.lastVerifiedAt, isNull);
    },
  );

  test('fresh fractional progress stays precise and bounds fail closed', () {
    ProjectSummary parse(Object progress) =>
        ProjectSummary.fromJson(<String, Object?>{
          'id': 'fixture',
          'name': 'Fixture',
          'progressPercent': progress,
          'progressVerified': true,
          'dataFreshness': 'fresh',
        });

    final fractional = parse(33.33);
    expect(fractional.progressPercent, 33.33);
    expect(fractional.progressVerified, isTrue);
    expect(fractional.progressLabel, '33.33% verified');
    expect(parse(100.01).progressPercent, isNull);
    expect(parse(-0.01).progressPercent, isNull);
    expect(parse('100').progressPercent, isNull);
    expect(parse('100').progressVerified, isFalse);

    final stringVerification = ProjectSummary.fromJson(<String, Object?>{
      'id': 'fixture',
      'name': 'Fixture',
      'progressPercent': 100,
      'progressVerified': 'true',
      'dataFreshness': 'fresh',
    });
    expect(stringVerification.progressPercent, 100);
    expect(stringVerification.progressVerified, isFalse);
  });

  test('missing required project identity raises a typed contract failure', () {
    expect(
      () => ProjectSummary.fromJson(<String, Object?>{'name': 'Fixture'}),
      throwsA(
        isA<PandoraModelContractException>().having(
          (error) => error.field,
          'field',
          'project.id',
        ),
      ),
    );
  });

  test('proof stages remain five distinct evidence claims', () {
    expect(EvidenceStage.values, <EvidenceStage>[
      EvidenceStage.documented,
      EvidenceStage.implemented,
      EvidenceStage.tested,
      EvidenceStage.deployed,
      EvidenceStage.productionVerified,
    ]);
    expect(
      EvidenceStage.parse('production_verified'),
      EvidenceStage.productionVerified,
    );
    expect(EvidenceStage.parse('unknown_future_stage'), isNull);
  });

  test('a deployment claim never implies implementation or test proof', () {
    final project = ProjectSummary.fromJson(<String, Object?>{
      'id': 'fixture',
      'name': 'Fixture',
      'proofStages': <String, Object?>{
        'deployed': 'verified',
        'future_proof': 'future_state',
      },
    });

    expect(
      project.evidenceState(EvidenceStage.deployed),
      EvidenceClaimState.verified,
    );
    expect(
      project.evidenceState(EvidenceStage.implemented),
      EvidenceClaimState.notChecked,
    );
    expect(
      project.evidenceState(EvidenceStage.tested),
      EvidenceClaimState.notChecked,
    );
    expect(
      project.evidenceStages.singleWhere((item) => item.stage == null).rawStage,
      'future_proof',
    );
  });

  test('freshness boundary uses an injected clock', () {
    final freshness = FreshnessInfo.fromJson(<String, Object?>{
      'staleAfter': '2026-08-14T02:00:00Z',
    }, now: DateTime.parse('2026-08-14T01:00:00Z'));
    expect(freshness.state, FreshnessState.fresh);
  });

  test('home ignores fallback priority that has no approval identity', () {
    final home = HomeSummary.fromJson(fixture('home'));
    expect(home.priority?.id, 'approval-fixture-1');

    final fallback = HomeSummary.fromJson(<String, Object?>{
      'systemHealth': <String, Object?>{},
      'priority': <String, Object?>{
        'whatWillHappen': 'Nothing needs you right now',
      },
      'counters': <String, Object?>{},
    });
    expect(fallback.priority, isNull);
  });

  test('missing home counters never masquerade as verified zeroes', () {
    final missing = HomeSummary.fromJson(<String, Object?>{});
    final explicit = HomeSummary.fromJson(<String, Object?>{
      'counters': <String, Object?>{
        'approvals': 0,
        'activeProjects': 0,
        'needsAttention': 0,
      },
    });

    expect(missing.countersVerified, isFalse);
    expect(explicit.countersVerified, isTrue);
    final stringCounters = HomeSummary.fromJson(<String, Object?>{
      'counters': <String, Object?>{
        'approvals': '0',
        'activeProjects': '0',
        'needsAttention': '0',
      },
    });
    expect(stringCounters.countersVerified, isFalse);
  });

  test('project detail discards arbitrary currentState from domain model', () {
    final detail = ProjectDetail.fromJson(fixture('project'));
    expect(detail.phases, hasLength(1));
    expect(detail.tasks, hasLength(1));
    expect(detail.evidence, hasLength(1));
    expect(detail.summary.progressVerified, isFalse);
    expect(detail.tasks.single.state, ProjectTaskState.inProgress);
  });

  test('task completion accepts only the canonical complete state', () {
    ProjectTask parse(String status) => ProjectTask.fromJson(<String, Object?>{
          'id': 'task-fixture',
          'title': 'Fixture task',
          'status': status,
        });

    expect(parse('complete').state, ProjectTaskState.complete);
    expect(parse('Incomplete').state, ProjectTaskState.unknown);
    expect(parse('Not complete').state, ProjectTaskState.unknown);
    expect(parse('completed').state, ProjectTaskState.unknown);
    expect(parse('IN PROGRESS').state, ProjectTaskState.unknown);
    expect(parse('waiting-approval').state, ProjectTaskState.unknown);
  });

  test('202 intake fixture maps only the documented receipt contract', () {
    final receipt = IntakeReceipt.fromJson(
      fixture('intake_receipt'),
      requestId: 'request-fixture-1',
    );
    expect(receipt.needsApproval, isTrue);
    expect(receipt.actionId, 'action-fixture-1');
    expect(receipt.approvalId, 'approval-fixture-1');
    expect(receipt.status.whatIWillDoNext, contains('plan'));
    expect(receipt.requestId, 'request-fixture-1');
  });

  test('intake receipt never invents a recorded-success reply', () {
    final json = canonicalIntakeReceipt()..remove('reply');
    expectContractField(json, 'intake.reply');
  });

  test('intake receipt requires a canonical boolean and action identity', () {
    final nonBoolean = canonicalIntakeReceipt()..['needsApproval'] = 'false';
    expectContractField(nonBoolean, 'intake.needsApproval');

    final missingActionId = canonicalIntakeReceipt()..remove('actionId');
    expectContractField(missingActionId, 'intake.actionId');

    final numericActionId = canonicalIntakeReceipt()..['actionId'] = 123;
    expectContractField(numericActionId, 'intake.actionId');

    final structuredReply = canonicalIntakeReceipt()
      ..['reply'] = <String, Object?>{'message': 'Recorded'};
    expectContractField(structuredReply, 'intake.reply');
  });

  test('intake receipt requires the complete canonical status', () {
    final json = canonicalIntakeReceipt();
    asJsonMap(json['status']).remove('whatIsDone');
    expectContractField(json, 'intake.status.whatIsDone');
  });

  test('approval-bearing intake receipt requires an approval identity', () {
    final json = canonicalIntakeReceipt()
      ..['needsApproval'] = true
      ..['approvalId'] = null;
    expectContractField(json, 'intake.approvalId');

    final structuredId = canonicalIntakeReceipt()
      ..['needsApproval'] = true
      ..['approvalId'] = <String, Object?>{'id': 'approval-fixture'};
    expectContractField(structuredId, 'intake.approvalId');
  });

  test('approval summary never invents a canonical identity', () {
    expect(
      () => ApprovalSummary.fromJson(<String, Object?>{}),
      throwsA(
        isA<PandoraModelContractException>().having(
          (error) => error.field,
          'field',
          'approval.id',
        ),
      ),
    );
    expect(
      () => ApprovalSummary.fromJson(<String, Object?>{'id': 123}),
      throwsA(isA<PandoraModelContractException>()),
    );
    expect(
      () => ProjectSummary.fromJson(<String, Object?>{
        'id': <String, Object?>{'value': 'project'},
        'name': 'Fixture',
      }),
      throwsA(isA<PandoraModelContractException>()),
    );
  });

  test(
    'approval decisions require pending state and a future exact expiry',
    () {
      final now = DateTime.parse('2026-08-14T01:00:00Z').toLocal();
      ApprovalSummary parse({
        Object? decision = 'pending',
        Object? expiresAt,
      }) =>
          ApprovalSummary.fromJson(<String, Object?>{
            'id': 'approval-fixture-1',
            'decision': decision,
            'expiresAt': expiresAt,
          });

      expect(parse(expiresAt: '2026-08-14T01:00:01Z').canDecideAt(now), isTrue);
      expect(parse(expiresAt: null).canDecideAt(now), isFalse);
      expect(parse(expiresAt: 'not-a-date').canDecideAt(now), isFalse);
      expect(parse(expiresAt: 20260815).canDecideAt(now), isFalse);
      expect(
        parse(expiresAt: <String, Object?>{'date': '2030-01-01'})
            .canDecideAt(now),
        isFalse,
      );
      expect(
        parse(expiresAt: '2026-08-14T01:00:00Z').canDecideAt(now),
        isFalse,
      );
      expect(
        parse(
          decision: 'approved',
          expiresAt: '2026-08-14T01:00:01Z',
        ).canDecideAt(now),
        isFalse,
      );
      expect(
        parse(
          decision: 'Pending',
          expiresAt: '2026-08-14T01:00:01Z',
        ).canDecideAt(now),
        isFalse,
      );
      final revoked = parse(
        decision: 'revoked',
        expiresAt: '2026-08-14T01:00:01Z',
      );
      expect(revoked.state, ApprovalState.revoked);
      expect(revoked.canDecideAt(now), isFalse);
    },
  );

  test('remaining canonical summary fixtures parse to typed owner models', () {
    final approval = ApprovalSummary.fromJson(
      asJsonList(fixture('approvals')).single,
    );
    final action = ActionDefinition.fromJson(
      asJsonList(fixture('actions')).single,
    );
    final activity = AuditEvent.fromJson(
      asJsonList(fixture('activity')).single,
    );
    final connection = ConnectionSummary.fromJson(
      asJsonList(fixture('connections')).single,
    );
    final safety = SafetyOverview.fromJson(fixture('safety'));

    expect(approval.risk, ActionRisk.high);
    expect(approval.reversible, isTrue);
    expect(action.executionMode, 'Plan first');
    expect(activity.summary, contains('exact candidate'));
    expect(connection.canRead, isTrue);
    expect(connection.canChange, isFalse);
    expect(safety.auditChain.valid, isTrue);
  });

  test('malformed boolean-like values cannot invent safety claims', () {
    final approval = ApprovalSummary.fromJson(<String, Object?>{
      'id': 'approval-fixture',
      'decision': 'pending',
      'reversible': 'true',
      'howWeCanUndoIt': 'Restore the prior state.',
    });
    final connection = ConnectionSummary.fromJson(<String, Object?>{
      'id': 'connection-fixture',
      'canRead': 'true',
      'canChange': 1,
    });
    final detail = ConnectionDetail.fromJson(<String, Object?>{
      'id': 'connection-fixture',
      'needsOwnerApprovalForChanges': 'false',
    });
    final audit = AuditChainStatus.fromJson(<String, Object?>{'valid': 'true'});
    final action = ActionDefinition.fromJson(<String, Object?>{
      'id': 'action-fixture',
      'extraIdentityCheckRequired': 'false',
    });
    final missingActionGate = ActionDefinition.fromJson(<String, Object?>{
      'id': 'action-fixture',
    });
    final malformedRollback = ApprovalSummary.fromJson(<String, Object?>{
      'id': 'approval-fixture',
      'decision': 'pending',
      'reversible': true,
      'howWeCanUndoIt': <String, Object?>{'steps': 'Restore prior state'},
    });

    expect(approval.reversible, isFalse);
    expect(connection.canRead, isFalse);
    expect(connection.canChange, isFalse);
    expect(detail.needsOwnerApprovalForChanges, isTrue);
    expect(audit.valid, isFalse);
    expect(action.extraIdentityCheckRequired, isTrue);
    expect(missingActionGate.extraIdentityCheckRequired, isTrue);
    expect(malformedRollback.reversible, isFalse);
  });

  test('structured values never leak into plain-language text fields', () {
    final event = AuditEvent.fromJson(<String, Object?>{
      'id': 'event-fixture',
      'type': <String, Object?>{'private': 'payload'},
      'summary': <String, Object?>{'private': 'payload'},
    });

    expect(event.type, 'Activity');
    expect(event.summary, 'Activity recorded');
    expect(event.summary, isNot(contains('private')));
  });
}
