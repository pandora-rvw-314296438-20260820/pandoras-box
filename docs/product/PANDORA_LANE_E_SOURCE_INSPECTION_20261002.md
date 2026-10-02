# Lane E — Global Active-Chat Shell Source Inspection

Date: 2026-10-02
Owner directive: locked Lane E baseline.
Visual benchmark: owner-approved 6470.mp4 (compact mobile composer interaction).

## Source inspected

- `apps/pandora-mobile/lib/main.dart` and `app/pandora_app.dart`: app entry and MaterialApp.
- `features/auth/auth_gate.dart`: authenticated owner route chooses `PandoraChatShell`.
- `app/pandora_chat_shell.dart`: main owner navigation, drawers, breakpoints, workspace routing and the current `AskPandoraScreen` destination.
- `features/simple/ask_pandora_screen.dart`: conversation/thread ownership, attachments, voice, capability context, keyboard/safe-area behavior and cloud/local dispatch.
- `features/operations/operations_room_screen.dart`: independent Operations Room thread/composer.
- `app/plp_enterprise_shell.dart`: PLP persistent command dock forwarding into one mounted `AskPandoraScreenState`.
- `app/eurofish_enterprise_shell.dart`: page/launcher-oriented Pandora entry points.
- Vision, workspace-home and current navigation/widget tests and visual-evidence coverage.

## Findings

1. Conversation state already has a viable single owner: `AskPandoraScreenState` owns the thread id, messages, pending turn, attachments, service/project/character context, error state and submission lifecycle.
2. PLP already proves external prompts can be submitted into that same mounted state across page navigation, but its separate `PlpCommandDock` and one-off reply strip are not the Lane E interaction.
3. Main Pandora currently exposes chat as destination 0 instead of an app-level layer. Vision navigates into that destination and Operations Room owns another chat state.
4. Euro-Fish still uses launcher/page-specific entry patterns.
5. The strongest keyboard implementation is in `AskPandoraScreen`: `resizeToAvoidBottomInset: false`, explicit `MediaQuery.viewInsets.bottom` anchoring, measured composer height and conversation viewport updates.
6. Main shell breakpoint is 900px. Vision uses a 920px wide-layout threshold. PLP has dedicated keyboard tests; main has navigation/keyboard tests plus non-blocking golden evidence.
7. PR #902 owns current landing/drawer/scrim polish and is the source base for this stacked PR. PR #903 owns Connections cleanup and is intentionally not duplicated here.

## Bounded implementation sequence

1. **PR 1 — shared shell / composer / state:** app-level `PandoraConversationLayer`, one mounted conversation state, compact fixed composer, expandable/minimizable history and intentional page-context rebinding.
2. **PR 2 — history convergence:** move recent-thread controls into the inline history model and remove obsolete separate-history chrome.
3. **PR 3 — enterprise shell convergence:** migrate PLP and Euro-Fish onto the shared layer while preserving each business visual identity and real operational pages.
4. **PR 4 — specialist-chat cleanup:** converge Operations Room/page-specific chat duplicates, provider connection initiation and natural failure/confirmation states.
5. **PR 5 — acceptance:** responsive/accessibility hardening, long-page reachability, cross-page commands/context, visual evidence against 6470.mp4 and exact-source runtime verification.

## PR 1 non-goals

PR 1 does not claim Lane E production acceptance. It deliberately leaves PLP/Euro-Fish migration, Operations Room convergence, complete selected-record/filter context, provider-flow acceptance and refreshed visual screenshots for later bounded PRs.
