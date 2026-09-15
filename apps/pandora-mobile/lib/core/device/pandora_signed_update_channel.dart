import 'package:flutter/services.dart';

Map<String, Object?> _updateMap(Object? raw, String label) {
  if (raw is! Map) throw FormatException('$label must be a map.');
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _updateString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

bool _updateBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

int _updateInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int || value <= 0) {
    throw FormatException('$key must be a positive integer.');
  }
  return value;
}

void _exactUpdateKeys(
  Map<String, Object?> map,
  Set<String> allowed,
  String label,
) {
  if (map.keys.toSet().length != allowed.length ||
      !map.keys.toSet().containsAll(allowed)) {
    throw FormatException('$label fields do not match the update contract.');
  }
}

void _rejectUpdateSecrets(Object? raw) {
  const forbiddenFragments = {
    'password',
    'token',
    'otp',
    'secret',
    'privatekey',
    'servicerolekey',
  };
  void walk(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String) {
          final key = (entry.key as String).toLowerCase();
          if (forbiddenFragments.any(key.contains)) {
            throw const FormatException(
              'Signed update evidence must not carry credentials or secrets.',
            );
          }
        }
        walk(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  walk(raw);
}

final RegExp _hex40 = RegExp(r'^[0-9a-f]{40}$');
final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

String _updateHex(Map<String, Object?> map, String key, RegExp pattern) {
  final value = _updateString(map, key).toLowerCase();
  if (!pattern.hasMatch(value)) throw FormatException('$key is invalid.');
  return value;
}

class PandoraSignedUpdatePolicy {
  const PandoraSignedUpdatePolicy({
    required this.installRoute,
    required this.deviceOwnerProvisioned,
    required this.userConfirmationRequired,
    required this.productionVerificationAvailable,
  });

  final String installRoute;
  final bool deviceOwnerProvisioned;
  final bool userConfirmationRequired;
  final bool productionVerificationAvailable;

  factory PandoraSignedUpdatePolicy.fromMap(Object? raw) {
    final map = _updateMap(raw, 'signed update policy');
    _rejectUpdateSecrets(map);
    _exactUpdateKeys(
        map,
        const {
          'schemaVersion',
          'platform',
          'packageName',
          'artifactStagingScope',
          'manifestSignatureAuthority',
          'signerRotationPolicy',
          'sourceShaAuthority',
          'sourceTreeAuthority',
          'rollbackStrategy',
          'requiresCandidateAndRecovery',
          'requestInstallPackagesAllowed',
          'requestInstallPackagesDeclared',
          'unknownSourcesInstallAllowed',
          'directInstallerExposed',
          'deviceOwnerProvisioned',
          'installRoute',
          'userConfirmationRequired',
          'productionVerificationAvailable',
          'physicalUpdateVerified',
          'physicalRollbackVerified',
        },
        'signed update policy');
    if (_updateString(map, 'schemaVersion') != '1.0.0' ||
        _updateString(map, 'platform') != 'android' ||
        _updateString(map, 'packageName') !=
            'com.banataosystems.pandora_mobile') {
      throw const FormatException('Unsupported signed update policy identity.');
    }
    if (_updateString(map, 'artifactStagingScope') != 'app_private_only' ||
        _updateString(map, 'manifestSignatureAuthority') !=
            'installed_app_signer' ||
        _updateString(map, 'signerRotationPolicy') !=
            'exact_current_signer_v1' ||
        _updateString(map, 'sourceShaAuthority') != 'apk_embedded_revision' ||
        _updateString(map, 'sourceTreeAuthority') != 'signed_manifest' ||
        _updateString(map, 'rollbackStrategy') !=
            'forward_version_signed_recovery') {
      throw const FormatException('Signed update trust policy was weakened.');
    }
    if (!_updateBool(map, 'requiresCandidateAndRecovery') ||
        _updateBool(map, 'requestInstallPackagesAllowed') ||
        _updateBool(map, 'requestInstallPackagesDeclared') ||
        _updateBool(map, 'unknownSourcesInstallAllowed') ||
        _updateBool(map, 'directInstallerExposed') ||
        _updateBool(map, 'physicalUpdateVerified') ||
        _updateBool(map, 'physicalRollbackVerified')) {
      throw const FormatException(
        'Signed update install boundary was weakened.',
      );
    }
    final deviceOwner = _updateBool(map, 'deviceOwnerProvisioned');
    final route = _updateString(map, 'installRoute');
    if (route != 'managed_device_owner_distribution' &&
        route != 'trusted_store_or_user_installer') {
      throw const FormatException('Unsupported signed update install route.');
    }
    final confirmation = _updateBool(map, 'userConfirmationRequired');
    if (confirmation == deviceOwner) {
      throw const FormatException(
        'Update confirmation authority is inconsistent.',
      );
    }
    return PandoraSignedUpdatePolicy(
      installRoute: route,
      deviceOwnerProvisioned: deviceOwner,
      userConfirmationRequired: confirmation,
      productionVerificationAvailable:
          _updateBool(map, 'productionVerificationAvailable'),
    );
  }
}

class PandoraVerifiedUpdateArtifact {
  const PandoraVerifiedUpdateArtifact({
    required this.apkSha256,
    required this.sourceSha,
    required this.sourceTree,
    required this.versionCode,
    required this.versionName,
    required this.signerSha256,
    this.rollbackTargetSourceSha,
  });

  final String apkSha256;
  final String sourceSha;
  final String sourceTree;
  final int versionCode;
  final String versionName;
  final String signerSha256;
  final String? rollbackTargetSourceSha;

  factory PandoraVerifiedUpdateArtifact.fromMap(
    Object? raw, {
    required bool recovery,
  }) {
    final map = _updateMap(
      raw,
      recovery ? 'recovery artifact' : 'candidate artifact',
    );
    _rejectUpdateSecrets(map);
    final allowed = <String>{
      'staging',
      'apkSha256',
      'sourceSha',
      'sourceTree',
      'versionCode',
      'versionName',
      'signerSha256',
      'hashVerified',
      'packageVerified',
      'versionVerified',
      'sourceShaVerified',
      'signerVerified',
      if (recovery) 'rollbackTargetSourceSha',
    };
    _exactUpdateKeys(
      map,
      allowed,
      recovery ? 'recovery artifact' : 'candidate artifact',
    );
    if (_updateString(map, 'staging') != 'app_private_verified') {
      throw const FormatException(
        'Update artifact escaped app-private staging.',
      );
    }
    for (final key in [
      'hashVerified',
      'packageVerified',
      'versionVerified',
      'sourceShaVerified',
      'signerVerified',
    ]) {
      if (!_updateBool(map, key)) {
        throw FormatException('$key must be verified.');
      }
    }
    return PandoraVerifiedUpdateArtifact(
      apkSha256: _updateHex(map, 'apkSha256', _hex64),
      sourceSha: _updateHex(map, 'sourceSha', _hex40),
      sourceTree: _updateHex(map, 'sourceTree', _hex40),
      versionCode: _updateInt(map, 'versionCode'),
      versionName: _updateString(map, 'versionName'),
      signerSha256: _updateHex(map, 'signerSha256', _hex64),
      rollbackTargetSourceSha:
          recovery ? _updateHex(map, 'rollbackTargetSourceSha', _hex40) : null,
    );
  }
}

class PandoraVerifiedUpdateBundle {
  const PandoraVerifiedUpdateBundle({
    required this.channel,
    required this.currentVersionCode,
    required this.candidate,
    required this.recovery,
    required this.installRoute,
    required this.userConfirmationRequired,
  });

  final String channel;
  final int currentVersionCode;
  final PandoraVerifiedUpdateArtifact candidate;
  final PandoraVerifiedUpdateArtifact recovery;
  final String installRoute;
  final bool userConfirmationRequired;

  factory PandoraVerifiedUpdateBundle.fromMap(Object? raw) {
    final map = _updateMap(raw, 'verified update bundle');
    _rejectUpdateSecrets(map);
    _exactUpdateKeys(
        map,
        const {
          'schemaVersion',
          'status',
          'channel',
          'packageName',
          'productionRelease',
          'manifestSignatureVerified',
          'installedSignerVerified',
          'candidateVerified',
          'recoveryVerified',
          'sourceShaAuthority',
          'sourceTreeAuthority',
          'rollbackStrategy',
          'currentVersionCode',
          'candidate',
          'recovery',
          'installRoute',
          'userConfirmationRequired',
          'requestInstallPackagesAllowed',
          'directInstallerExposed',
          'installExecuted',
          'physicalUpdateVerified',
          'physicalRollbackVerified',
        },
        'verified update bundle');
    if (_updateString(map, 'schemaVersion') != '1.0.0' ||
        _updateString(map, 'status') != 'verified' ||
        _updateString(map, 'packageName') !=
            'com.banataosystems.pandora_mobile' ||
        !_updateBool(map, 'productionRelease')) {
      throw const FormatException(
        'Update bundle is not a verified production release.',
      );
    }
    for (final key in [
      'manifestSignatureVerified',
      'installedSignerVerified',
      'candidateVerified',
      'recoveryVerified',
    ]) {
      if (!_updateBool(map, key)) throw FormatException('$key must be true.');
    }
    if (_updateBool(map, 'requestInstallPackagesAllowed') ||
        _updateBool(map, 'directInstallerExposed') ||
        _updateBool(map, 'installExecuted') ||
        _updateBool(map, 'physicalUpdateVerified') ||
        _updateBool(map, 'physicalRollbackVerified') ||
        _updateString(map, 'sourceShaAuthority') != 'apk_embedded_revision' ||
        _updateString(map, 'sourceTreeAuthority') != 'signed_manifest' ||
        _updateString(map, 'rollbackStrategy') !=
            'forward_version_signed_recovery') {
      throw const FormatException('Verified update boundary was weakened.');
    }
    final channel = _updateString(map, 'channel');
    if (channel != 'stable' && channel != 'enterprise') {
      throw const FormatException('Unsupported verified update channel.');
    }
    final current = _updateInt(map, 'currentVersionCode');
    final candidate = PandoraVerifiedUpdateArtifact.fromMap(
      map['candidate'],
      recovery: false,
    );
    final recovery = PandoraVerifiedUpdateArtifact.fromMap(
      map['recovery'],
      recovery: true,
    );
    if (candidate.versionCode <= current ||
        recovery.versionCode <= candidate.versionCode ||
        candidate.signerSha256 != recovery.signerSha256) {
      throw const FormatException(
        'Update/rollback version or signer chain is invalid.',
      );
    }
    final route = _updateString(map, 'installRoute');
    if (route != 'managed_device_owner_distribution' &&
        route != 'trusted_store_or_user_installer') {
      throw const FormatException('Unsupported verified install route.');
    }
    return PandoraVerifiedUpdateBundle(
      channel: channel,
      currentVersionCode: current,
      candidate: candidate,
      recovery: recovery,
      installRoute: route,
      userConfirmationRequired: _updateBool(map, 'userConfirmationRequired'),
    );
  }
}

class PandoraSignedUpdateRuntime {
  PandoraSignedUpdateRuntime({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PandoraSignedUpdatePolicy> getPolicy() async {
    final raw = await _channel.invokeMethod<Object?>('getSignedUpdatePolicy');
    return PandoraSignedUpdatePolicy.fromMap(raw);
  }

  Future<PandoraVerifiedUpdateBundle> verifyBundle({
    required String manifestPayload,
    required String manifestSignatureBase64,
    required String candidatePath,
    required String recoveryPath,
  }) async {
    if (manifestPayload.isEmpty || manifestPayload.length > 64 * 1024) {
      throw const FormatException('Signed update manifest payload is invalid.');
    }
    if (manifestSignatureBase64.isEmpty ||
        manifestSignatureBase64.length > 16 * 1024 ||
        candidatePath.isEmpty ||
        recoveryPath.isEmpty) {
      throw const FormatException(
        'Signed update verification input is invalid.',
      );
    }
    final raw = await _channel.invokeMethod<Object?>(
      'verifySignedUpdateBundle',
      <String, Object?>{
        'manifestPayload': manifestPayload,
        'manifestSignatureBase64': manifestSignatureBase64,
        'candidatePath': candidatePath,
        'recoveryPath': recoveryPath,
      },
    );
    return PandoraVerifiedUpdateBundle.fromMap(raw);
  }
}
