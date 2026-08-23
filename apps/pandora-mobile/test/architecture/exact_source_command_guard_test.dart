import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact-source command stays explicit, bounded, and single-send', () {
    final repositoryContract = File('lib/core/data/pandora_repository.dart')
        .readAsStringSync();
    final remoteRepository = File(
      'lib/core/data/remote_pandora_repository.dart',
    ).readAsStringSync();
    final httpClient = File('lib/core/network/pandora_api_client.dart')
        .readAsStringSync();
    final verificationCard = File(
      'lib/features/command/exact_source_verification_card.dart',
    ).readAsStringSync();
    final commandScreen = File('lib/features/command/command_screen.dart')
        .readAsStringSync();

    expect(repositoryContract, contains("'node_regression'"));
    expect(repositoryContract, contains("'supabase_migration_replay'"));
    expect(repositoryContract, contains('required String projectId'));
    expect(repositoryContract, contains('required String exactSha'));
    expect(repositoryContract, contains('int? maxRuntimeSeconds'));

    expect(remoteRepository, contains("'verify-exact-source'"));
    expect(remoteRepository, contains("'projectId': project"));
    expect(remoteRepository, contains("'exactSha': sourceSha"));
    expect(remoteRepository, contains("'jobClass': jobClass.wireValue"));
    expect(remoteRepository, contains('maxRuntimeSeconds < 30'));
    expect(remoteRepository, contains('maxRuntimeSeconds > 1800'));
    expect(remoteRepository, contains(r"RegExp(r'^[0-9a-f]{40}$')"));

    expect(verificationCard, contains('.verifyExactSource('));
    expect(verificationCard, contains('_lockedAfterAmbiguousOutcome'));
    expect(verificationCard, isNot(contains('.runAction(')));
    expect(verificationCard, isNot(contains('Retry same request')));
    expect(commandScreen, isNot(contains('Retry same request')));

    expect(
      RegExp(r'_httpClient\.send\(request\)').allMatches(httpClient),
      hasLength(1),
      reason: 'The transport must have one send site and no retry loop.',
    );
  });
}
