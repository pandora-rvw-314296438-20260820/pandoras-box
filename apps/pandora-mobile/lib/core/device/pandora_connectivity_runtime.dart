import 'package:flutter/services.dart';

Map<String, Object?> _connectivityMap(Object? raw, String label) {
  if (raw is! Map) {
    throw FormatException('$label must be a map.');
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

bool _connectivityBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

int _connectivityInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}

String _connectivityString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

void _rejectConnectivityIdentifiers(Object? value) {
  const forbidden = {
    'androidId', 'serial', 'ssid', 'bssid', 'ipAddress', 'ipAddresses',
    'dns', 'dnsServers', 'macAddress', 'imei', 'imsi',
  };
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is String && forbidden.contains(entry.key)) {
        throw const FormatException(
          'Connectivity state must not contain device or network identifiers.',
        );
      }
      _rejectConnectivityIdentifiers(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _rejectConnectivityIdentifiers(item);
    }
  }
}

enum PandoraConnectivitySettingsTarget {
  internet,
  wifi,
  mobile,
  bluetooth,
  usb,
}

class PandoraConnectivityState {
  const PandoraConnectivityState({
    required this.capturedAtElapsedRealtimeMs,
    required this.connected,
    required this.internetCapable,
    required this.validated,
    required this.captivePortal,
    required this.metered,
    required this.transports,
  });

  final int capturedAtElapsedRealtimeMs;
  final bool connected;
  final bool internetCapable;
  final bool validated;
  final bool captivePortal;
  final bool metered;
  final Map<String, bool> transports;

  factory PandoraConnectivityState.fromMap(Object? raw) {
    final map = _connectivityMap(raw, 'connectivity state');
    _rejectConnectivityIdentifiers(map);
    if (_connectivityString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported connectivity state schema.');
    }
    if (!_connectivityBool(map, 'userControlOnly') ||
        _connectivityBool(map, 'silentMutationAllowed') ||
        _connectivityBool(map, 'normalOperationRequiresDesktop') ||
        _connectivityBool(map, 'rootRequired')) {
      throw const FormatException(
        'Connectivity state violates Pandora connectivity safety policy.',
      );
    }
    final rawTransports = _connectivityMap(map['transports'], 'transports');
    const requiredTransports = {
      'wifi', 'cellular', 'bluetooth', 'ethernet', 'vpn', 'usb',
    };
    final transports = <String, bool>{};
    for (final key in requiredTransports) {
      transports[key] = _connectivityBool(rawTransports, key);
    }
    return PandoraConnectivityState(
      capturedAtElapsedRealtimeMs:
          _connectivityInt(map, 'capturedAtElapsedRealtimeMs'),
      connected: _connectivityBool(map, 'connected'),
      internetCapable: _connectivityBool(map, 'internetCapable'),
      validated: _connectivityBool(map, 'validated'),
      captivePortal: _connectivityBool(map, 'captivePortal'),
      metered: _connectivityBool(map, 'metered'),
      transports: Map.unmodifiable(transports),
    );
  }
}

class PandoraConnectivitySettingsResult {
  const PandoraConnectivitySettingsResult({
    required this.target,
    required this.opened,
  });

  final PandoraConnectivitySettingsTarget target;
  final bool opened;

  factory PandoraConnectivitySettingsResult.fromMap(Object? raw) {
    final map = _connectivityMap(raw, 'connectivity settings result');
    if (_connectivityString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported connectivity settings schema.');
    }
    final targetName = _connectivityString(map, 'target');
    PandoraConnectivitySettingsTarget? target;
    for (final candidate in PandoraConnectivitySettingsTarget.values) {
      if (candidate.name == targetName) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      throw const FormatException('Unsupported connectivity settings target.');
    }
    if (!_connectivityBool(map, 'userActionRequired') ||
        _connectivityBool(map, 'silentMutation')) {
      throw const FormatException(
        'Connectivity settings must remain explicitly user-controlled.',
      );
    }
    return PandoraConnectivitySettingsResult(
      target: target,
      opened: _connectivityBool(map, 'opened'),
    );
  }
}

abstract interface class PandoraConnectivityRuntime {
  Future<PandoraConnectivityState> getState();

  Future<PandoraConnectivitySettingsResult> openSettings(
    PandoraConnectivitySettingsTarget target,
  );
}

class MethodChannelPandoraConnectivityRuntime
    implements PandoraConnectivityRuntime {
  MethodChannelPandoraConnectivityRuntime({
    MethodChannel channel = const MethodChannel('pandora/connectivity'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<PandoraConnectivityState> getState() async {
    final raw = await _channel.invokeMethod<Object?>('getConnectivityState');
    return PandoraConnectivityState.fromMap(raw);
  }

  @override
  Future<PandoraConnectivitySettingsResult> openSettings(
    PandoraConnectivitySettingsTarget target,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'openConnectivitySettings',
      <String, Object?>{'target': target.name},
    );
    return PandoraConnectivitySettingsResult.fromMap(raw);
  }
}
