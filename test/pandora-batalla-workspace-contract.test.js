
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const home = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart",
  "utf8",
);
const screen = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/batalla_workspace_screen.dart",
  "utf8",
);
const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/pandora_chat_shell.dart",
  "utf8",
);
const api = fs.readFileSync(
  "apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart",
  "utf8",
);

test("Batalla top-level information architecture is exact and Home-first", () => {
  const start = home.indexOf("key: 'batalla-associates'");
  const end = home.indexOf("key: 'bok'", start);
  assert.ok(start >= 0 && end > start);
  const block = home.slice(start, end);
  const expected = [
    "Home",
    "Today",
    "Matters",
    "Clients & Intake",
    "Hearings & Calendar",
    "Reviews & Decisions",
    "Documents & Evidence",
    "Paper Files",
    "Scan & File",
    "Calls & Communications",
    "Print Center",
    "Billing & Finance",
    "Reports",
    "Team & Access",
    "Activity & Audit",
    "Settings",
    "System / Developer",
  ];
  let cursor = -1;
  for (const label of expected) {
    const next = block.indexOf("'" + label + "'");
    assert.ok(next > cursor, label + " is missing or out of order");
    cursor = next;
  }
  assert.ok(!block.includes("Client Portal"));
});

test("Batalla Home implements the three workspace_profile presentations", () => {
  for (const value of [
    "Executive Command Center",
    "Dan's Desk",
    "Secretary Quick Desk",
    "workspace_profile controls presentation only; authorization remains server-enforced.",
  ]) {
    assert.ok(screen.includes(value), "missing " + value);
  }
});

test("Atty decision queue makes counts secondary and exposes decision facts", () => {
  for (const value of [
    "Counts are secondary",
    "What needs my decision?",
    "Preparer",
    "Dan's recommendation",
    "Urgency",
    "Folder state",
    "Who is waiting",
    "Physical folder location",
    "Who owns the next action",
    "What can be printed now",
    "Open Review",
    "Print Packet",
  ]) {
    assert.ok(screen.includes(value), "missing " + value);
  }
});

test("Secretary quick desk preserves the repository safety flow", () => {
  for (const value of [
    "New Client",
    "Calls",
    "Schedule",
    "Scan",
    "Print",
    "Find Folder",
    "I'm not sure — send this for checking",
    "Write it down",
    "Please check",
    "Save and add to the office queue",
    "Drafts are retained",
    "Duplicate protection",
    "Controlled choices and minimal typing",
  ]) {
    assert.ok(screen.includes(value), "missing " + value);
  }
});

test("Matters, paper files, scan, print, conflict and reports keep their legal boundaries", () => {
  for (const value of [
    "Matter Cover Sheet",
    "Physical folder code and volume",
    "Quarantine / security check",
    "Today's Decision Packet",
    "Candidate matches, not automatic conclusions",
    "Daily Reconciliation",
    "Client Portal remains a separate security and visual boundary",
  ]) {
    assert.ok(screen.includes(value), "missing " + value);
  }
});

test("Recent chats are workspace-scoped before appearing in Batalla", () => {
  assert.match(api, /recentThreadsForWorkspace/);
  assert.match(api, /'workspaceKey': normalized/);
  assert.match(screen, /recentThreadsForWorkspace/);
  assert.match(screen, /batalla-recent-chats/);
});

test("shell opens Batalla as a dedicated workspace and preserves generic Pandora", () => {
  assert.match(shell, /BatallaWorkspaceScreen/);
  assert.match(shell, /_activeWorkspaceSelection/);
  assert.match(shell, /selection\.workspace\.key == 'batalla-associates'/);
  assert.match(shell, /AskPandoraScreen/);
});
