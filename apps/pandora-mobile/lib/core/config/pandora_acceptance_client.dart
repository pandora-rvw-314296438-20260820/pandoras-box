import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pandora_runtime_binding.dart';

/// The only admission path for acceptance SDK clients. Registration is private
/// and occurs only when this factory supplies the actual guarded HTTP transport.
class PandoraAcceptanceClient {
  PandoraAcceptanceClient._();
  static final _clients = Expando<_AcceptanceHttpClient>();

  static _AcceptanceHttpClient _transport(PandoraRuntimeBinding binding,
      String publishableKey, http.Client? inner) {
    if (!binding.isAcceptance) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_PROFILE_REQUIRED');
    }
    binding.requireClient(
        restUrl: '${binding.canonical['supabaseUrl']}/rest/v1',
        organizationId: binding.canonical['organizationId']!,
        functionHeaders: {'apikey': publishableKey});
    return _AcceptanceHttpClient(binding, inner ?? http.Client());
  }

  static SupabaseClient create({
    required PandoraRuntimeBinding binding,
    required String publishableKey,
    http.Client? httpClient,
    AuthClientOptions authOptions = const AuthClientOptions(),
  }) {
    final guard = _transport(binding, publishableKey, httpClient);
    try {
      final client = SupabaseClient(
          binding.canonical['supabaseUrl']!, publishableKey,
          httpClient: guard, authOptions: authOptions);
      _clients[client] = guard;
      return client;
    } catch (_) {
      guard.close();
      rethrow;
    }
  }

  static Future<void> initializeFlutter({
    required PandoraRuntimeBinding binding,
    required String publishableKey,
    required FlutterAuthClientOptions authOptions,
  }) async {
    // The SDK silently returns a previous client when initialized twice. That
    // cannot prove guarded transport ownership and must never be relabeled.
    try {
      if (Supabase.instance.isInitialized) {
        throw const PandoraRuntimeBindingException(
            'ACCEPTANCE_CLIENT_ALREADY_INITIALIZED');
      }
    } on AssertionError {
      // The pinned SDK's debug getter asserts only before initialization.
    }
    final guard = _transport(binding, publishableKey, null);
    try {
      final instance = await Supabase.initialize(
          url: binding.canonical['supabaseUrl']!,
          publishableKey: publishableKey,
          httpClient: guard,
          authOptions: authOptions);
      _clients[instance.client] = guard;
    } catch (_) {
      guard.close();
      rethrow;
    }
  }

  /// Supabase does not close an injected HTTP client. Owners of a client from
  /// [create] use this method; Flutter's initialized singleton is app-scoped.
  static Future<void> dispose(SupabaseClient client) async {
    final guard = _clients[client];
    _clients[client] = null;
    guard?.close();
    await client.dispose();
  }

  static void requireGuarded(
      SupabaseClient client, PandoraRuntimeBinding binding) {
    if (!binding.isAcceptance) return;
    final guard = _clients[client];
    if (guard == null ||
        guard.closed ||
        guard.binding.configSha256 != binding.configSha256) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_CLIENT_UNGUARDED');
    }
  }
}

class _AcceptanceHttpClient extends http.BaseClient {
  _AcceptanceHttpClient(this.binding, this.inner);
  final PandoraRuntimeBinding binding;
  final http.Client inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_CLIENT_CLOSED');
    }
    final target = Uri.parse(binding.canonical['supabaseUrl']!);
    final uri = request.url;
    final chat = uri.path == '/functions/v1/pandora-intelligence-chat';
    if (uri.scheme != target.scheme ||
        uri.host != target.host ||
        uri.port != target.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.pathSegments.any((segment) =>
            segment == '.' || segment == '..' || segment.contains('/')) ||
        !(chat ||
            uri.path.startsWith('/auth/v1/') ||
            uri.path.startsWith('/rest/v1/'))) {
      throw const PandoraRuntimeBindingException(
          'ACCEPTANCE_REQUEST_TARGET_MISMATCH');
    }
    binding.requireClient(
        restUrl: '${target.toString()}/rest/v1',
        organizationId: request.headers['x-organization-id'] ??
            binding.canonical['organizationId']!,
        functionHeaders: request.headers);
    if (chat) {
      for (final expected in binding.headers.entries) {
        if (request.headers[expected.key] != expected.value) {
          throw const PandoraRuntimeBindingException(
              'ACCEPTANCE_REQUEST_MISMATCH');
        }
      }
    }
    // A redirect must not forward the client key/session to another backend.
    request.followRedirects = false;
    final response = await inner.send(request);
    try {
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const PandoraRuntimeBindingException(
            'ACCEPTANCE_REDIRECT_REJECTED');
      }
      if (chat) binding.requireResponseHeaders(response.headers);
    } catch (_) {
      try {
        await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
      } catch (_) {
        // Preserve the fixed binding failure even if transport cleanup fails.
      }
      rethrow;
    }
    // Return the original stream: no buffering, duplicate subscription, parsing,
    // or synthetic tokens; downstream cancellation/backpressure is preserved.
    return response;
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    inner.close();
  }
}
