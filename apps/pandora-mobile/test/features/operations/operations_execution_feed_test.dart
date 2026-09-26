
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/pandora_operations_events.dart';
import 'package:pandora_mobile/features/operations/operations_execution_feed.dart';

final now = DateTime.utc(2026, 9, 26, 2, 30);
Map<String, dynamic> event([String id = '1']) => {
  'id': id, 'key': 'fixture:$id', 'type': 'tasks_ingested', 'taskId': 'TASK-$id',
  'receiptRef': null, 'occurredAt': now.toIso8601String(),
};
Map<String, dynamic> fixture() => {
  'schemaVersion': 'pandora-operations-events-v1',
  'organizationId': canonicalOperationsOrganization, 'projectId': canonicalOperationsProject,
  'authority': 'immutable_operations_events', 'syntheticProgress': false,
  'observedAt': now.toIso8601String(), 'events': [event()],
  'hasMore': false, 'nextCursor': '1', 'highWatermark': '1',
};
PandoraOperationsPage parse(Map<String, dynamic> value, {String after = '0'}) => PandoraOperationsPage.parse(value,
  organizationId: canonicalOperationsOrganization, projectId: canonicalOperationsProject, after: after, now: now);
class TrackedClient extends http.BaseClient {
  TrackedClient(Future<http.Response> Function(http.Request) action) : delegate = MockClient(action);
  final MockClient delegate;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => delegate.send(request);
  @override
  void close() { closed = true; delegate.close(); }
}

void main() {
  test('parses exact scoped provider evidence without inventing task completion', () {
    final page = parse(fixture());
    expect(page.events.single.label, 'Tasks added'); expect(page.events.single.taskComplete, isFalse);
    expect(page.nextCursor, '1'); expect(page.hasMore, isFalse);
  });
  for (final entry in <String, Object?>{
    'schemaVersion': 'other', 'organizationId': 'other', 'projectId': 'other',
    'authority': 'fixture-authority', 'syntheticProgress': true, 'events': null,
    'nextCursor': '2', 'highWatermark': '0', 'hasMore': 'false', 'observedAt': 'yesterday',
  }.entries) {
    test('rejects mismatched ${entry.key}', () => expect(() => parse({...fixture(), entry.key: entry.value}), throwsFormatException));
  }
  test('rejects stale or future event page', () {
    for (final observed in [now.subtract(const Duration(seconds: 61)), now.add(const Duration(seconds: 31))]) {
      expect(() => parse({...fixture(), 'observedAt': observed.toIso8601String()}), throwsFormatException);
    }
  });
  test('large sequence IDs retain integer precision', () {
    final page = parse({...fixture(), 'events': [event('9007199254740993')], 'nextCursor': '9007199254740993', 'highWatermark': '9007199254740993'});
    expect(page.events.single.id, '9007199254740993');
  });
  test('rejects sequence beyond signed database integer range', () => expect(() => parse({...fixture(), 'highWatermark': '9223372036854775808'}), throwsFormatException));
  test('rejects duplicate and out-of-order events', () {
    expect(() => parse({...fixture(), 'events': [event(), event()]}), throwsFormatException);
    expect(() => parse({...fixture(), 'events': [event('2'), event()], 'highWatermark': '2'}), throwsFormatException);
  });
  test('rejects a non-advancing has-more page', () => expect(() => parse({...fixture(), 'events': [], 'hasMore': true, 'nextCursor': '0'}), throwsFormatException));
  test('rejects oversized event batches', () => expect(() => parse({...fixture(), 'events': List.generate(201, (i) => event('${i + 1}'))}), throwsFormatException));
  test('unknown event does not become completion', () {
    final value = PandoraOperationsEvent.parse({...event(), 'type': 'model_says_done'});
    expect(value.label, 'Recorded Operations event'); expect(value.taskComplete, isFalse);
  });
  test('only native verification acceptance is task completion', () {
    expect(PandoraOperationsEvent.parse({...event(), 'type': 'inference_verified'}).taskComplete, isFalse);
    expect(PandoraOperationsEvent.parse({...event(), 'type': 'verification_accepted'}).taskComplete, isTrue);
  });
  for (final entry in <String, Object?>{'key': null, 'type': 'Bad Type', 'occurredAt': 'never', 'taskId': 3, 'receiptRef': List.empty()}.entries) {
    test('rejects invalid event ${entry.key}', () => expect(() => parse({...fixture(), 'events': [{...event(), entry.key: entry.value}]}), throwsFormatException));
  }
  test('HTTP reader uses fixed Vercel endpoint, current bearer and no redirects', () async {
    final client = TrackedClient((request) async {
      expect(request.url.toString(), 'https://mcpmaster.vercel.app/api/operations-inference?operation=events');
      expect(request.method, 'POST'); expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], 'Bearer fixture-session');
      expect(request.headers.containsKey('x-pandora-vercel-oidc'), isFalse);
      expect(jsonDecode(request.body)['organizationId'], canonicalOperationsOrganization);
      return http.Response(jsonEncode(fixture()), 200);
    });
    final reader = PandoraOperationsEventReader(organizationId: canonicalOperationsOrganization,
      readSession: () => const PandoraOperationsSession('user', 'fixture-session'), clientFactory: () => client, clock: () => now);
    expect((await reader.read(canonicalOperationsProject, '0')).events.length, 1); expect(client.closed, isTrue); reader.dispose();
  });
  test('HTTP reader denies a missing session before creating a client', () async {
    final reader = PandoraOperationsEventReader(organizationId: canonicalOperationsOrganization, readSession: () => null,
      clientFactory: () => throw StateError('unexpected network'));
    await expectLater(reader.read(canonicalOperationsProject, '0'), throwsA(isA<PandoraOperationsReadException>())); reader.dispose();
  });
  test('HTTP read cannot leak a response after account changes', () async {
    var session = const PandoraOperationsSession('first', 'first-fixture-session');
    final client = TrackedClient((request) async { session = const PandoraOperationsSession('second', 'second-fixture-session'); return http.Response(jsonEncode(fixture()), 200); });
    final reader = PandoraOperationsEventReader(organizationId: canonicalOperationsOrganization, readSession: () => session, clientFactory: () => client, clock: () => now);
    await expectLater(reader.read(canonicalOperationsProject, '0'), throwsA(isA<PandoraOperationsReadException>())); expect(client.closed, isTrue); reader.dispose();
  });
  for (final status in [401, 403, 500, 302]) {
    test('HTTP status$status never becomes event acceptance', () async {
      final client = TrackedClient((_) async => http.Response('{}', status));
      final reader = PandoraOperationsEventReader(organizationId: canonicalOperationsOrganization,
        readSession: () => const PandoraOperationsSession('user', 'fixture-session'), clientFactory: () => client);
      await expectLater(reader.read(canonicalOperationsProject, '0'), throwsA(isA<PandoraOperationsReadException>())); reader.dispose();
    });
  }
  test('body size is bounded even when response is otherwise successful', () async {
    final reader = PandoraOperationsEventReader(organizationId: canonicalOperationsOrganization,
      readSession: () => const PandoraOperationsSession('user', 'fixture-session'),
      clientFactory: () => TrackedClient((_) async => http.Response('x' * 262145, 200)));
    await expectLater(reader.read(canonicalOperationsProject, '0'), throwsA(isA<PandoraOperationsReadException>())); reader.dispose();
  });
  test('feed serializes refresh and retains provider cursor', () async {
    final done = Completer<PandoraOperationsPage>(); var calls = 0;
    final feed = PandoraOperationsFeed(readPage: (_, __) { calls++; return done.future; }, cancelRead: () {});
    feed.reset('session', canonicalOperationsProject); final first = feed.refresh(); await feed.refresh(); expect(calls, 1);
    done.complete(parse(fixture())); await first; expect(feed.cursor, '1'); expect(feed.loading, isFalse); feed.dispose();
  });
  test('signout fences late data and clears old events', () async {
    final done = Completer<PandoraOperationsPage>(); final feed = PandoraOperationsFeed(readPage: (_, __) => done.future, cancelRead: () {});
    feed.reset('first', canonicalOperationsProject); final pending = feed.refresh(); feed.reset(null, null); done.complete(parse(fixture())); await pending;
    expect(feed.events, isEmpty); expect(feed.cursor, '0'); expect(feed.loading, isFalse); feed.dispose();
  });
  test('pause cancels the live read without pretending task cancellation', () async {
    var cancelled = 0; final done = Completer<PandoraOperationsPage>();
    final feed = PandoraOperationsFeed(readPage: (_, __) => done.future, cancelRead: () { cancelled++; });
    feed.reset('first', canonicalOperationsProject); final pending = feed.refresh(); feed.pause(); done.complete(parse(fixture())); await pending;
    expect(cancelled, 2); expect(feed.events, isEmpty); expect(feed.error, isNull); feed.dispose();
  });
  test('access denial clears earlier records', () async {
    var calls = 0; final feed = PandoraOperationsFeed(readPage: (_, __) async {
      calls++; if (calls == 1) return parse(fixture()); throw const PandoraOperationsReadException(accessDenied: true);
    }, cancelRead: () {});
    feed.reset('user', canonicalOperationsProject); await feed.refresh(); await feed.refresh();
    expect(feed.events, isEmpty); expect(feed.error, contains('not available')); feed.dispose();
  });
  test('ordinary read failure retains earlier records and reports failure', () async {
    var calls = 0; final feed = PandoraOperationsFeed(readPage: (_, __) async {
      calls++; if (calls == 1) return parse(fixture()); throw const PandoraOperationsReadException();
    }, cancelRead: () {});
    feed.reset('user', canonicalOperationsProject); await feed.refresh(); await feed.refresh();
    expect(feed.events.length, 1); expect(feed.error, contains('could not be refreshed')); feed.dispose();
  });
  testWidgets('panel renders native evidence rather than fake execution or percentage', (tester) async {
    final feed = PandoraOperationsFeed(readPage: (_, __) async => parse(fixture()), cancelRead: () {});
    feed.reset('user', canonicalOperationsProject); await feed.refresh();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OperationsExecutionPanel(feed: feed))));
    expect(find.text('Tasks added'), findsOneWidget); expect(find.text('100%'), findsNothing);
    expect(find.textContaining('verification receipt'), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); feed.dispose();
  });
  testWidgets('empty accepted page is shown as empty, not as active workers', (tester) async {
    final feed = PandoraOperationsFeed(readPage: (_, __) async => parse({...fixture(), 'events': [], 'nextCursor': '0', 'highWatermark': '0'}), cancelRead: () {});
    feed.reset('user', canonicalOperationsProject); await feed.refresh();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OperationsExecutionPanel(feed: feed))));
    expect(find.text('No recorded execution events.'), findsOneWidget); expect(find.textContaining('worker active'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); feed.dispose();
  });
}
