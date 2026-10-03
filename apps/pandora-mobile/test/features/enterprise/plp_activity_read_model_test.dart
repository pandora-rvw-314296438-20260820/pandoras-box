import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_activity_read_model.dart';

void main() {
  test('real staff and ordinary product descriptions remain production history', () {
    const production = <String, Object?>{
      'title': 'Synthetic pillows requested',
      'summary': 'Replace synthetic pillows before arrival',
      'actor': 'QA manager',
      'sourceLabel': 'Mockingbird PMS',
      'isTestData': false,
    };
    expect(plpRecordIsTestData(production), isFalse);
    expect(plpProductionActivityRecords([production]).single, production);
  });

  test('root and nested test flags cannot appear in production history', () {
    for (final flag in const [
      'isMock', 'is_mock', 'isTestData', 'is_test_data',
      'isTest', 'is_test', 'synthetic', 'mock', 'testOnly', 'test_only',
    ]) {
      for (final value in <Object>[true, 'true', 'TRUE', '1', 'yes']) {
        expect(plpRecordIsTestData({flag: value}), isTrue);
        expect(plpRecordIsTestData({'metadata': {flag: value}}), isTrue);
        expect(plpRecordIsTestData({'provenance': {flag: value}}), isTrue);
      }
    }
  });

  test('legacy test provenance is excluded without substring false positives', () {
    for (final source in const [
      'qa_mock_seed_20260920', 'mock', 'synthetic-run',
      'fixture:acceptance', 'test/run', 'demo seed',
    ]) {
      expect(plpRecordIsTestData({'sourceLabel': source}), isTrue);
    }
    expect(plpRecordIsTestData({'note': '[MOCK QA] Completed task'}), isTrue);
    expect(plpRecordIsTestData({'bookingReference': 'MOCK-PLP-001'}), isTrue);
    expect(plpRecordIsTestData({'booking_reference': 'mock-plp-001'}), isTrue);
    expect(plpRecordIsTestData({
      'provenance': {'sourceType': 'qa_mock'},
    }), isTrue);
    expect(plpRecordIsTestData({'sourceLabel': 'Mockingbird PMS'}), isFalse);
    expect(plpRecordIsTestData({'sourceLabel': 'Synthetics supplier'}), isFalse);
  });

  test('activity reads are lazy, coalesced, and shared without duplicate queries', () async {
    var calls = 0;
    final pending = Completer<Map<String, Object?>>();
    final model = PlpActivityReadModel(loader: () { calls++; return pending.future; });
    addTearDown(model.dispose);
    expect(calls, 0);
    final first = model.load();
    final second = model.load();
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    pending.complete({'items': [
      {'title': 'Production event', 'isMock': false},
      {'title': '[MOCK QA] Seed', 'isMock': true},
      {'title': 'Synthetic completed task', 'sourceLabel': 'qa_mock'},
    ]});
    await first;
    expect(model.items.single['title'], 'Production event');
    expect(identical(await model.load(), model.data), isTrue);
    expect(calls, 1);
  });

  test('failed and malformed refreshes retain evidence instead of inventing zero', () async {
    var calls = 0;
    final model = PlpActivityReadModel(loader: () async {
      calls++;
      if (calls == 1) return {'items': [{'title': 'Verified event'}]};
      if (calls == 2) throw StateError('Source unavailable');
      return {'source': 'missing items'};
    });
    addTearDown(model.dispose);
    await model.load();
    final previous = model.data;
    await expectLater(model.load(force: true), throwsStateError);
    expect(identical(model.data, previous), isTrue);
    expect(model.error, isNotNull);
    await expectLater(model.load(force: true), throwsStateError);
    expect(identical(model.data, previous), isTrue);
    expect(model.loading, isFalse);
  });

  test('a resolved empty list is distinct from not loaded', () async {
    final model = PlpActivityReadModel(loader: () async => {'items': []});
    addTearDown(model.dispose);
    expect(model.data, isNull);
    await model.load();
    expect(model.data, isNotNull);
    expect(model.items, isEmpty);
    expect(model.error, isNull);
  });

  test('disposed activity model never notifies or starts another request', () async {
    final pending = Completer<Map<String, Object?>>();
    final model = PlpActivityReadModel(loader: () => pending.future);
    final read = model.load();
    model.dispose();
    pending.complete({'items': []});
    await read;
    await expectLater(model.load(), throwsStateError);
  });
}
