import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/security/facebook_provider_settings.dart';

final _url = Uri.parse('https://jcyqixttuebxqqfkjonq.supabase.co');
const _publicKey = 'sb_publishable_fixture';

Future<bool> _read(String body, {int status = 200}) {
  return readFacebookProviderEnabled(
    client: MockClient((request) async {
      expect(request.url.toString(),
          'https://jcyqixttuebxqqfkjonq.supabase.co/auth/v1/settings');
      expect(request.headers['apikey'], _publicKey);
      return http.Response(body, status);
    }),
    supabaseUrl: _url,
    publishableKey: _publicKey,
  );
}

void main() {
  test('shows only when Auth settings explicitly enable Facebook', () async {
    expect(await _read('{"external":{"facebook":true}}'), isTrue);
    for (final body in <String>[
      '{"external":{"facebook":false}}',
      '{"external":{"facebook":"true"}}',
      '{"external":{}}',
      '{}',
      '<html>not settings</html>',
    ]) {
      expect(await _read(body), isFalse, reason: body);
    }
    expect(await _read('{"external":{"facebook":true}}', status: 503), isFalse);
  });

  test('settings outage and insecure configuration fail closed', () async {
    final failed = MockClient((_) async => throw Exception('offline'));
    expect(await readFacebookProviderEnabled(
      client: failed,
      supabaseUrl: _url,
      publishableKey: _publicKey,
    ), isFalse);
    expect(await readFacebookProviderEnabled(
      client: MockClient((_) async => http.Response(
        '{"external":{"facebook":true}}', 200,
      )),
      supabaseUrl: Uri.parse('http://untrusted.example'),
      publishableKey: _publicKey,
    ), isFalse);
  });
}
