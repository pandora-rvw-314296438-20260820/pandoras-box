import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local/pandora_local_data_policy.dart';
import 'package:pandora_mobile/core/local/pandora_local_state_cache.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_stub.dart';

String _key(String identity) =>
    'thread_${sha256.convert(utf8.encode(identity)).toString().substring(0, 32)}';

void main() {
  final now = DateTime.utc(2026, 10, 3, 15);

  test(
      'explicit thread cache records its identity and never mirrors local-chat',
      () async {
    final backend = MemoryPandoraLocalStore(clock: () => now);
    final cache = PandoraLocalStateCache(backend, clock: () => now);
    await cache.cacheRecentConversation(
      threadIdentity: 'thread-one',
      messages: const [
        {'id': 'message-one', 'role': 'user', 'text': 'Hi'},
      ],
    );
    final record = await backend.getCache(
      PandoraLocalNamespace.recentConversation,
      _key('thread-one'),
    );
    expect(jsonDecode(record!.payloadJson)['threadIdentity'], 'thread-one');
    expect(
      await backend.getCache(
        PandoraLocalNamespace.recentConversation,
        _key('local-chat'),
      ),
      isNull,
    );
    expect(
      await cache.loadRecentConversation(threadIdentity: 'thread-one'),
      const [
        {'id': 'message-one', 'role': 'user', 'text': 'Hi'},
      ],
    );
  });

  test('unknown local-chat identity cannot create a restorable conversation',
      () async {
    final backend = MemoryPandoraLocalStore(clock: () => now);
    final cache = PandoraLocalStateCache(backend, clock: () => now);
    await cache.cacheRecentConversation(
      threadIdentity: 'local-chat',
      messages: const [
        {'role': 'user', 'text': 'Hi'},
      ],
    );
    expect(
      await backend.getCache(
        PandoraLocalNamespace.recentConversation,
        _key('local-chat'),
      ),
      isNull,
    );
  });

  test('legacy active alias fails closed without deleting explicit history',
      () async {
    final backend = MemoryPandoraLocalStore(clock: () => now);
    final cache = PandoraLocalStateCache(backend, clock: () => now);
    const legacy = {
      'messages': [
        {'role': 'user', 'text': 'A prior conversation'},
      ],
    };
    for (final identity in ['local-chat', 'thread-one']) {
      await backend.putCache(
        namespace: PandoraLocalNamespace.recentConversation,
        key: _key(identity),
        payload: legacy,
        expiresAt: now.add(const Duration(days: 1)),
      );
    }
    expect(await cache.loadRecentConversation(threadIdentity: 'local-chat'),
        isEmpty);
    expect(
      await backend.getCache(
        PandoraLocalNamespace.recentConversation,
        _key('local-chat'),
      ),
      isNull,
    );
    expect(await cache.loadRecentConversation(threadIdentity: 'thread-one'),
        hasLength(1));
  });

  test('mismatched stored identity cannot paint the requested thread',
      () async {
    final backend = MemoryPandoraLocalStore(clock: () => now);
    final cache = PandoraLocalStateCache(backend, clock: () => now);
    await backend.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: _key('thread-one'),
      payload: const {
        'threadIdentity': 'thread-two',
        'messages': [
          {'role': 'user', 'text': 'Wrong thread'},
        ],
      },
      expiresAt: now.add(const Duration(days: 1)),
    );
    expect(await cache.loadRecentConversation(threadIdentity: 'thread-one'),
        isEmpty);
  });

  test('explicit cache remains bounded and expires after seven days', () async {
    var clock = now;
    final backend = MemoryPandoraLocalStore(clock: () => clock);
    final cache = PandoraLocalStateCache(backend, clock: () => clock);
    await cache.cacheRecentConversation(
      threadIdentity: 'thread-one',
      messages: List.generate(
          40,
          (i) =>
              <String, Object?>{'id': 'row-$i', 'role': 'user', 'text': '$i'}),
    );
    final restored =
        await cache.loadRecentConversation(threadIdentity: 'thread-one');
    expect(restored, hasLength(30));
    expect(restored.first['id'], 'row-10');
    expect(restored.last['id'], 'row-39');
    clock = now.add(const Duration(days: 7));
    expect(await cache.loadRecentConversation(threadIdentity: 'thread-one'),
        isEmpty);
  });
}
