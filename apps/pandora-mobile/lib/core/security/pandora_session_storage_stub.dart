import 'package:supabase_flutter/supabase_flutter.dart';

LocalStorage pandoraSessionStorage() => const EmptyLocalStorage();

// Preserve Supabase Flutter's existing native PKCE verifier storage.
GotrueAsyncStorage? pandoraPkceStorage() => null;
