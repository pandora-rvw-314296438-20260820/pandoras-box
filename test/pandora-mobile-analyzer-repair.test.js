
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const ask = fs.readFileSync(
  "apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart",
  "utf8",
);
const home = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart",
  "utf8",
);
const batalla = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/batalla_workspace_screen.dart",
  "utf8",
);
const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/pandora_chat_shell.dart",
  "utf8",
);
const visionWeb = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_vision_embed_web.dart",
  "utf8",
);

test("Ask Pandora overlay measurement state is complete", () => {
  assert.match(ask, /final GlobalKey _headerKey/);
  assert.match(ask, /final GlobalKey _composerKey/);
  assert.match(ask, /double _headerHeight = 0/);
  assert.match(ask, /double _composerHeight = 0/);
  assert.match(ask, /void _scheduleOverlayMeasure\(\)/);
  assert.match(ask, /_headerKey\.currentContext\?\.size\?\.height/);
  assert.match(ask, /_composerKey\.currentContext\?\.size\?\.height/);
});

test("Enterprise context remains on Ask Pandora but not unused ChatHeader", () => {
  assert.match(ask, /final Map<String, Object\?>\? enterpriseContext;/);
  const header = ask.slice(ask.indexOf("class _ChatHeader"), ask.indexOf("class _Composer"));
  assert.doesNotMatch(header, /enterpriseContext/);
});

test("workspace routes and keys use interpolation", () => {
  assert.match(home, /enterprise\/workspaces\/\${workspace\.key\}\/\${section\.routeSlug\}/);
  assert.match(home, /workspace-card-\${workspace\.key\}/);
  assert.match(home, /workspace-expand-\${workspace\.key\}/);
  assert.match(home, /workspace-more-\${workspace\.key\}/);
  assert.match(home, /\${workspace\.key\}-\${section\.routeSlug\}/);
  assert.match(batalla, /batalla-associates\/\${item\.routeSlug\}/);
  assert.match(batalla, /batalla-nav-\${item\.routeSlug\}/);
  assert.match(batalla, /\${_profile\.displayName\} · Batalla & Associates/);
  assert.match(shell, /enterprise_workspace_\${selection\.workspace\.key\}_\${selection\.section\.routeSlug\}/);
});

test("legacy web embed deprecation is explicitly bounded", () => {
  assert.match(
    visionWeb,
    /ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use/,
  );
});
