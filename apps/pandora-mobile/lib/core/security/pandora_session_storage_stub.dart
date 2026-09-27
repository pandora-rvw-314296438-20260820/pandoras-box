import 'package:supabase_flutter/supabase_flutter.dart';

// Preserve Supabase Flutter's existing native PKCE verifier storage.
GotrueAsyncStorage? pandoraPkceStorage() => null;

bool pandoraCanCompleteFacebookRedirect() => false;
