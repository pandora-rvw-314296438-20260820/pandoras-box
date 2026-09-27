import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';

void main() {
  test('Facebook web login returns to the canonical Pandora web origin', () {
    expect(
      pandoraFacebookRedirectUrl(
        isWeb: true,
        platform: TargetPlatform.linux,
      ),
      pandoraFacebookWebRedirectUrl,
    );
    expect(pandoraFacebookWebRedirectUrl, 'https://mcpmaster.vercel.app/');
  });

  test('Facebook Android login uses the Pandora app deep link', () {
    expect(
      pandoraFacebookRedirectUrl(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      pandoraFacebookAndroidRedirectUrl,
    );
    expect(
      pandoraFacebookAndroidRedirectUrl,
      'com.banataosystems.pandora://login-callback/',
    );
    expect(
      pandoraFacebookSignInSupported(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
  });

  test('Facebook client login does not claim unsupported native platforms', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        pandoraFacebookRedirectUrl(isWeb: false, platform: platform),
        isNull,
      );
      expect(
        pandoraFacebookSignInSupported(isWeb: false, platform: platform),
        isFalse,
      );
    }
  });
}
