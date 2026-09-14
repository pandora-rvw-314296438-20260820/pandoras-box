import 'pandora_resource_runtime.dart';

const String pandoraResourceSnapshotTool = 'tool.device.get_resource_snapshot';
const String pandoraResourceBenchmarkTool =
    'tool.device.run_resource_benchmark';

class PandoraDeviceToolException implements Exception {
  const PandoraDeviceToolException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PandoraDeviceToolProposal {
  const PandoraDeviceToolProposal({
    required this.name,
    required this.arguments,
  });

  final String name;
  final Map<String, Object?> arguments;

  factory PandoraDeviceToolProposal.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const PandoraDeviceToolException(
          'Device tool proposal is invalid.');
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final name = map['name'];
    if (name is! String ||
        (name != pandoraResourceSnapshotTool &&
            name != pandoraResourceBenchmarkTool)) {
      throw const PandoraDeviceToolException(
        'Pandora requested an unsupported device tool.',
      );
    }
    final rawArguments = map['arguments'];
    if (rawArguments is! Map) {
      throw const PandoraDeviceToolException(
        'Pandora device tool arguments are invalid.',
      );
    }
    final arguments = <String, Object?>{};
    for (final entry in rawArguments.entries) {
      if (entry.key is! String) {
        throw const PandoraDeviceToolException(
          'Pandora device tool arguments are invalid.',
        );
      }
      arguments[entry.key as String] = entry.value;
    }
    return PandoraDeviceToolProposal(
      name: name,
      arguments: Map.unmodifiable(arguments),
    );
  }
}

class PandoraDeviceToolResult {
  const PandoraDeviceToolResult({
    required this.tool,
    required this.output,
  });

  final String tool;
  final Map<String, Object?> output;

  Map<String, Object?> toJson() => <String, Object?>{
        'tool': tool,
        'status': 'succeeded',
        'output': output,
      };
}

class DeviceAgentExecutor {
  DeviceAgentExecutor({PandoraResourceRuntime? resourceRuntime})
      : _resourceRuntime =
            resourceRuntime ?? MethodChannelPandoraResourceRuntime();

  final PandoraResourceRuntime _resourceRuntime;

  Future<PandoraDeviceToolResult> execute(
    PandoraDeviceToolProposal proposal,
  ) async {
    switch (proposal.name) {
      case pandoraResourceSnapshotTool:
        if (proposal.arguments.isNotEmpty) {
          throw const PandoraDeviceToolException(
            'Resource snapshot does not accept arguments.',
          );
        }
        final PandoraResourceSnapshot snapshot;
        try {
          snapshot = await _resourceRuntime.getResourceSnapshot();
        } catch (_) {
          throw const PandoraDeviceToolException(
            'Pandora could not safely read this phone resource snapshot.',
          );
        }
        return PandoraDeviceToolResult(
          tool: proposal.name,
          output: <String, Object?>{
            'schemaVersion': snapshot.schemaVersion,
            'capturedAtElapsedRealtimeMs': snapshot.capturedAtElapsedRealtimeMs,
            'cpu': snapshot.cpu,
            'gpu': snapshot.gpu,
            'memory': snapshot.memory,
            'storage': snapshot.storage,
            'battery': snapshot.battery,
            'thermal': snapshot.thermal,
            'process': snapshot.process,
            'network': snapshot.network,
          },
        );
      case pandoraResourceBenchmarkTool:
        if (proposal.arguments.keys.any((key) => key != 'durationMs')) {
          throw const PandoraDeviceToolException(
            'Resource benchmark only accepts durationMs.',
          );
        }
        final rawDuration = proposal.arguments['durationMs'];
        if (rawDuration != null && rawDuration is! int) {
          throw const PandoraDeviceToolException(
            'Resource benchmark duration must be an integer.',
          );
        }
        final request = PandoraResourceBenchmarkRequest(
          durationMs: rawDuration as int? ?? 40,
        );
        try {
          request.toMap();
        } on RangeError {
          throw const PandoraDeviceToolException(
            'Resource benchmark duration must be between 25 and 100 ms.',
          );
        }
        final PandoraResourceBenchmarkResult result;
        try {
          result = await _resourceRuntime.runResourceBenchmark(request);
        } catch (_) {
          throw const PandoraDeviceToolException(
            'Pandora could not safely run the bounded phone resource benchmark.',
          );
        }
        return PandoraDeviceToolResult(
          tool: proposal.name,
          output: <String, Object?>{
            'schemaVersion': result.schemaVersion,
            'kind': result.kind,
            'requestedDurationMs': result.requestedDurationMs,
            'wallDurationMs': result.wallDurationMs,
            'cpuTimeMs': result.cpuTimeMs,
            'iterations': result.iterations,
            'checksum': result.checksum,
            'thermalStatusBefore': result.thermalStatusBefore,
            'thermalStatusAfter': result.thermalStatusAfter,
          },
        );
    }
    throw const PandoraDeviceToolException(
      'Pandora requested an unsupported device tool.',
    );
  }
}
