import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/security/mobile_auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('project-scoped session keys are deterministic and distinct', () {
    expect(
      PandoraMobileAuthStorage.secureSessionKey(
        'https://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      'pandora-jcyqixttuebxqqfkjonq-secure-auth-session-v1',
    );
    expect(
      PandoraMobileAuthStorage.legacySessionKey(
        'https://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      'sb-jcyqixttuebxqqfkjonq-auth-token',
    );
  });

  test('secure Supabase session storage persists and removes the session', () async {
    const key = 'pandora-test-secure-auth-session-v1';
    final storage = PandoraSecureSupabaseSessionStorage(
      persistSessionKey: key,
    );

    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);

    const session = '{"access_token":"token","refresh_token":"refresh"}';
    await storage.persistSession(session);

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), session);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('invalid Supabase URL fails closed', () {
    expect(
      () => PandoraMobileAuthStorage.secureSessionKey('http://not-secure'),
      throwsStateError,
    );
  });
}
