
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/pandora_chat_shell.dart",
  "utf8",
);
const screen = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_vision_screen.dart",
  "utf8",
);
const stub = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_vision_embed_stub.dart",
  "utf8",
);
const web = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_vision_embed_web.dart",
  "utf8",
);
const androidHost = fs.readFileSync(
  "apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/MainActivity.kt",
  "utf8",
);
const batalla = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/batalla_workspace_screen.dart",
  "utf8",
);

test("Kabukicho Vision Intelligence is wired into the current shell", () => {
  assert.match(shell, /'Vision Intelligence'/);
  assert.match(shell, /10 => 'vision_intelligence'/);
  assert.match(shell, /10 => EnterpriseVisionScreen\(/);
  assert.match(shell, /\[9, 10, 0, 8, 1, 2, 4, 5, 6, 7, 3\]/);
});

test("web and Android use the same provider-controlled CamStreamer feed", () => {
  const embed =
    "https://camstreamer.com/embed/VSnOa4OubclxMcFKpTws6Yv7U2rt0VbMfcrHomkq?rel=0";
  assert.ok(web.includes(embed));
  assert.ok(androidHost.includes(embed));
  assert.match(stub, /Platform\.isAndroid/);
  assert.match(stub, /AndroidView/);
  assert.match(androidHost, /PandoraCamStreamerViewFactory/);
});

test("abandoned feeds are absent from the converged Vision source", () => {
  const combined = screen + "\n" + web + "\n" + stub;
  for (const oldSource of [
    "Times Square",
    "Perdido",
    "Shibuya",
    "youtube.com",
    "youtube-nocookie.com",
    "webcamlivestream.com",
  ]) {
    assert.equal(combined.includes(oldSource), false, oldSource);
  }
  assert.match(screen, /LIVE KABUKICHO/);
  assert.match(screen, /Automated analysis is/);
  assert.match(screen, /not connected to this public source\./);
});

test("Batalla law-office navigation remains separate from global Vision", () => {
  const navStart = batalla.indexOf("const batallaNavigation");
  const navEnd = batalla.indexOf("class BatallaWorkspaceScreen");
  assert.ok(navStart >= 0 && navEnd > navStart);
  assert.equal(
    batalla.slice(navStart, navEnd).includes("Vision Intelligence"),
    false,
  );
});
