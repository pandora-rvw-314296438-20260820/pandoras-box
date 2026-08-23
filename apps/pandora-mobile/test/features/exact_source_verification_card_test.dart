import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/features/command/exact_source_verification_card.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

const _receipt = IntakeReceipt(
  reply: 'Verification plan recorded.',
  needsApproval: true,
  actionId: 'action-exact-source-1',
  approvalId: 'approval-exact-source-1',
  status: IntakeStatus(
    whatChanged: 'A plan was created.',
    whereWeAre: 'Waiting for approval.',
    whatIsDone: 'The source contract is fixed.',
    whatIsHappeningNow: 'No worker is running.',
    whatIWillDoNext: 'Wait for owner approval.',
  ),
);
const _exactSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _VerificationRepository extends FakeRepository {
  _VerificationRepository({
    this.ambiguous = false,
    this.transientFailure = false,
  });

  final bool ambiguous;
  final bool transientFailure;
  var calls = 0;
  var workerReads = 0;
  final submittedKeys = <String?>[];
  String? projectId;
  String? exactSha;
  WorkerJobClass? jobClass;
  int? maxRuntimeSeconds;
  String? idempotencyKey;

  @override
  Future<IntakeReceipt> verifyExactSource({
    required String projectId,
    required String exactSha,
    required WorkerJobClass jobClass,
    int? maxRuntimeSeconds,
    String? idempotencyKey,
  }) async {
    calls += 1;
    submittedKeys.add(idempotencyKey);
    this.projectId = projectId;
    this.exactSha = exactSha;
    this.jobClass = jobClass;
    this.maxRuntimeSeconds = maxRuntimeSeconds;
    this.idempotencyKey = idempotencyKey;
    if (ambiguous) {
      throw const PandoraApiError(
        kind: PandoraApiErrorKind.ambiguousMutation,
        message: 'Outcome unknown.',
        code: 'WORKER_PLAN_UNAVAILABLE',
      );
    }
    if (transientFailure && calls == 1) {
      throw const PandoraApiError(
        kind: PandoraApiErrorKind.unavailable,
        message: 'Temporarily unavailable.',
        code: 'TEMPORARY_UNAVAILABLE',
      );
    }
    return _receipt;
  }

  @override
  Future<WorkerExecutionStatus> workerExecution({
    required String planId,
  }) async {
    workerReads += 1;
    return super.workerExecution(planId: planId);
  }
}

Widget _subject(_VerificationRepository repository) => PandoraDependencies(
  auth: const FakeAuth(),
  repository: repository,
  diagnostics: DiagnosticsStore(),
  child: testApp(
    child: const Scaffold(
      body: SingleChildScrollView(child: ExactSourceVerificationCard()),
    ),
  ),
);

Future<void> _fillRequiredFields(
  WidgetTester tester, {
  bool selectMigrationReplay = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('exact-source-project-id')),
    'project-canonical-1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('exact-source-sha')),
    _exactSha,
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('exact-source-runtime')),
    '900',
  );
  if (selectMigrationReplay) {
    await tester.tap(
      find.byKey(const ValueKey<String>('exact-source-job-class')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supabase migration replay').last);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'submits every exact-source field through the dedicated contract',
    (tester) async {
      final repository = _VerificationRepository();
      await setTestSurface(tester, logicalSize: const Size(430, 1200));
      await tester.pumpWidget(_subject(repository));
      await _fillRequiredFields(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('exact-source-submit')),
      );
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(repository.projectId, 'project-canonical-1');
      expect(repository.exactSha, _exactSha);
      expect(repository.jobClass, WorkerJobClass.supabaseMigrationReplay);
      expect(repository.maxRuntimeSeconds, 900);
      expect(
        repository.idempotencyKey,
        startsWith('pandora:verify-exact-source:'),
      );
      expect(find.text('Verification plan recorded.'), findsOneWidget);
      expect(repository.workerReads, 1);
      expect(find.text('Independent final proof is available'), findsOneWidget);
      expect(find.text('Worker-01 claim: observed.'), findsOneWidget);
      expect(
        find.text('Final reviewer proof: available in this owner read.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a safe retry reuses the same exact idempotency key', (
    tester,
  ) async {
    final repository = _VerificationRepository(transientFailure: true);
    await setTestSurface(tester, logicalSize: const Size(430, 1200));
    await tester.pumpWidget(_subject(repository));
    await _fillRequiredFields(tester, selectMigrationReplay: false);

    await tester.tap(find.byKey(const ValueKey<String>('exact-source-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('exact-source-submit')));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(repository.submittedKeys[0], repository.submittedKeys[1]);
    expect(repository.workerReads, 1);
  });

  testWidgets('locks the write after an ambiguous outcome without retry UI', (
    tester,
  ) async {
    final repository = _VerificationRepository(ambiguous: true);
    await setTestSurface(tester, logicalSize: const Size(430, 1200));
    await tester.pumpWidget(_subject(repository));
    await _fillRequiredFields(tester, selectMigrationReplay: false);

    await tester.tap(find.byKey(const ValueKey<String>('exact-source-submit')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.textContaining('will not retry'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('exact-source-submit')),
    );
    expect(button.onPressed, isNull);
  });
}
