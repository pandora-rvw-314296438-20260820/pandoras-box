import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_device_tool_executor.dart';
import 'package:pandora_mobile/core/device/pandora_resource_runtime.dart';

class _FakeRuntime implements PandoraResourceRuntime {
  int snapshotCalls = 0;
  int benchmarkCalls = 0;
  int? benchmarkDuration;

  @override
  Future<PandoraResourceSnapshot> getResourceSnapshot() async {
    snapshotCalls += 1;
    return const PandoraResourceSnapshot(
      schemaVersion: '1.0.0',
      capturedAtElapsedRealtimeMs: 99,
      cpu: {'logicalProcessors': 8},
      gpu: {'headroomSupported': false},
      memory: {'availableBytes': 100},
      storage: {'availableBytes': 200},
      battery: {'levelPercent': 80.0},
      thermal: {'status': 'none'},
      process: {'pid': 1},
      network: {'available': true},
    );
  }

  @override
  Future<PandoraResourceBenchmarkResult> runResourceBenchmark(
    PandoraResourceBenchmarkRequest request,
  ) async {
    benchmarkCalls += 1;
    benchmarkDuration = request.durationMs;
    return PandoraResourceBenchmarkResult(
      schemaVersion: '1.0.0',
      kind: 'cpu_integer_mix_v1',
      requestedDurationMs: request.durationMs,
      wallDurationMs: request.durationMs.toDouble(),
      cpuTimeMs: request.durationMs,
      iterations: 10,
      checksum: 7,
      thermalStatusBefore: 'none',
      thermalStatusAfter: 'none',
    );
  }
}

void main() {
  test('snapshot proposal executes only the typed resource runtime', () async {
    final runtime = _FakeRuntime();
    final executor = DeviceAgentExecutor(resourceRuntime: runtime);
    final proposal = PandoraDeviceToolProposal.fromJson({
      'name': pandoraResourceSnapshotTool,
      'arguments': <String, Object?>{},
    });

    final result = await executor.execute(proposal);

    expect(runtime.snapshotCalls, 1);
    expect(runtime.benchmarkCalls, 0);
    expect(result.toJson()['tool'], pandoraResourceSnapshotTool);
    expect(result.output['capturedAtElapsedRealtimeMs'], 99);
  });

  test('benchmark proposal is bounded to 25-100 ms', () async {
    final runtime = _FakeRuntime();
    final executor = DeviceAgentExecutor(resourceRuntime: runtime);
    final proposal = PandoraDeviceToolProposal.fromJson({
      'name': pandoraResourceBenchmarkTool,
      'arguments': <String, Object?>{'durationMs': 75},
    });

    final result = await executor.execute(proposal);

    expect(runtime.benchmarkCalls, 1);
    expect(runtime.benchmarkDuration, 75);
    expect(result.output['requestedDurationMs'], 75);
  });
  test('executor rejects arbitrary tools and unexpected arguments', () async {
    expect(
      () => PandoraDeviceToolProposal.fromJson({
        'name': 'tool.device.shell',
        'arguments': <String, Object?>{},
      }),
      throwsA(isA<PandoraDeviceToolException>()),
    );

    final runtime = _FakeRuntime();
    final executor = DeviceAgentExecutor(resourceRuntime: runtime);
    final snapshotWithCommand = PandoraDeviceToolProposal.fromJson({
      'name': pandoraResourceSnapshotTool,
      'arguments': <String, Object?>{'command': 'id'},
    });
    await expectLater(
      executor.execute(snapshotWithCommand),
      throwsA(isA<PandoraDeviceToolException>()),
    );
    expect(runtime.snapshotCalls, 0);
  });

  test('executor rejects out-of-range and non-integer benchmark duration',
      () async {
    final runtime = _FakeRuntime();
    final executor = DeviceAgentExecutor(resourceRuntime: runtime);
    for (final value in <Object?>[24, 101, 40.5]) {
      final proposal = PandoraDeviceToolProposal.fromJson({
        'name': pandoraResourceBenchmarkTool,
        'arguments': <String, Object?>{'durationMs': value},
      });
      await expectLater(
        executor.execute(proposal),
        throwsA(isA<PandoraDeviceToolException>()),
      );
    }
    expect(runtime.benchmarkCalls, 0);
  });
}
