# pandora-owner-api v100 — allow https://enterprise-omega-five.vercel.app

Deployed 2026-10-09 to Supabase project `jcyqixttuebxqqfkjonq` (verify_jwt=false,
same as v99). These are the exact deployed files.

v99 was a one-line shim importing the owner-api source at commit
`33f37ef9dea651ff5cc78fa8bff5a1158099dc01`
(`ops/supabase/runtime-patches/pandora-owner-api-v98-plp-billing-sandbox/`).
v100 keeps that shim byte-for-byte and adds only:

- `deno.json`: one import-map entry that remaps that commit's `contract.ts`
  to the local `./contract.ts`.
- `contract.ts`: the commit's file with one line added to
  `DEFAULT_ALLOWED_ORIGINS`: `"https://enterprise-omega-five.vercel.app"`.

Every other module (index.ts, paypal-billing.mjs, command-pipeline.mjs,
operational-workspace.mjs) is still bundled from the immutable commit.

The live return/cancel URL check (`pandora_plp_billing_checkout_v1`) only
requires `https://`, so no backend return-host allowlist change was needed.

Rollback: redeploy v99 = this directory's `index.ts` with `deno.json`
reduced to `{"compilerOptions":{"strict":true}}` and no `contract.ts`.
