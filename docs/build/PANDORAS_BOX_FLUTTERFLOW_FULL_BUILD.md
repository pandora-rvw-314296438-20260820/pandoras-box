# FINISH PANDORA'S BOX — FULL AUTONOMOUS BUILD

You are the lead product engineer, FlutterFlow expert, systems architect, UX designer, integration engineer, QA engineer, and release manager for Pandora's Box.

Use **GPT-5.6 Sol as the lead model**. Use Terra for parallel implementation/testing when useful and Luna only for repetitive low-risk work.

PROJECT:
https://app.flutterflow.io/project/pandoras-box-gj9hnb

## PRIMARY OBJECTIVE

Take the existing Pandora's Box FlutterFlow project from its current real state to a polished, working, premium, production-ready control center.

Do not merely redesign mockups or write recommendations.

Inspect the actual project, understand what already exists, preserve good working parts, repair broken parts, simplify confusing parts, complete missing parts, test everything, and leave the project in the strongest verified state possible.

The finished product must feel extremely premium, calm, sophisticated, fast, and easy enough that a non-technical business owner can understand it.

It must NOT feel like a developer dashboard.

## FIRST: RECOVER THE REAL PROJECT STATE

Pandora Memory is the authoritative project memory.

Before making substantial changes:

1. Connect to Pandora Memory/MCPMaster.
2. Recover the current roadmap, architecture, decisions, tasks, blockers, source state, integrations, deployment evidence, tests, rollback information, and next action.
3. Treat `https://mcpmaster.vercel.app/mcp` as the legacy machine route that was blocked by Vercel Authentication with HTTP 401.
4. The current direct production Memory OAuth MCP resource is `https://pandorasbox-memory.vercel.app/api/mcp`. Live verification on 2026-08-10 showed that this route reaches application authorization and returns the expected bearer challenge; its protected-resource metadata is also live.
5. The current ChatGPT/Pandora Memory health and search binding still fails with HTTP 404 even though the direct production MCP resource is reachable. Diagnose the exact connector endpoint, OAuth binding, workload identity, namespace, and grant path before changing application authorization.
6. Do not disable Vercel protection globally, allow anonymous Memory access, weaken application authorization, invent a universal credential, or expose any bearer or workload token merely to clear the connection error.
7. Do not invent missing Pandora state.
8. If newer verified evidence contradicts Pandora, correct Pandora first and preserve the previous history.

Distinguish at all times:

Documented → Implemented → Tested → Deployed → Production Verified.

Never call something finished because code merely exists.

## INSPECT THE ACTUAL FLUTTERFLOW PROJECT

Open the existing FlutterFlow project.

Audit:

- every page
- every component
- navigation
- themes
- typography
- responsive layouts
- mobile behavior
- tablet behavior
- desktop behavior
- actions
- API calls
- custom actions
- authentication
- Supabase
- state management
- variables
- database queries
- loading states
- empty states
- error states
- permissions
- integrations
- duplicated components
- unused components
- broken actions
- dead navigation
- inconsistent spacing
- inconsistent terminology
- accessibility
- performance problems

Do not rebuild blindly.

Preserve what is good and improve what is weak.

## RADICALLY SIMPLIFY THE PRODUCT

Pandora's Box may be technically sophisticated underneath.

The interface must NOT expose that complexity.

The product should explain itself in ordinary language.

Prefer these concepts:

Home
Projects
Connections
Approvals
Activity
Memory
Settings

Avoid technical language unless the user explicitly opens an Advanced/Developer area.

Examples:

"MCP Server" → "Connection"

"MCP Registry" → "Connections"

"Tool Invocation" → "Action"

"Execute" → "Run"

"Execution Pipeline" → "How it will run"

"Risk Gate" → "Approval needed"

"AAL2" → "Extra verification"

"Service Principal" → "System account"

"OIDC Workload Identity" → "Secure system sign-in"

"Adapter" → "Connector"

"Provider" → "Service"

"Deployment Artifact" → "Release"

"Rollback" → "Restore previous version"

"Orchestration" → "Automation"

"Telemetry" → "Activity"

"Semantic Memory" → "Memory"

"Runtime" → "System"

Do not dumb down the capabilities.

Simplify how they are explained.

Technical information can remain available under an Advanced Details disclosure.

## CORE USER EXPERIENCE

The main screen should immediately answer:

1. What projects do I have?
2. What is happening right now?
3. Is anything waiting for me?
4. Are my connections healthy?
5. What should happen next?

Create one prominent command/input area such as:

"What do you want Pandora to do?"

The owner should be able to request work naturally instead of navigating dozens of engineering controls.

Examples:

"Continue Porknyeta."

"Check Battle."

"Fix the deployment."

"Connect Gmail."

"What's blocking FXPass?"

"Show me what needs my approval."

Pandora should translate these human requests into the underlying technical actions.

## OFFICIAL PANDORA'S BOX PRODUCT MARK

Use the attached asset `2165.png` as the sole user-approved official Pandora's Box product mark for this build.

Source identity:

- SHA-256: `d6f055b88b962b4dbae4ac67bc30f5e31b6c3a90997dfd5fddf9a0be23aa5970`
- 1536 × 1536 monochrome white apple/vortex linework on a black square field
- no approved replacement, recolor, transparent version, vector version, simplified version, wordmark, or alternate logo is implied

Do not redraw, trace, regenerate, reinterpret, recolor, invert, distort, animate, or replace this mark. Do not turn the apple red. Do not substitute a stock apple, emoji, icon-font glyph, generated approximation, generic FlutterFlow icon, or fallback asset.

Preserve the original uploaded bytes unchanged as the provenance master. The supplied file is JPEG-encoded despite its `.png` filename. Normalize delivery derivatives so their filename, encoding, and MIME type agree, but never overwrite the source master.

Create deterministic display derivatives from the master:

- a tightly cropped square UI asset that removes only excess outer black canvas while preserving the complete apple, leaf, stem, spiral details, aspect ratio, and a safe margin
- a square launcher/maskable asset with the complete mark inside the platform-safe area
- correctly encoded and optimized sizes for FlutterFlow UI, browser favicon/PWA, and native launcher use

Do not remove the black field or create a transparent or inverted variant without separate owner approval. Use the approved black-and-white treatment in both themes. On light surfaces, retain the black logo field. On dark surfaces, a subtle neutral border may be applied to the surrounding container when needed, but never to or inside the artwork.

Use `contain`, never `cover`, for in-product rendering. Never clip the leaf, stem, outer apple silhouette, or spiral.

Required placements:

- desktop navigation header: 40–48 px mark beside the text `Pandora's Box`
- mobile top app bar: 40–48 px mark
- sign-in and secure reconnect screens: 144–192 px mark
- launch and splash states: 180–240 px mark
- browser favicon and pinned icon
- web-app manifest and PWA install icons
- native app launcher and adaptive icon where applicable
- About and product-identity surfaces

Do not use the logo as a 20–24 px bottom-navigation icon; its fine linework will not remain legible. Use it sparingly. Do not repeat it on every card, use it as a decorative watermark, turn it into a loading spinner, or let it compete with the page's primary action. The accessible label is `Pandora's Box`.

Treat this as the primary Pandora's Box product mark. Keep any separate Banatao Systems ownership treatment subordinate and use it only when the exact canon-approved ownership asset is available. Never replace this product mark with an ownership mark or fabricate a missing ownership asset.

If Pandora Memory records a different current product mark, treat this owner-approved asset as newer verified direction: update the canon with the source checksum, preserve the prior identity's history, and then change the product.

## PREMIUM ELITE UI/UX

Upgrade the entire visual system.

Aim for the quality level expected from a serious institutional software company, not a generic FlutterFlow template.

Design principles:

- restrained
- premium
- highly polished
- minimal
- confident
- spacious
- extremely readable
- responsive
- consistent
- fast
- subtle rather than flashy

Use a sophisticated neutral foundation.

Use black, white, charcoal, and soft gray. The approved product mark is monochrome; do not infer or invent a brand accent from it. Use another accent only if Pandora's verified product canon already contains an explicitly approved color, and then use it sparingly.

Do not flood the interface with gradients, glowing cards, excessive glassmorphism, huge shadows, random colors, or unnecessary animations.

Use color primarily to communicate meaning.

Create excellent light AND dark themes.

Use a disciplined design system for:

- typography
- spacing
- radii
- borders
- shadows
- surfaces
- buttons
- form fields
- icons
- cards
- modals
- sheets
- status indicators
- tables
- navigation
- charts
- command interfaces

Every page should clearly belong to the same product.

Use subtle motion only where it improves understanding.

## MOBILE FIRST WITHOUT SACRIFICING DESKTOP

The system must work beautifully from a phone.

No requirement should force the owner to use a desktop, terminal, CLI, developer console, or manually copy code when an available connected tool can perform the work.

Optimize tap targets, bottom sheets, navigation, approvals, status cards, command entry, and project management for one-handed mobile use.

Then make tablet and desktop versions equally polished.

Do not simply shrink desktop layouts onto mobile.

## MCP ARCHITECTURE — ONE FRONT DOOR

Do NOT directly hard-wire FlutterFlow to every MCP independently.

Use this architecture:

FlutterFlow
↓
Pandora/MCPMaster secure gateway
↓
MCP connector registry
↓
Available MCP services

Pandora/MCPMaster should be the single front door.

FlutterFlow should ask the gateway things such as:

- show available connections
- show connection health
- show available actions
- request an action
- show action progress
- request approval
- show results
- retrieve project state

Adding a future MCP should normally NOT require redesigning the FlutterFlow application.

The gateway should return a consistent normalized format regardless of which MCP actually executes the operation.

Build reusable models for concepts such as:

Connection
Action
Project
Task
Approval
Run
Result
Health
Capability

Use OpenAPI-compatible APIs where practical so FlutterFlow API definitions can be imported and maintained cleanly.

Never place privileged MCP credentials or service secrets in the FlutterFlow client.

Keep sensitive execution server-side.

## CONNECTIONS EXPERIENCE

Build a simple Connections page.

A normal user should see things like:

GitHub — Connected
Vercel — Connected
Supabase — Connected
Google Drive — Connected
Gmail — Connected
PostHog — Connected
Resend — Needs attention

Each connection should provide simple actions:

View
Connect
Reconnect
Test
Disconnect

Advanced technical information can be hidden under:

"Technical details"

The app should retrieve capabilities dynamically whenever practical instead of hard-coding assumptions about each MCP.

## PROJECT EXPERIENCE

Each project should have a clean project page showing:

Project name
Purpose
Current phase
Progress based on verified roadmap work
Current activity
Completed work
Work in progress
Blockers
Approvals needed
Recent releases
Connection health
Next recommended action

Never invent completion percentages.

Calculate progress only from the real roadmap/tasks/proof gates.

## APPROVALS

Create an exceptionally simple approval interface.

Explain:

What Pandora wants to do
Why it wants to do it
What will change
Risk level
Whether it can be reversed

Then provide clear actions such as:

Approve
Reject
View details

High-risk actions must remain fail-closed.

Do not weaken existing Pandora/Pandora security merely to simplify the interface.

## MEMORY

Pandora Memory should feel understandable.

The user should be able to ask:

"What do you remember about this project?"

"Why did we make this decision?"

"What happened yesterday?"

"What's blocking us?"

"Continue from where we stopped."

Keep deep provenance and technical evidence underneath, while presenting a clean human-readable summary first.

## RESILIENCE

Design useful states for:

Connected
Connecting
Working
Waiting for approval
Temporarily unavailable
Authentication expired
Failed
Completed
Needs attention

Never display raw stack traces or cryptic API errors as the primary message.

Translate technical failures into useful language and provide the appropriate recovery action.

Example:

Instead of:

HTTP 401 OIDC workload authentication failed

show:

"Pandora needs to reconnect."

Then optionally show the technical details underneath.

## SECURITY

Protect:

credentials
API keys
tokens
private customer information
authentication data
financial records
KYC information
sensitive message contents

Do not expose privileged secrets in the FlutterFlow client, logs, screenshots, analytics, or semantic memory.

Retain authorization and approval controls.

Do not bypass security simply to make an integration work.

## REMOVE CLUTTER

Find and remove or consolidate:

duplicate pages
duplicate components
dead navigation
unused variables
unused APIs
placeholder content
fake metrics
fake activity
developer-only terminology
unnecessary settings
redundant buttons
contradictory status information
unfinished demo elements

Do not delete recovery evidence or working functionality merely for cleanliness.

## PERFORMANCE

Optimize:

initial loading
API call count
unnecessary queries
widget rebuilds
large assets
image sizes
repeated backend calls
list rendering
navigation responsiveness
state handling

Provide skeleton/loading states where useful.

The app should feel immediate even when backend work continues asynchronously.

## TEST EVERYTHING

Test real functionality, not just appearance.

Verify:

authentication
logout/login
navigation
responsive layouts
API calls
MCP gateway
connection discovery
connection health
actions
approvals
failed requests
timeouts
empty states
offline/reconnect behavior where applicable
Supabase authorization/RLS
theme switching
official logo rendering in light and dark themes
header, mobile app bar, sign-in, reconnect, and splash placements
favicon, pinned icon, web manifest, PWA, and native launcher assets
logo recognition at the smallest rendered size
asset MIME type, cache version, crop, contrast, sharpness, and safe area
absence of placeholder, fallback, recolored, or regenerated logos
mobile layout
tablet layout
desktop layout
accessibility
data persistence

Check that sensitive operations remain protected.

## FINAL UX REVIEW

After implementation, perform another complete pass as a demanding product-design reviewer.

Remove anything that feels:

cheap
template-like
overdesigned
confusing
technical without reason
inconsistent
crowded
unfinished

Every important screen must have:

a clear purpose
a clear hierarchy
one obvious primary action
good empty states
good loading states
good error states
consistent visual language

## AUTONOMOUS EXECUTION

Do not stop after producing an audit or roadmap.

Audit → decide → implement → test → repair → retest → verify.

Continue autonomously through safe, reversible, no-cost work.

Do not repeatedly ask the owner what to do next when existing project state determines the answer.

Interrupt only when genuinely required for:

missing permissions or authentication
new spending
destructive production/data actions
legal/public commitments
regulated activation
non-preauthorized production release
unavoidable owner confirmation

## SOURCE AND RECOVERY

Preserve durable source and recovery evidence.

Maintain version history.

Do not overwrite recovery evidence just to create a cleaner-looking current state.

Keep Pandora Memory updated whenever meaningful project reality changes.

## DEFINITION OF FINISHED

Do NOT say "done" merely because FlutterFlow saves successfully.

Finished means the relevant work is:

Implemented
Tested
Integrated
Responsive
Security checked
Visually reviewed
Deployment verified where applicable
Recovery/rollback understood
Recorded in Pandora Memory

Anything without required proof remains incomplete.

## FINAL REPORT

When substantial work has been completed, give me a concise owner-level report:

WHAT CHANGED
What you actually changed.

EVIDENCE
What proves it works.

CURRENT PHASE
Where the project really is now.

DONE
Verified completed work.

IN PROGRESS
Anything still actively unfinished.

BLOCKED
Anything that genuinely requires outside action.

RISKS
Only meaningful remaining risks.

NEXT AUTONOMOUS ACTION
The highest-value safe thing Pandora should do next.

Use simple language.

Do not bury me in engineering jargon.

Do not give me a generic roadmap and stop.

**Go full blast on the actual project.**
