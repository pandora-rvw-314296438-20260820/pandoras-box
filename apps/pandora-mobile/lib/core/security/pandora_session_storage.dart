import 'package:supabase_flutter/supabase_flutter.dart';

import 'pandora_session_storage_stub.dart'
    if (dart.library.js_interop) 'pandora_session_storage_web.dart' as platform;

/// Web uses per-tab storage for the session and PKCE verifier. The Android
/// owner app retains its existing memory-only session.
FlutterAuthClientOptions pandoraAuthClientOptions() =>
    FlutterAuthClientOptions(
      localStorage: platform.pandoraSessionStorage(),
      pkceAsyncStorage: platform.pandoraPkceStorage(),
    );
