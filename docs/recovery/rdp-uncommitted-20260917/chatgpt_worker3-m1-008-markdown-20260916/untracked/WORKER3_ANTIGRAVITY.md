ANTIGRAVITY WORKER 3 — M1-008 RICH TEXT / MARKDOWN — ISOLATED SOURCE LANE

Goal: fix APK-017 / M1-008 so assistant replies render headings, emphasis and lists cleanly instead of showing raw Markdown markers.

Ownership boundary:
- You may inspect the whole repo.
- You may edit ONLY files needed for assistant-message rich-text rendering and their focused tests.
- DO NOT edit any Worker 1 R-058 files: supabase/functions/pandora-coordinator-gate/**, test/pandora-coordinator-*.test.js, or R-058 migrations.
- DO NOT edit any Worker 2 M4-018 files: PandoraCalendarChannel.kt, pandora_calendar_runtime.dart, MainActivity.kt, PandoraDeviceAgentChannel.kt, configure_validation_android.py, test_configure_validation_android.py, calendar runtime tests/build artifacts.
- DO NOT merge, push, rebase, or mutate another worktree.
- Before every source edit, run git status --short and confirm the target file is outside both ownership sets.
- Keep changes minimal, add focused tests, run the narrow Flutter/Dart tests first, then broader relevant checks if green.
- Stop and record a CONFLICT if required work touches either ownership set.

Acceptance:
- Raw markers such as **Headline finding:** must not display literally in assistant replies.
- Headings/emphasis/lists remain readable and accessible.
- Plain text remains correct.
- No regression to streaming, composer, Activity Theatre, navigation, or device/native code.

Write progress/evidence to WORKER3_STATUS.md in this worktree only.
