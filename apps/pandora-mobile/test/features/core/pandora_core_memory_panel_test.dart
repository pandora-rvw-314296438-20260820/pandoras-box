import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_core_memory_api.dart';
import 'package:pandora_mobile/features/core/pandora_core_memory_panel.dart';

Map<String, dynamic> envelope() => {
      'ok': true,
      'operation': 'context',
      'organizationId': '2270b266-59da-4c39-bfd9-9f8d08352af0',
      'projectId': 'ee282126-3f61-4058-8c92-2fedbfcecf1f',
      'authorizationGranted': false,
      'data': {
        'state': 'available',
        'authorizationGranted': false,
        'context': {
          'schemaVersion': 'm5.task-aware-retrieval.v1',
          'status': 'available',
          'namespace': 'real_life',
          'project': {'id': '7c686cbd-d968-49d5-86cc-918f5e777bd2'},
          'contextSha256': 'a' * 64,
          'asOf': '2026-10-03T05:00:00Z',
          'authorization': {
            'principalKey': 'pandora-mcpmaster-production',
            'environment': 'production',
            'canRead': true,
            'retrievalDoesNotGrantExecutionAuthority': true,
          },
          'policyMemory': <Map<String, dynamic>>[],
          'advisoryMemory': [
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'title': 'Verify the deployed source',
              'summary': 'A successful build needs runtime readback.',
              'promotionBasis': 'Observed deployment mismatch.',
              'canonStatus': 'soft_canon',
              'recordType': 'failure_lesson',
              'knowledgeSchemaVersion': 'm5.v1',
              'authorizationEffect': 'none',
            }
          ],
          'degradation': {'degraded': false},
        },
      },
    };

class FakeMemory implements PandoraCoreMemoryGateway {
  FakeMemory(this.result);
  Future<PandoraCoreMemoryContext> Function() result;
  @override
  Future<PandoraCoreMemoryContext> load() => result();
}

void main() {
  test(
      'existing owner endpoint sends only a fixed read with the actual session',
      () async {
    var requests = 0;
    final gateway = HttpPandoraCoreMemoryGateway(
      accessToken: () => 'fixture-session',
      client: MockClient((request) async {
        requests++;
        expect(request.url.toString(),
            'https://mcpmaster.vercel.app/api/operations-memory');
        expect(request.followRedirects, false);
        expect(request.headers['authorization'], 'Bearer fixture-session');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, unorderedEquals(['operation', 'request']));
        expect(body['operation'], 'context');
        expect(body['request']['actionMode'], 'read_only');
        expect(body['request']['consequential'], false);
        return http.Response(jsonEncode(envelope()), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final context = await gateway.load();
    expect(context.records.single['canonStatus'], 'soft_canon');
    expect(requests, 1);
  });

  test('anonymous session makes no provider call', () async {
    final gateway = HttpPandoraCoreMemoryGateway(
        accessToken: () => null,
        client: MockClient((_) async => throw StateError('must not call')));
    await expectLater(
        gateway.load(),
        throwsA(isA<PandoraCoreFailure>()
            .having((e) => e.code, 'code', 'SIGN_IN_REQUIRED')));
  });

  test('session change during read discards the old owner reply', () async {
    var token = 'first-session';
    final gateway = HttpPandoraCoreMemoryGateway(
        accessToken: () => token,
        client: MockClient((_) async {
          token = 'second-session';
          return http.Response(jsonEncode(envelope()), 200,
              headers: {'content-type': 'application/json'});
        }));
    await expectLater(
        gateway.load(),
        throwsA(isA<PandoraCoreFailure>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED')));
  });

  for (final field in ['organizationId', 'projectId']) {
    test('rejects a mismatched $field', () {
      final response = envelope()..[field] = 'another-tenant';
      expect(() => PandoraCoreMemoryContext.fromResponse(response),
          throwsA(isA<PandoraCoreFailure>()));
    });
  }

  test('draft records and advisory authority escalation are rejected', () {
    for (final change in [
      {'canonStatus': 'draft'},
      {'authorizationEffect': 'allow'},
      {'recordType': 'policy'},
    ]) {
      final response = envelope();
      response['data']['context']['advisoryMemory'][0].addAll(change);
      expect(() => PandoraCoreMemoryContext.fromResponse(response),
          throwsA(isA<PandoraCoreFailure>()));
    }
  });

  test('raw provider errors remain private and denied is not an empty list',
      () async {
    final gateway = HttpPandoraCoreMemoryGateway(
        accessToken: () => 'session',
        client: MockClient(
            (_) async => http.Response('private-provider-detail', 403)));
    await expectLater(
        gateway.load(),
        throwsA(isA<PandoraCoreFailure>()
            .having((e) => e.code, 'code', 'ACCESS_DENIED')
            .having((e) => e.message.contains('private-provider-detail'),
                'redacted', false)));
  });

  testWidgets('small owner view opens a reviewed lesson and returns',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeMemory(
        () async => PandoraCoreMemoryContext.fromResponse(envelope()));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: PandoraCoreMemoryPanel(gateway: gateway)))));
    await tester.pumpAndSettle();
    expect(find.text('Approved Memory'), findsOneWidget);
    expect(find.text('Reviewed lesson'), findsOneWidget);
    await tester.tap(find.text('Verify the deployed source'));
    await tester.pumpAndSettle();
    expect(find.text('A successful build needs runtime readback.'),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed read offers retry and truthful empty state',
      (tester) async {
    final gateway = FakeMemory(() async => throw const PandoraCoreFailure(
        'MEMORY_UNAVAILABLE', 'Memory is unavailable right now.'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PandoraCoreMemoryPanel(gateway: gateway))));
    await tester.pumpAndSettle();
    expect(find.text('Memory is unavailable right now.'), findsOneWidget);
    expect(
        find.text('No approved lessons match this owner view.'), findsNothing);
    gateway.result = () async {
      final response = envelope();
      response['data']['context']['advisoryMemory'] = <Map<String, dynamic>>[];
      return PandoraCoreMemoryContext.fromResponse(response);
    };
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No approved lessons match this owner view.'),
        findsOneWidget);
  });

  testWidgets('late result from a previous gateway cannot replace active state',
      (tester) async {
    final pending = Completer<PandoraCoreMemoryContext>();
    final oldGateway = FakeMemory(() => pending.future);
    final replacement = FakeMemory(() async => throw const PandoraCoreFailure(
        'ACCESS_DENIED', 'This operator no longer has access.'));
    Widget app(PandoraCoreMemoryGateway gateway) => MaterialApp(
        home: Scaffold(body: PandoraCoreMemoryPanel(gateway: gateway)));
    await tester.pumpWidget(app(oldGateway));
    await tester.pumpWidget(app(replacement));
    await tester.pumpAndSettle();
    pending.complete(PandoraCoreMemoryContext.fromResponse(envelope()));
    await tester.pumpAndSettle();
    expect(find.text('This operator no longer has access.'), findsOneWidget);
    expect(find.text('Verify the deployed source'), findsNothing);
  });
}
