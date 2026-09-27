import 'package:supabase_flutter/supabase_flutter.dart';

import 'pandora_session_storage_stub.dart'
    if (dart.library.js_interop) 'pandora_session_storage_web.dart' as platform;

/// User sessions stay memory-only on every platform. Web stores only the
/// short-lived PKCE verifier in this browser tab for the OAuth redirect.
FlutterAuthClientOptions pandoraAuthClientOptions() =>
    FlutterAuthClientOptions(
      localStorage: const EmptyLocalStorage(),
      pkceAsyncStorage: platform.pandoraPkceStorage(),
    );

/// Prevent an OAuth redirect when this browser cannot retain the PKCE verifier.
bool pandoraCanCompleteFacebookRedirect() =>
    platform.pandoraCanCompleteFacebookRedirect();
