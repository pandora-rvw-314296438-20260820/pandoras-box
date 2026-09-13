# Pandora Mobile Secret Boundary v1

Status: M7-003 implementation contract  
Scope: Android/mobile client, exact-source CI, and provider credential boundary

## Security invariant

Pandora Mobile must never contain or persist long-lived provider master credentials. OpenAI, Gemini, AWS, GitHub, Vercel, Supabase service-role, database, signing, and equivalent privileged credentials stay behind governed server-side/Vault brokers.

The mobile client may contain public connection material such as the canonical Supabase URL and Supabase publishable key. Authenticated calls use the current scoped Supabase user session obtained after owner sign-in. A publishable key is not a provider master credential.

## Owner-test session policy

`supabase_flutter 2.15.4` persists its auth session to SharedPreferences by default using:

`sb-<supabase-project-ref>-auth-token`

For the current non-production owner-test APK, Pandora explicitly:

1. removes that legacy persisted session key before Supabase initialization; and
2. initializes Supabase with `EmptyLocalStorage`.

The result is memory-only user-session state. Closing/restarting the process requires owner re-authentication. This is deliberate until a Keystore-backed persistence design has migration, logout, recovery, rollback, and physical-device evidence.

Existing non-secret SharedPreferences state, such as project-creation attempts and stream cursors, is not removed by the auth cleanup.

## Build-time boundary

The mobile secret-boundary scanner fails closed on operational mobile source or the canonical mobile workflow when it detects:

- provider master-secret identifiers;
- GitHub Actions `secrets.*` injection;
- sensitive `--dart-define` names other than the explicitly public Supabase publishable key;
- credential-shaped GitHub, OpenAI-style, Google, AWS, Supabase-secret, bearer, or private-key literals.

Findings disclose only rule, location, line, and a short SHA-256 fingerprint. The scanner never prints matched credential material.

The canonical `pandora-mobile-integration.yml` already runs every Python `test_*.py` under `apps/pandora-mobile/tool` before Flutter analysis/tests/build. `test_secret_boundary.py` therefore makes the scan an exact-source build gate and scans:

- `apps/pandora-mobile/lib`
- `apps/pandora-mobile/platform`
- `apps/pandora-mobile/pubspec.yaml`
- `apps/pandora-mobile/pubspec.lock`
- `.github/workflows/pandora-mobile-integration.yml`

The pre-existing private-key literal gate remains independent defense in depth.

## Runtime authority

Mobile code must not call provider master APIs with platform credentials. Provider actions route through Pandora/ProjectOS governed adapters and server-side Vault-backed brokers. User/session authority sent from the APK must remain scoped, revocable, and attributable.

No credential value belongs in Activity Theatre events, logs, Memory evidence, screenshots, crash reports, tool/model inputs, source, CI artifacts, or release manifests.

## Acceptance boundary

M7-003 can be source/CI verified without claiming physical device acceptance. Physical claims remain separate gates:

- stock firmware / locked bootloader / non-root baseline;
- exact-source APK identity and signature;
- Wi-Fi and mobile-data journeys;
- calls, SMS, SIM/IMS/VoLTE and emergency behavior;
- GCash/banking/authenticator/password-manager regression;
- install/update/rollback and app-data migration behavior.

A later move from memory-only auth to persistent auth must use Android Keystore-backed storage and repeat the applicable exact-source and physical acceptance gates.
