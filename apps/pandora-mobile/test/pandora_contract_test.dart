import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/pandora_config.dart';

void main() {
  test('canonical operator configuration is explicit', () {
    expect(
      PandoraConfig.supabaseUrl,
      'https://jcyqixttuebxqqfkjonq.supabase.co',
    );
    expect(
      PandoraConfig.ownerApiBaseUrl,
      'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-owner-api',
    );
    expect(
      PandoraConfig.organizationId,
      '2270b266-59da-4c39-bfd9-9f8d08352af0',
    );
    expect(PandoraConfig.supabasePublishableKey, startsWith('sb_publishable_'));
    expect(PandoraConfig.appVersion, '0.3.0-rc.3+6');
  });

  test('only the contract-proven owner endpoint is configured', () {
    expect(PandoraConfig.ownerApiBaseUrl, contains('pandora-owner-api'));
    expect(PandoraConfig.ownerApiEndpointLabel, 'Supabase owner API');
  });

  test('client defaults contain no deprecated operational owner', () {
    final combined = <String>[
      PandoraConfig.supabaseUrl,
      PandoraConfig.ownerApiBaseUrl,
      PandoraConfig.organizationId,
    ].join(' ');
    expect(combined.toLowerCase(), isNot(contains('mbanatao')));
  });
}
