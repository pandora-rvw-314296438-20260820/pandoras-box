import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../local/pandora_local_store.dart';

class ProjectCreationAttempt {
  const ProjectCreationAttempt({
    required this.intent,
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory ProjectCreationAttempt.fromJson(Map<String, Object?> json) {
    final intent = json['intent'];
    final key = json['idempotencyKey'];
    final createdAt = json['createdAt'];
    if (intent is! String ||
        intent.trim().isEmpty ||
        key is! String ||
        key.trim().isEmpty ||
        createdAt is! String) {
      throw const FormatException('Invalid project creation attempt.');
    }
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) {
      throw const FormatException('Invalid project creation attempt time.');
    }
    return ProjectCreationAttempt(
      intent: intent,
      idempotencyKey: key,
      createdAt: parsed.toUtc(),
    );
  }

  final String intent;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'intent': intent,
        'idempotencyKey': idempotencyKey,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

abstract interface class ProjectCreationAttemptStore {
  Future<String?> idempotencyKeyFor(String intent);

  Future<void> save({
    required String intent,
    required String idempotencyKey,
  });

  Future<void> clear({
    required String intent,
    required String idempotencyKey,
  });
}

class SharedPreferencesProjectCreationAttemptStore
    implements ProjectCreationAttemptStore {
  const SharedPreferencesProjectCreationAttemptStore();

  static const _key = 'pandora.project-create.pending.v1';

  @override
  Future<String?> idempotencyKeyFor(String intent) async {
    final normalized = intent.trim();
    if (normalized.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map) return null;
      final attempt = ProjectCreationAttempt.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      return attempt.intent == normalized ? attempt.idempotencyKey : null;
    } on FormatException {
      await prefs.remove(_key);
      return null;
    } on Object {
      await prefs.remove(_key);
      return null;
    }
  }

  @override
  Future<void> save({
    required String intent,
    required String idempotencyKey,
  }) async {
    final normalized = intent.trim();
    final key = idempotencyKey.trim();
    if (normalized.isEmpty || key.isEmpty) {
      throw ArgumentError('Intent and idempotency key are required.');
    }
    final prefs = await SharedPreferences.getInstance();
    final attempt = ProjectCreationAttempt(
      intent: normalized,
      idempotencyKey: key,
      createdAt: DateTime.now().toUtc(),
    );
    await prefs.setString(_key, jsonEncode(attempt.toJson()));
  }

  @override
  Future<void> clear({
    required String intent,
    required String idempotencyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map) return;
      final attempt = ProjectCreationAttempt.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (attempt.intent == intent.trim() &&
          attempt.idempotencyKey == idempotencyKey.trim()) {
        await prefs.remove(_key);
      }
    } on Object {
      await prefs.remove(_key);
    }
  }
}

class PandoraLocalProjectCreationAttemptStore
    implements ProjectCreationAttemptStore {
  PandoraLocalProjectCreationAttemptStore(
    this._store, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _cacheKey = 'project_creation_pending';

  final PandoraLocalStore _store;
  final DateTime Function() _clock;

  Future<ProjectCreationAttempt?> _read() async {
    final record = await _store.getCache(
      PandoraLocalNamespace.recentConversation,
      _cacheKey,
    );
    if (record == null) return null;
    try {
      final raw = jsonDecode(record.payloadJson);
      if (raw is! Map) return null;
      return ProjectCreationAttempt.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on Object {
      await _store.deleteCache(
        PandoraLocalNamespace.recentConversation,
        _cacheKey,
      );
      return null;
    }
  }

  @override
  Future<String?> idempotencyKeyFor(String intent) async {
    final normalized = intent.trim();
    if (normalized.isEmpty) return null;
    final attempt = await _read();
    return attempt?.intent == normalized ? attempt!.idempotencyKey : null;
  }

  @override
  Future<void> save({
    required String intent,
    required String idempotencyKey,
  }) async {
    final normalized = intent.trim();
    final key = idempotencyKey.trim();
    if (normalized.isEmpty || key.isEmpty) {
      throw ArgumentError('Intent and idempotency key are required.');
    }
    final now = _clock().toUtc();
    final attempt = ProjectCreationAttempt(
      intent: normalized,
      idempotencyKey: key,
      createdAt: now,
    );
    await _store.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: _cacheKey,
      payload: attempt.toJson(),
      expiresAt: now.add(PandoraLocalDataPolicy.maxRetention),
    );
  }

  @override
  Future<void> clear({
    required String intent,
    required String idempotencyKey,
  }) async {
    final attempt = await _read();
    if (attempt == null) return;
    if (attempt.intent == intent.trim() &&
        attempt.idempotencyKey == idempotencyKey.trim()) {
      await _store.deleteCache(
        PandoraLocalNamespace.recentConversation,
        _cacheKey,
      );
    }
  }
}
