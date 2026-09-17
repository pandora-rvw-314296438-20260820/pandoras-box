# Pandora Protected-App Security & Provisioning Contract v1

Status: **Implemented contract; physical acceptance pending**
Tasks: **M7-001, M7-002, M7-004, M7-005, M7-007**
Machine contract: `pandora-protected-app-security-v1.json`

## Protected zone

Protected applications include GCash and other financial apps, banks/e-wallets, authenticator apps, password managers, identity/security apps, and other security-sensitive applications.

Pandora may launch a protected app, use supported deep links/APIs, explain required user steps, and resume after supported user re-authentication. Safe handoff never authorizes private screen scraping or financial side effects.

Pandora must deny credential extraction/scraping, OTP reading/bypass, authenticator-secret export outside a secure recovery workflow, biometric bypass, device-integrity bypass, protected-screen scraping, and silent financial transfer. Unknown protected-app operations fail closed.

A model suggestion, Memory pattern, prediction, prior success, or provider fallback never grants protected-app authority.

## Authority and financial actions

- **F0 information_only** — non-transactional public information or guidance.
- **F1 protected_app_handoff** — launch or supported deep link; no financial side effect.
- **F2 account_or_payee_change** — consequential account/payee/security change.
- **F3 money_movement_or_purchase** — transfer, purchase, withdrawal, or deposit.
- **F4 security_bypass_forbidden** — security bypass or silent financial transfer; always deny.

F2/F3 require current explicit user authority or an active explicit standing policy whose scope **and bounds are both verified**, plus protected-app user presence where required. Authority never overrides F4.

Supported protected APIs may execute only inside valid authority, with provider/OS protections verified and an explicit post-action verification plan. If either control is missing, Pandora fails closed.

## Production device integrity baseline

The first production Pandora Device remains on stock firmware with a locked bootloader, no root, no custom ROM, trusted verified boot, required Google/system services preserved, biometrics preserved, SIM/telephony preserved, and IMS dependencies preserved.

Known violations are **blocked**. Unknown integrity facts are **needs_physical_verification**. Only explicitly verified facts plus physical evidence may reach **meets_policy_baseline**.

CI verifies fail-closed policy behavior. CI does not prove that the actual Redmi still satisfies this baseline.

## Destructive provisioning gate

Factory reset, destructive reprovisioning, bootloader changes, or equivalent destructive work must not begin until every gate is verified: authenticator recovery, password-manager recovery, protected-app recovery, backup/export, SIM/eSIM recovery, a known-good rollback path, and explicit user authorization for the destructive action.

The current lane performs no reset, bootloader unlock, OEM unlock, root, custom ROM installation, or destructive provisioning. Recovery confirmation remains a real owner/physical boundary.

## Consequential-action audit

Consequential device/cloud actions record actor/principal, authority basis/policy fingerprint, job/action identity, capability/operation/action class, protected-app class when applicable, redacted input scope, hashed idempotency key, outcome, verification/readback state, evidence identifiers, and timestamps.

Secret-like fields such as credentials, OTPs, tokens, cookies, authorization headers, API keys, private keys and passwords are redacted. Personal payload fields are redacted by default. Raw idempotency keys are never stored.

## Final exact-source physical acceptance run

Do not mark the following PASS from unit tests, CI, emulator, desktop build, or policy inspection. They must be executed on the actual Redmi using the exact-source APK intended for release:

1. Confirm stock HyperOS/Android firmware, locked bootloader, no root/custom ROM, trusted verified-boot behavior, and expected Play/system integrity behavior.
2. Launch GCash and at least one representative bank/e-wallet; verify normal startup, login/reauthentication, biometrics where applicable, and protected-app usability.
3. Launch authenticator/password-manager apps; verify normal user-controlled access and that recovery material remains intact.
4. Place and receive a normal phone call; verify SIM, IMS/VoLTE/VoWiFi where applicable, audio, stock dialer fallback, and incoming-call behavior.
5. Send and receive SMS; verify Pandora obeys policy and stock fallback remains available.
6. Verify Wi-Fi and mobile data separately, including 5G where available, then recheck protected apps after network switching.
7. Verify the emergency-call path remains owned by Android/system telephony and was not intercepted or disabled.
8. Reboot and repeat critical Pandora, telephony, protected-app, permission, background-runtime and battery-behavior checks.
9. Verify source SHA, APK version/build, package ID, signing identity, artifact digest, release manifest, tests and installed artifact all correspond exactly.
10. Capture evidence without recording credentials, OTPs, authenticator secrets, protected financial data or private recovery material.

Any protected-app or core-telephony regression blocks release. A successful CI run is not a waiver.

## Scope note

M7-006 least-privilege runtime permission brokerage remains downstream of M4-001 Device Agent capability/permission foundations. This lane deliberately does not modify Android permission-broker or communications files while M4 workers own those surfaces.
