import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_resource_runtime.dart';

Map<String, Object?> _snapshot() => {
      'schemaVersion': '1.0.0',
      'capturedAtElapsedRealtimeMs': 1234,
      'normalOperationRequiresDesktop': false,
      'rootRequired': false,
      'arbitraryCommandAccepted': false,
      'cpu': {
        'logicalProcessors': 8,
        'headroomSupported': true,
        'headroomPercent': 42.5,
        'headroomMinIntervalMs': 1000,
      },
      'gpu': {
        'headroomSupported': false,
        'headroomPercent': null,
        'headroomMinIntervalMs': null,
      },
      'memory': {
        'totalBytes': 8000000000,
        'availableBytes': 4000000000,
        'thresholdBytes': 512000000,
        'lowMemory': false,
      },
      'storage': {
        'scope': 'app_data_filesystem',
        'totalBytes': 128000000000,
        'availableBytes': 64000000000,
      },
      'battery': {
        'available': true,
        'levelPercent': 72.0,
        'charging': false,
        'plugged': 'battery',
        'temperatureCelsius': 32.4,
      },
      'thermal': {
        'status': 'none',
        'headroomSupported': true,
        'headroom': 0.4,
      },
      'process': {
        'pid': 123,
        'totalPssBytes': 12345678,
        'javaHeapAllocatedBytes': 4567890,
        'memoryClassMb': 256,
        'largeMemoryClassMb': 512,
      },
      'network': {
        'permissionGranted': true,
        'available': true,
        'internetCapability': true,
        'validated': true,
        'captivePortal': false,
        'metered': false,
        'transports': ['wifi'],
        'downstreamKbps': 100000,
        'upstreamKbps': 50000,
      },
    };

Map<String, Object?> _benchmark() => {
      'schemaVersion': '1.0.0',
      'kind': 'cpu_integer_mix_v1',
      'requestedDurationMs': 40,
      'wallDurationMs': 40.2,
      'cpuTimeMs': 39,
      'iterations': 100000,
      'checksum': 123456,
      'thermalStatusBefore': 'none',
      'thermalStatusAfter': 'none',
      'persistentMutation': false,
      'arbitraryCommandAccepted': false,
      'normalOperationRequiresDesktop': false,
      'rootRequired': false,
    };

void main() {
  test('parses bounded non-identifying resource snapshot', () {
    final snapshot = PandoraResourceSnapshot.fromMap(_snapshot());

    expect(snapshot.schemaVersion, '1.0.0');
    expect(snapshot.capturedAtElapsedRealtimeMs, 1234);
    expect(snapshot.cpu['headroomPercent'], 42.5);
    expect(snapshot.network['validated'], isTrue);
    expect(snapshot.network.containsKey('ssid'), isFalse);
    expect(snapshot.network.containsKey('bssid'), isFalse);
  });

  test('rejects resource snapshot that weakens phone-only trust boundary', () {
    for (final key in [
      'normalOperationRequiresDesktop',
      'rootRequired',
      'arbitraryCommandAccepted',
    ]) {
      final invalid = _snapshot();
      invalid[key] = true;
      expect(
        () => PandoraResourceSnapshot.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('rejects device and network identifiers in resource telemetry', () {
    for (final key in ['androidId', 'serial', 'ssid', 'bssid', 'ipAddresses']) {
      final invalid = _snapshot();
      final network = Map<String, Object?>.from(invalid['network']! as Map);
      network[key] = 'secret-ish-identifier';
      invalid['network'] = network;
      expect(
        () => PandoraResourceSnapshot.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid CPU and GPU headroom percentages', () {
    for (final key in ['cpu', 'gpu']) {
      final invalid = _snapshot();
      final section = Map<String, Object?>.from(invalid[key]! as Map);
      section['headroomPercent'] = 101;
      invalid[key] = section;
      expect(
        () => PandoraResourceSnapshot.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('resource benchmark request is strictly bounded', () {
    expect(
      const PandoraResourceBenchmarkRequest().toMap(),
      {'durationMs': 40},
    );
    expect(
      () => const PandoraResourceBenchmarkRequest(durationMs: 24).toMap(),
      throwsRangeError,
    );
    expect(
      () => const PandoraResourceBenchmarkRequest(durationMs: 101).toMap(),
      throwsRangeError,
    );
  });

  test('parses bounded resource benchmark result', () {
    final result = PandoraResourceBenchmarkResult.fromMap(_benchmark());

    expect(result.kind, 'cpu_integer_mix_v1');
    expect(result.requestedDurationMs, 40);
    expect(result.iterations, greaterThan(0));
  });

  test('rejects benchmark mutation, command, desktop or root claims', () {
    for (final key in [
      'persistentMutation',
      'arbitraryCommandAccepted',
      'normalOperationRequiresDesktop',
      'rootRequired',
    ]) {
      final invalid = _benchmark();
      invalid[key] = true;
      expect(
        () => PandoraResourceBenchmarkResult.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('rejects out-of-contract benchmark duration', () {
    final invalid = _benchmark();
    invalid['requestedDurationMs'] = 250;
    expect(
      () => PandoraResourceBenchmarkResult.fromMap(invalid),
      throwsFormatException,
    );
  });
}
