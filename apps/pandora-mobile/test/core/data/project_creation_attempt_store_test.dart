import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/project_creation_attempt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('same intent reuses the pending creation key after store recreation',
      () async {
    const firstStore = SharedPreferencesProjectCreationAttemptStore();
    await firstStore.save(
      intent: 'Build a realtime system status page',
      idempotencyKey: 'pandora:create:test-key-1',
    );

    const afterRestart = SharedPreferencesProjectCreationAttemptStore();
    expect(
      await afterRestart.idempotencyKeyFor(
        'Build a realtime system status page',
      ),
      'pandora:create:test-key-1',
    );
  });

  test('different intent never inherits a pending creation key', () async {
    const store = SharedPreferencesProjectCreationAttemptStore();
    await store.save(
      intent: 'Build the first project',
      idempotencyKey: 'pandora:create:test-key-2',
    );

    expect(
      await store.idempotencyKeyFor('Build a different project'),
      isNull,
    );
  });

  test('acknowledged creation clears only the matching pending attempt',
      () async {
    const store = SharedPreferencesProjectCreationAttemptStore();
    await store.save(
      intent: 'Build a booking page',
      idempotencyKey: 'pandora:create:test-key-3',
    );

    await store.clear(
      intent: 'Build a booking page',
      idempotencyKey: 'pandora:create:test-key-3',
    );

    expect(await store.idempotencyKeyFor('Build a booking page'), isNull);
  });
}
