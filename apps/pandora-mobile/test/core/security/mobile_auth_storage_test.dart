import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pandora_mobile/core/security/mobile_auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('matches the pinned supabase_flutter v2 session key contract', () {
    expect(
      PandoraMobileAuthStorage.legacySessionKey(
        'https://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      'sb-jcyqixttuebxqqfkjonq-auth-token',
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

  test('fails closed for non-HTTPS auth origins', () {
    expect(
      () => PandoraMobileAuthStorage.legacySessionKey(
        'http://jcyqixttuebxqqfkjonq.supabase.co',
      ),
      throwsStateError,
    );
  });
}
