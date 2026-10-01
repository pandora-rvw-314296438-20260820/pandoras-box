import 'package:supabase_flutter/supabase_flutter.dart';

import 'pandora_session_storage_stub.dart'
    if (dart.library.js_interop) 'pandora_session_storage_web.dart' as platform;

/// Pandora defaults to memory-only sessions. Product-specific entrypoints may
/// supply an OS-encrypted [LocalStorage] when persistent sign-in is an explicit
/// part of that product's security and device-ownership model.
FlutterAuthClientOptions pandoraAuthClientOptions({
  LocalStorage? localStorage,
}) =>
    FlutterAuthClientOptions(
      localStorage: localStorage ?? const EmptyLocalStorage(),
      pkceAsyncStorage: platform.pandoraPkceStorage(),
    );

/// Prevent an OAuth redirect when this browser cannot retain the PKCE verifier.
bool pandoraCanCompleteFacebookRedirect() =>
    platform.pandoraCanCompleteFacebookRedirect();
