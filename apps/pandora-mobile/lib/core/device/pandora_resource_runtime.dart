import 'package:flutter/services.dart';

Map<String, Object?> _resourceMap(Object? raw, String label) {
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

String _resourceString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _resourceBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

int _resourceInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

num _resourceNum(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return value;
}

Map<String, Object?> _resourceSection(Map<String, Object?> map, String key) {
  return Map.unmodifiable(_resourceMap(map[key], key));
}

void _rejectIdentifiers(Map<String, Object?> map) {
  const forbidden = {
    'androidId',
    'serial',
    'ssid',
    'bssid',
    'ipAddress',
    'ipAddresses',
    'dns',
    'dnsServers',
    'macAddress',
    'imei',
    'imsi',
  };
  void walk(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String && forbidden.contains(entry.key)) {
          throw FormatException(
            'Resource telemetry must not contain device or network identifiers.',
          );
        }
        walk(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  walk(map);
}

void _validateHeadroom(Map<String, Object?> section, String key) {
  final value = section[key];
  if (value == null) return;
  if (value is! num || !value.isFinite || value < 0 || value > 100) {
    throw FormatException('$key must be null or a percentage from 0 to 100.');
  }
}

class PandoraResourceSnapshot {
  const PandoraResourceSnapshot({
    required this.schemaVersion,
    required this.capturedAtElapsedRealtimeMs,
    required this.cpu,
    required this.gpu,
    required this.memory,
    required this.storage,
    required this.battery,
    required this.thermal,
    required this.process,
    required this.network,
  });

  final String schemaVersion;
  final int capturedAtElapsedRealtimeMs;
  final Map<String, Object?> cpu;
  final Map<String, Object?> gpu;
  final Map<String, Object?> memory;
  final Map<String, Object?> storage;
  final Map<String, Object?> battery;
  final Map<String, Object?> thermal;
  final Map<String, Object?> process;
  final Map<String, Object?> network;

  factory PandoraResourceSnapshot.fromMap(Object? raw) {
    final map = _resourceMap(raw, 'resource snapshot');
    if (_resourceString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported resource snapshot schema.');
    }
    if (_resourceBool(map, 'normalOperationRequiresDesktop') ||
        _resourceBool(map, 'rootRequired') ||
        _resourceBool(map, 'arbitraryCommandAccepted')) {
      throw const FormatException(
        'Resource telemetry must remain phone-only, rootless and command-free.',
      );
    }
    _rejectIdentifiers(map);

    final cpu = _resourceSection(map, 'cpu');
    final gpu = _resourceSection(map, 'gpu');
    _validateHeadroom(cpu, 'headroomPercent');
    _validateHeadroom(gpu, 'headroomPercent');

    final network = _resourceSection(map, 'network');
    if (network.containsKey('downstreamKbps') ||
        network.containsKey('upstreamKbps')) {
      throw const FormatException(
        'Network bandwidth fields must be explicitly labeled as estimates.',
      );
    }
    for (final key in ['estimatedDownstreamKbps', 'estimatedUpstreamKbps']) {
      final value = network[key];
      if (value != null && (value is! num || !value.isFinite || value < 0)) {
        throw FormatException('$key must be null or a non-negative estimate.');
      }
    }

    final capturedAt = _resourceInt(map, 'capturedAtElapsedRealtimeMs');
    if (capturedAt < 0) {
      throw const FormatException(
        'capturedAtElapsedRealtimeMs must not be negative.',
      );
    }

    return PandoraResourceSnapshot(
      schemaVersion: '1.0.0',
      capturedAtElapsedRealtimeMs: capturedAt,
      cpu: cpu,
      gpu: gpu,
      memory: _resourceSection(map, 'memory'),
      storage: _resourceSection(map, 'storage'),
      battery: _resourceSection(map, 'battery'),
      thermal: _resourceSection(map, 'thermal'),
      process: _resourceSection(map, 'process'),
      network: network,
    );
  }
}

class PandoraResourceBenchmarkRequest {
  const PandoraResourceBenchmarkRequest({this.durationMs = 40});

  static const int minDurationMs = 25;
  static const int maxDurationMs = 100;

  final int durationMs;

  Map<String, Object?> toMap() {
    if (durationMs < minDurationMs || durationMs > maxDurationMs) {
      throw RangeError.range(
        durationMs,
        minDurationMs,
        maxDurationMs,
        'durationMs',
      );
    }
    return <String, Object?>{'durationMs': durationMs};
  }
}

class PandoraResourceBenchmarkResult {
  const PandoraResourceBenchmarkResult({
    required this.schemaVersion,
    required this.kind,
    required this.requestedDurationMs,
    required this.wallDurationMs,
    required this.cpuTimeMs,
    required this.cpuTimeScope,
    required this.iterations,
    required this.checksum,
    required this.thermalStatusBefore,
    required this.thermalStatusAfter,
  });

  final String schemaVersion;
  final String kind;
  final int requestedDurationMs;
  final num wallDurationMs;
  final int cpuTimeMs;
  final String cpuTimeScope;
  final int iterations;
  final int checksum;
  final String thermalStatusBefore;
  final String thermalStatusAfter;

  factory PandoraResourceBenchmarkResult.fromMap(Object? raw) {
    final map = _resourceMap(raw, 'resource benchmark');
    if (_resourceString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported resource benchmark schema.');
    }
    final kind = _resourceString(map, 'kind');
    if (kind != 'cpu_integer_mix_v1') {
      throw FormatException('Unsupported resource benchmark kind: $kind');
    }
    if (_resourceBool(map, 'persistentMutation') ||
        _resourceBool(map, 'arbitraryCommandAccepted') ||
        _resourceBool(map, 'normalOperationRequiresDesktop') ||
        _resourceBool(map, 'rootRequired')) {
      throw const FormatException(
        'Resource benchmark violates the bounded local benchmark policy.',
      );
    }
    final requestedDurationMs = _resourceInt(map, 'requestedDurationMs');
    if (requestedDurationMs < PandoraResourceBenchmarkRequest.minDurationMs ||
        requestedDurationMs > PandoraResourceBenchmarkRequest.maxDurationMs) {
      throw const FormatException(
        'Resource benchmark duration is out of bounds.',
      );
    }
    final wallDurationMs = _resourceNum(map, 'wallDurationMs');
    final cpuTimeMs = _resourceInt(map, 'cpuTimeMs');
    final cpuTimeScope = _resourceString(map, 'cpuTimeScope');
    if (cpuTimeScope != 'benchmark_worker_thread') {
      throw const FormatException(
        'Resource benchmark CPU time must be scoped to the benchmark worker thread.',
      );
    }
    final iterations = _resourceInt(map, 'iterations');
    final checksum = _resourceInt(map, 'checksum');
    if (wallDurationMs < 0 || cpuTimeMs < 0 || iterations <= 0) {
      throw const FormatException('Resource benchmark metrics are invalid.');
    }

    return PandoraResourceBenchmarkResult(
      schemaVersion: '1.0.0',
      kind: kind,
      requestedDurationMs: requestedDurationMs,
      wallDurationMs: wallDurationMs,
      cpuTimeMs: cpuTimeMs,
      cpuTimeScope: cpuTimeScope,
      iterations: iterations,
      checksum: checksum,
      thermalStatusBefore: _resourceString(map, 'thermalStatusBefore'),
      thermalStatusAfter: _resourceString(map, 'thermalStatusAfter'),
    );
  }
}

abstract interface class PandoraResourceRuntime {
  Future<PandoraResourceSnapshot> getResourceSnapshot();

  Future<PandoraResourceBenchmarkResult> runResourceBenchmark(
    PandoraResourceBenchmarkRequest request,
  );
}

class MethodChannelPandoraResourceRuntime implements PandoraResourceRuntime {
  MethodChannelPandoraResourceRuntime({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<PandoraResourceSnapshot> getResourceSnapshot() async {
    final raw = await _channel.invokeMethod<Object?>('getResourceSnapshot');
    return PandoraResourceSnapshot.fromMap(raw);
  }

  @override
  Future<PandoraResourceBenchmarkResult> runResourceBenchmark(
    PandoraResourceBenchmarkRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'runResourceBenchmark',
      request.toMap(),
    );
    return PandoraResourceBenchmarkResult.fromMap(raw);
  }
}
