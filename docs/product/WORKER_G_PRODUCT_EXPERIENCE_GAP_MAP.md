# Worker G — Product Experience Gap Map

Audit baseline: `main` at `789eae5869363499c5bbafd63d1f2660200abde9` after Worker B PR #42 merged.

## Confirmed good foundations

- Simple Mode primary navigation is already `Home / Projects / Ask Pandora / Needs You / Business` on mobile and desktop.
- Ask Pandora is the visually prominent mobile action.
- Projects is the visible customer portfolio container; `Systems` is not a primary navigation item.
- The current Project journey creates real provider-backed previews through the server-side project runtime boundary.
- HTTPS preview/live links use the existing native URL bridge with scheme validation.
- The Build Theatre already has Pandora-specific mark/orbit motion and honors reduced-motion preferences.
- Authentication and organization-sensitive routes remain inside the existing authenticated shell boundary.

## Highest-priority gaps found

| Area | Live source truth | Worker G action |
| --- | --- | --- |
| Create Project | Name, intent and build type are combined into one form | Split into a short owner journey: name → build type → natural-language intent → understanding confirmation |
| Intent understanding | Flutter creates the project directly from raw form text | Consume Worker B / Worker A owner-safe understanding and ProjectSpec summary once the server contract is exposed |
| Build Theatre | Presentation used a 1.2-second local stage timer | Fixed in PR #48: reconcile from durable project runtime state, resume on app foreground, never advance from a presentation timer |
| Build resume | Re-entering the theatre could start another preview request | Fixed in PR #48: fetch durable runtime first and only request a preview when no preview/in-flight state exists |
| Owner language | Build/runtime wording was distributed across screens | PR #48 adds a centralized owner-safe project/build language mapper |
| Verification | Current customer runtime snapshot has no Worker E release-readiness projection | Keep preview and publish readiness distinct; wire the release-readiness contract when available |
| Publish | Current runtime can publish a preview without a Worker E eligibility field in Flutter | UI must fail closed once release-readiness projection exists; do not infer eligibility from build completion |
| Change loop | No complete conversational `preview → change → new version` customer loop | Add governed change intent flow after the intent/control-plane API is available |
| Version history | Current Simple project workspace does not yet present owner-readable version history | Add latest preview/current live/previous versions using control-plane/runtime lineage |
| Rollback | Current Simple project workspace has no complete rollback flow | Add impact-aware rollback only from Worker F/E eligibility truth |
| Domain | Domain state is basic connected/verification-required copy | Expand to setup required / connecting / checking / live / needs attention from runtime truth |
| Business | Business surface exists but is not yet project-objective/result driven end to end | Bind to measured objective/metric projections; show `Not measured yet` when unavailable |
| Stale/offline | Project list has cache support but project workspace/build freshness is incomplete | Preserve last known safe state, show freshness, reconnect without replacing unknown with success |
| Legacy source | Legacy `systems_screen.dart` and `more_screen.dart` remain in the source tree | Keep only as secondary/legacy surfaces where still referenced; never restore them as Simple Mode primary navigation |
| Documentation | Older master-plan guards still assume legacy More/Systems source surfaces | Converge docs and guards on implemented Projects-first customer truth without deleting valid secondary safety/professional routes blindly |

## Backend contract dependencies

- Worker A PR #43 explicitly reports the Build Theatre customer-safe Realtime projection as not yet implemented in its current tranche.
- Worker B PR #42 provides provider-independent intelligence foundations, but not yet a customer Flutter API for compiled owner-safe understanding.
- Worker E/F release-readiness, verified-preview and rollback eligibility must remain authoritative; Worker G will not manufacture those states.

## Worker G implementation order

1. Truthful/resumable Build Theatre and centralized owner language.
2. Create → type → describe → owner-readable understanding journey.
3. Preview/workspace iteration and version awareness.
4. Publish eligibility, publishing theatre, domain and live-project states.
5. Needs You / Business integration and post-launch recommendations.
6. Professional expansion, accessibility, responsive/golden coverage and full journey proof.

PR #26 is explicitly excluded from all Worker G work.
