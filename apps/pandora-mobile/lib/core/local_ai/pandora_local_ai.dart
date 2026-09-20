import 'dart:async';

import 'package:flutter/services.dart';

class PandoraLocalAiStatus {
  const PandoraLocalAiStatus({
    required this.supported,
    required this.configured,
    required this.loaded,
    this.modelName,
    this.modelBytes,
    this.modelSha256,
    this.engineState,
    this.diagnostics = const <String, Object?>{},
  });

  final bool supported;
  final bool configured;
  final bool loaded;
  final String? modelName;
  final int? modelBytes;
  final String? modelSha256;
  final String? engineState;
  final Map<String, Object?> diagnostics;

  static const unavailable = PandoraLocalAiStatus(
    supported: false,
    configured: false,
    loaded: false,
  );

  factory PandoraLocalAiStatus.fromMap(Map<Object?, Object?> value) {
    int? asInt(Object? raw) => switch (raw) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
    String? asText(Object? raw) {
      final text = raw?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return PandoraLocalAiStatus(
      supported: value['supported'] == true,
      configured: value['configured'] == true,
      loaded: value['loaded'] == true,
      modelName: asText(value['modelName']),
      modelBytes: asInt(value['modelBytes']),
      modelSha256: asText(value['modelSha256']),
      engineState: asText(value['engineState']),
      diagnostics: <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) (entry.key as String): entry.value,
      },
    );
  }
}

class PandoraLocalAiException implements Exception {
  const PandoraLocalAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PandoraLocalAi {
  PandoraLocalAi._();

  static final PandoraLocalAi instance = PandoraLocalAi._();

  static const MethodChannel _methods = MethodChannel('pandora/local_ai');
  static const EventChannel _events = EventChannel('pandora/local_ai_tokens');

  Stream<dynamic>? _sharedEvents;

  Stream<dynamic> get _eventStream =>
      _sharedEvents ??= _events.receiveBroadcastStream().asBroadcastStream();

  Future<PandoraLocalAiStatus> status() async {
    try {
      final raw = await _methods.invokeMethod<Object?>('status');
      if (raw is Map<Object?, Object?>) {
        return PandoraLocalAiStatus.fromMap(raw);
      }
      return PandoraLocalAiStatus.unavailable;
    } on MissingPluginException {
      return PandoraLocalAiStatus.unavailable;
    } on PlatformException {
      return PandoraLocalAiStatus.unavailable;
    }
  }

  Future<PandoraLocalAiStatus?> chooseModel() async {
    try {
      final raw = await _methods.invokeMethod<Object?>('pickModel');
      if (raw == null) return null;
      if (raw is Map<Object?, Object?>) {
        return PandoraLocalAiStatus.fromMap(raw);
      }
      throw const PandoraLocalAiException(
        'Pandora could not read the selected local model.',
      );
    } on PlatformException catch (error) {
      throw PandoraLocalAiException(
        error.message ?? 'Pandora could not import that GGUF model.',
      );
    }
  }

  Future<bool> warm() async {
    try {
      final warmed = await _methods.invokeMethod<bool>('warm');
      if (warmed == true) return true;

      final current = await status();
      final phase =
          current.diagnostics['lastWarmFailurePhase']?.toString().trim();
      final failure =
          current.diagnostics['lastWarmFailureMessage']?.toString().trim();
      final state = current.engineState?.trim();
      final detail = <String>[
        if (phase != null && phase.isNotEmpty) 'phase=$phase',
        if (state != null && state.isNotEmpty) 'state=$state',
        if (failure != null && failure.isNotEmpty) failure,
      ].join(' · ');
      throw PandoraLocalAiException(
        detail.isNotEmpty
            ? 'Local model warm failed: $detail'
            : 'Pandora could not warm the selected local model.',
      );
    } on MissingPluginException {
      throw const PandoraLocalAiException(
        'Pandora Android local-AI warm method is unavailable in this APK.',
      );
    } on PlatformException catch (error) {
      final details = error.details;
      String? nativeDetail;
      if (details is Map) {
        nativeDetail =
            details['lastWarmFailureMessage']?.toString().trim();
      }
      throw PandoraLocalAiException(
        (nativeDetail != null && nativeDetail.isNotEmpty)
            ? nativeDetail
            : (error.message ??
                'Pandora could not warm the selected local model.'),
      );
    }
  }

  Future<void> unload() async {
    try {
      await _methods.invokeMethod<void>('unload');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> resetConversation() async {
    try {
      await _methods.invokeMethod<void>('resetConversation');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> cancel() async {
    try {
      await _methods.invokeMethod<void>('cancel');
    } on MissingPluginException {
      return;
    }
  }

  Future<Map<String, Object?>> runAcceptance({
    required String sourceSha,
    required String challengeNonce,
    required String expectedApkSha256,
  }) async {
    try {
      final raw = await _methods.invokeMethod<Object?>(
        'runAcceptance',
        <String, Object?>{
          'sourceSha': sourceSha,
          'challengeNonce': challengeNonce,
          'expectedApkSha256': expectedApkSha256,
        },
      );
      if (raw is! Map<Object?, Object?>) {
        throw const PandoraLocalAiException(
          'Pandora could not read physical acceptance evidence.',
        );
      }
      return <String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) (entry.key as String): entry.value,
      };
    } on MissingPluginException {
      throw const PandoraLocalAiException(
        'Physical acceptance is unavailable on this build.',
      );
    } on PlatformException catch (error) {
      throw PandoraLocalAiException(
        error.message ?? 'Pandora physical acceptance failed.',
      );
    }
  }

  Stream<String> generate(String prompt, {int predictLength = 192}) async* {
    final normalized = prompt.trim();
    if (normalized.isEmpty) {
      throw const PandoraLocalAiException('Local AI prompt cannot be empty.');
    }

    final requestId =
        'local-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final controller = StreamController<String>();
    late final StreamSubscription<dynamic> subscription;

    subscription = _eventStream.listen(
      (event) {
        if (event is! Map<Object?, Object?> ||
            event['requestId'] != requestId) {
          return;
        }
        final type = event['type']?.toString();
        if (type == 'token') {
          final text = event['text']?.toString() ?? '';
          if (text.isNotEmpty && !controller.isClosed) controller.add(text);
          return;
        }
        if (type == 'done') {
          if (!controller.isClosed) controller.close();
          return;
        }
        if (type == 'error' && !controller.isClosed) {
          controller.addError(
            PandoraLocalAiException(
              event['message']?.toString() ?? 'Pandora local inference failed.',
            ),
          );
          controller.close();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
          controller.close();
        }
      },
    );

    try {
      final accepted =
          await _methods.invokeMethod<bool>('generate', <String, Object?>{
            'requestId': requestId,
            'prompt': normalized,
            'predictLength': predictLength.clamp(32, 512),
          }) ??
          false;
      if (!accepted) {
        throw const PandoraLocalAiException(
          'Pandora local inference is unavailable.',
        );
      }
      yield* controller.stream;
    } on MissingPluginException {
      throw const PandoraLocalAiException(
        'Pandora local inference is unavailable on this device.',
      );
    } on PlatformException catch (error) {
      throw PandoraLocalAiException(
        error.message ?? 'Pandora local inference could not start.',
      );
    } finally {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    }
  }
}

class PandoraLocalAiRouteDecision {
  const PandoraLocalAiRouteDecision({
    required this.useLocal,
    required this.reason,
  });

  final bool useLocal;
  final String reason;
}

class PandoraLocalAiRouter {
  const PandoraLocalAiRouter._();

  static PandoraLocalAiRouteDecision? _lastDecision;

  static PandoraLocalAiRouteDecision? get lastDecision => _lastDecision;

  static PandoraLocalAiRouteDecision _record(bool useLocal, String reason) {
    final decision = PandoraLocalAiRouteDecision(
      useLocal: useLocal,
      reason: reason,
    );
    _lastDecision = decision;
    return decision;
  }

  static PandoraLocalAiRouteDecision decide({
    required String message,
    required bool hasAttachment,
    required bool hasProjectContext,
    required bool hasSelectedCapability,
    required bool hasCharacterContext,
    PandoraLocalAiStatus? status,
  }) {
    final value = message.trim();
    if (value.isEmpty) return _record(false, 'empty_message');
    if (value.length > 4000) {
      return _record(false, 'context_exceeds_local_guard');
    }
    if (hasAttachment) return _record(false, 'multimodal_or_attachment');
    if (hasSelectedCapability) return _record(false, 'connected_capability');
    if (hasCharacterContext) return _record(false, 'character_context');

    if (status != null) {
      if (!status.supported) return _record(false, 'local_runtime_unsupported');
      if (!status.configured) return _record(false, 'local_model_missing');
      if (status.diagnostics['memoryLow'] == true) {
        return _record(false, 'android_memory_pressure');
      }
      final thermal =
          status.diagnostics['thermalStatus']?.toString().toLowerCase();
      if (const <String>{
        'severe',
        'critical',
        'emergency',
        'shutdown',
      }.contains(thermal)) {
        return _record(false, 'thermal_pressure');
      }
      final batteryRaw = status.diagnostics['batteryPercent'];
      final batteryPercent = batteryRaw is num
          ? batteryRaw.toInt()
          : int.tryParse(batteryRaw?.toString() ?? '');
      final charging = status.diagnostics['charging'] == true;
      if (batteryPercent != null && batteryPercent <= 15 && !charging) {
        return _record(false, 'low_battery');
      }
    }

    final lower = value.toLowerCase();
    const externalOrConnectedTerms = <String>[
      'weather',
      'stock',
      'market average',
      'what time',
      'time in',
      'score',
      'news',
      'look up',
      'search the web',
      'browse',
      'github',
      'supabase',
      'vercel',
      'posthog',
      'google drive',
      'gmail',
      'calendar',
      'email',
    ];
    if (externalOrConnectedTerms.any(lower.contains)) {
      return _record(false, 'live_or_connected_data');
    }
    const temporalTerms = <String>['latest', 'today', 'right now', 'current'];
    if (temporalTerms.any(lower.contains) && !hasProjectContext) {
      return _record(false, 'fresh_context_not_available_locally');
    }

    const heavyTerms = <String>[
      'deep research',
      'research this',
      'write code',
      'debug this code',
      'refactor',
      'typescript',
      'kotlin',
      'flutter',
      'sql query',
      'analyze repository',
      'image',
      'video',
    ];
    if (heavyTerms.any(lower.contains)) {
      return _record(false, 'heavier_reasoning_or_multimodal');
    }

    final externalAction = RegExp(
      r'^\s*(build|deploy|publish|merge|commit|push|send|call|text|'
      r'create|delete|remove|update|change|fix|install|download|upload|'
      r'open|run|execute|schedule|remind|book|buy)\b',
      caseSensitive: false,
    );
    if (externalAction.hasMatch(value)) {
      return _record(false, 'external_action');
    }

    return _record(
      true,
      hasProjectContext
          ? 'authorized_local_business_context'
          : 'routine_local_sufficient',
    );
  }

  static bool shouldUseLocal({
    required String message,
    required bool hasAttachment,
    required bool hasProjectContext,
    required bool hasSelectedCapability,
    required bool hasCharacterContext,
    PandoraLocalAiStatus? status,
  }) =>
      decide(
        message: message,
        hasAttachment: hasAttachment,
        hasProjectContext: hasProjectContext,
        hasSelectedCapability: hasSelectedCapability,
        hasCharacterContext: hasCharacterContext,
        status: status,
      ).useLocal;
}
