import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_signed_update_channel.dart';

const _shaA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _shaC = 'cccccccccccccccccccccccccccccccccccccccc';
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hashC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

Map<String, Object?> _policy({
  bool requestInstallPackagesDeclared = false,
  bool verificationAvailable = true,
  bool deviceOwner = false,
}) =>
    {
      'schemaVersion': '1.0.0',
      'platform': 'android',
      'packageName': 'com.banataosystems.pandora_mobile',
      'artifactStagingScope': 'app_private_only',
      'manifestSignatureAuthority': 'installed_app_signer',
      'signerRotationPolicy': 'exact_current_signer_v1',
      'sourceShaAuthority': 'apk_embedded_revision',
      'sourceTreeAuthority': 'signed_manifest',
      'rollbackStrategy': 'forward_version_signed_recovery',
      'requiresCandidateAndRecovery': true,
      'requestInstallPackagesAllowed': false,
      'requestInstallPackagesDeclared': requestInstallPackagesDeclared,
      'unknownSourcesInstallAllowed': false,
      'directInstallerExposed': false,
      'deviceOwnerProvisioned': deviceOwner,
      'installRoute': deviceOwner
          ? 'managed_device_owner_distribution'
          : 'trusted_store_or_user_installer',
      'userConfirmationRequired': !deviceOwner,
      'productionVerificationAvailable': verificationAvailable,
      'physicalUpdateVerified': false,
      'physicalRollbackVerified': false,
    };

Map<String, Object?> _artifact({
  required int versionCode,
  required String versionName,
  required String apkSha,
  required String sourceSha,
  required String sourceTree,
  bool recovery = false,
}) =>
    {
      'staging': 'app_private_verified',
      'apkSha256': apkSha,
      'sourceSha': sourceSha,
      'sourceTree': sourceTree,
      'versionCode': versionCode,
      'versionName': versionName,
      'signerSha256': _hashC,
      'hashVerified': true,
      'packageVerified': true,
      'versionVerified': true,
      'sourceShaVerified': true,
      'signerVerified': true,
      if (recovery) 'rollbackTargetSourceSha': _shaA,
    };

Map<String, Object?> _bundle({
  int currentVersionCode = 11,
  int candidateVersionCode = 12,
  int recoveryVersionCode = 13,
}) =>
    {
      'schemaVersion': '1.0.0',
      'status': 'verified',
      'channel': 'enterprise',
      'packageName': 'com.banataosystems.pandora_mobile',
      'productionRelease': true,
      'manifestSignatureVerified': true,
      'installedSignerVerified': true,
      'candidateVerified': true,
      'recoveryVerified': true,
      'sourceShaAuthority': 'apk_embedded_revision',
      'sourceTreeAuthority': 'signed_manifest',
      'rollbackStrategy': 'forward_version_signed_recovery',
      'currentVersionCode': currentVersionCode,
      'candidate': _artifact(
        versionCode: candidateVersionCode,
        versionName: '0.4.0-rc.5',
        apkSha: _hashA,
        sourceSha: _shaB,
        sourceTree: _shaC,
      ),
      'recovery': _artifact(
        versionCode: recoveryVersionCode,
        versionName: '0.4.0-rc.6-recovery',
        apkSha: _hashB,
        sourceSha: _shaC,
        sourceTree: _shaB,
        recovery: true,
      ),
      'installRoute': 'trusted_store_or_user_installer',
      'userConfirmationRequired': true,
      'requestInstallPackagesAllowed': false,
      'directInstallerExposed': false,
      'installExecuted': false,
      'physicalUpdateVerified': false,
      'physicalRollbackVerified': false,
    };

void main() {
  test('accepts fail-closed signed update policy', () {
    final policy = PandoraSignedUpdatePolicy.fromMap(_policy());
    expect(policy.installRoute, 'trusted_store_or_user_installer');
    expect(policy.userConfirmationRequired, isTrue);
    expect(policy.productionVerificationAvailable, isTrue);
  });

  test('rejects unknown-source permission declaration', () {
    expect(
      () => PandoraSignedUpdatePolicy.fromMap(
        _policy(requestInstallPackagesDeclared: true),
      ),
      throwsFormatException,
    );
  });

  test('accepts verified forward-version recovery chain', () {
    final bundle = PandoraVerifiedUpdateBundle.fromMap(_bundle());
    expect(bundle.currentVersionCode, 11);
    expect(bundle.candidate.versionCode, 12);
    expect(bundle.recovery.versionCode, 13);
    expect(bundle.recovery.rollbackTargetSourceSha, _shaA);
  });

  test('rejects Android downgrade rollback', () {
    expect(
      () => PandoraVerifiedUpdateBundle.fromMap(
        _bundle(candidateVersionCode: 12, recoveryVersionCode: 10),
      ),
      throwsFormatException,
    );
  });

  test('rejects unverified artifact evidence', () {
    final invalid = _bundle();
    final candidate = Map<String, Object?>.from(invalid['candidate']! as Map)
      ..['sourceShaVerified'] = false;
    invalid['candidate'] = candidate;
    expect(
      () => PandoraVerifiedUpdateBundle.fromMap(invalid),
      throwsFormatException,
    );
  });

  test('rejects credentials or secrets in update evidence', () {
    final invalid = _bundle()..['accessToken'] = 'forbidden';
    expect(
      () => PandoraVerifiedUpdateBundle.fromMap(invalid),
      throwsFormatException,
    );
  });

  test('rejects fabricated physical update or rollback truth', () {
    for (final key in [
      'installExecuted',
      'physicalUpdateVerified',
      'physicalRollbackVerified',
    ]) {
      final invalid = _bundle()..[key] = true;
      expect(
        () => PandoraVerifiedUpdateBundle.fromMap(invalid),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('requires exact signed-manifest source tree authority', () {
    final invalid = _bundle()..['sourceTreeAuthority'] = 'client_claim';
    expect(
      () => PandoraVerifiedUpdateBundle.fromMap(invalid),
      throwsFormatException,
    );
  });
}
