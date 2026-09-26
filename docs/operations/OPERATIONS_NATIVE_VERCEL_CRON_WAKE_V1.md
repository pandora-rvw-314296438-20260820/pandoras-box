# Operations native Vercel Cron wake v1

This change adds a second authenticated wake path for the existing Pandora-native Vercel worker.

- `GET /api/operations-native-worker` is reserved for Vercel Cron and requires Vercel's `Authorization: Bearer $CRON_SECRET` behavior.
- The secret is generated server-side by `private.pandora_ops_provision_vercel_cron_secret_v1()`, sent directly to the fixed canonical Vercel project as a sensitive production environment variable, and never returned by the function.
- `POST /api/operations-native-worker` retains the existing Supabase Vault wake-token digest authorization path.
- Both paths still require the production Vercel workload OIDC token before the fixed Supabase control adapter can register/heartbeat or mutate Operations state.
- No browser origin, query parameter, arbitrary project/task scope, or caller-selected control action is accepted.
- The cron wake does not unpause Operations. It can register the real native builder/release workers while paused, and execution begins only after an explicit workspace control change.

Deployment acceptance requires exact-source merge, server-side secret provisioning receipt, production deployment readback, a cron-authenticated invocation receipt, and live Operations worker/event readback. Source or a configured cron is not execution evidence.
