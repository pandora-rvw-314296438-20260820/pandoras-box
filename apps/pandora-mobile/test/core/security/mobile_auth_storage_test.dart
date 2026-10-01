import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/security/mobile_auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements PandoraSecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('matches the pinned supabase_flutter legacy session key contract', () {
    expect(
      PandoraMobileAuthStorage.legacySessionKey(
        'https://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      'sb-jcyqixttuebxqqfkjonq-auth-token',
    );
  });

  test('uses a separate versioned secure session key', () {
    expect(
      PandoraMobileAuthStorage.secureSessionKey(
        'https://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      'pandora-jcyqixttuebxqqfkjonq-auth-session-v1',
    );
  });

  test('purges only the legacy persisted Supabase session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sb-jcyqixttuebxqqfkjonq-auth-token': 'legacy-session',
      'pandora.project.cursor': 42,
    });

    await PandoraMobileAuthStorage.clearLegacyPersistedSession(
      'https://jcyqixttuebxqqfkjonq.supabase.co',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('sb-jcyqixttuebxqqfkjonq-auth-token'),
      isFalse,
    );
    expect(preferences.getInt('pandora.project.cursor'), 42);
  });

  test('secure auth storage persists, restores, and removes a session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sb-jcyqixttuebxqqfkjonq-auth-token': 'legacy-session',
    });
    final secureStore = _MemorySecureStore();
    final storage = PandoraSecureAuthStorage(
      'https://jcyqixttuebxqqfkjonq.supabase.co',
      secureStore: secureStore,
    );

    await storage.initialize();
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('sb-jcyqixttuebxqqfkjonq-auth-token'),
      isFalse,
    );
    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('verified-session-json');
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'verified-session-json');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('empty session payload removes any prior secure session', () async {
    final secureStore = _MemorySecureStore();
    final storage = PandoraSecureAuthStorage(
      'https://jcyqixttuebxqqfkjonq.supabase.co',
      secureStore: secureStore,
    );

    await storage.persistSession('first-session');
    await storage.persistSession('   ');

    expect(await storage.hasAccessToken(), isFalse);
  });

  test('fails closed for non-HTTPS auth origins', () {
    expect(
      () => PandoraMobileAuthStorage.legacySessionKey(
        'http://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      throwsStateError,
    );
    expect(
      () => PandoraMobileAuthStorage.secureSessionKey(
        'http://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      throwsStateError,
    );
  });
}
