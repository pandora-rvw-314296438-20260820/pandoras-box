# Facebook / Meta Permission and Review Matrix v1

**Tracker task:** FB-010  
**Provider readback date:** 2026-09-27 (Asia/Manila)  
**Meta app:** `1657540859357214` / Pandora's Box  
**Business Login configuration:** `1472160808104528`  
**Canonical domain:** `mcpmaster.vercel.app`  
**OAuth callback:** `https://mcpmaster.vercel.app/oauth/meta/callback`

This matrix documents capability and review requirements. It does not authorize OAuth, customer access, campaign mutation, messaging, or spend.

## Live provider state used by this matrix

A server-side Meta Graph API v26 read using the Vault-backed app credential returned HTTP 200 and verified:

- app ID `1657540859357214`;
- app name Pandora's Box;
- Business category;
- app domain `mcpmaster.vercel.app`;
- contact email configured;
- `privacy_policy_url` was unset at readback time.

The deployed OAuth preparation contract independently verifies the exact callback above, Business Login `config_id`, one-time state, and active organization-admin guard.

The last exact Meta app-mode evidence attached to PR #757 states that the app is unpublished. External-customer OAuth must therefore remain unclaimed until current publication/App Review state is read back after the legal URLs and review requirements are satisfied.

## Requested permissions

The live server-side `private.pandora_meta_required_scopes_v1()` contract currently requests:

| Permission | Pandora use | Dependencies / review notes | Authority boundary |
| --- | --- | --- | --- |
| `public_profile` | Basic connected-user identity required by login | Basic login scope | Identity only; no business mutation |
| `pages_show_list` | Enumerate Pages the authorized person manages | Meta permission review evidence is required for external use as applicable | Read-only discovery |
| `pages_read_engagement` | Read Page content, metadata and engagement needed for reporting | Depends on `pages_show_list`; Meta documents login + displayed Page-content evidence for review | Read-only until later action approvals |
| `ads_read` | Read Ads Insights and performance reporting | Meta documents this for Ads Insights; external use requires the applicable access/review tier | Read-only analytics |
| `ads_management` | Future bounded campaign-management adapter | Depends on Page permissions; Meta review evidence includes a login plus read and write operation | The scope itself is **not** spend authority; Pandora writes remain blocked behind FB-041–FB-047 approvals |
| `business_management` | Discover/manage Business Manager assets required by the approved business workflow | Depends on `pages_read_engagement` and `pages_show_list`; Meta documents login + business/ad-performance evidence for review | Asset authority only after owner authorization and provider readback |

Source references are Meta's current Permissions Reference and Marketing API/Business Manager documentation.

## Current release blockers before external-customer connection

1. Publish the approved privacy policy and data-deletion instructions at stable HTTPS routes.
2. Set the Meta app `privacy_policy_url` to the deployed Pandora privacy page and read it back from Meta.
3. Confirm current app publication mode and App Review status from Meta provider truth.
4. Complete required permission/use-case review evidence for any permission not available to external customers.
5. Only then treat external Business Login as available.

Development/admin testing must never be presented as evidence that an unrelated external customer can authorize the app.

## Staged authority model

- **FB-010:** validates setup and documents permissions/review requirements; no OAuth completion or spend.
- **FB-011:** owner-authorized interactive OAuth and exact asset selection. This is a separate human gate.
- **FB-013–FB-016:** provider-verified read connectivity and disconnect/revocation behavior.
- **FB-041–FB-045:** bounded campaign-action implementation, explicit expiring approvals, caps, kill switch, readback and paused/draft testing.
- **FB-046:** explicit pilot/spend authorization gate.
- **FB-047+:** paid delivery only after that exact authorization.

Neither `ads_management` nor any other granted Meta scope is sufficient evidence of approval to spend money.

## Legal URL release

The convergence candidate contains:

- `/privacy` and `/privacy-policy` -> public privacy policy;
- `/data-deletion` -> public data-deletion instructions.

Provider configuration is incomplete until the production URLs are deployed and Meta reads back the configured privacy URL.
