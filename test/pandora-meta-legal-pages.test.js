"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const app = require("../vercel-entrypoint.js");

const root = path.resolve(__dirname, "..");

test("Meta legal routes resolve to substantive public HTML instead of Pandora's web shell", async () => {
  const { rewrites } = JSON.parse(readFileSync(path.join(root, "vercel.json"), "utf8"));
  const map = new Map(rewrites.map(({ source, destination }) => [source, destination]));
  assert.equal(map.get("/privacy"), "/privacy.html");
  assert.equal(map.get("/privacy-policy"), "/privacy.html");
  assert.equal(map.get("/data-deletion"), "/data-deletion.html");
  assert.equal(map.get("/terms"), "/terms.html");

  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const origin = `http://127.0.0.1:${server.address().port}`;
    for (const [route, heading] of [
      ["/privacy", "Privacy policy"],
      ["/data-deletion", "Data deletion instructions"],
      ["/terms", "Terms of use"],
    ]) {
      const response = await fetch(origin + route, { headers: { accept: "text/html" } });
      assert.equal(response.status, 200, route);
      assert.match(response.headers.get("content-type") || "", /^text\/html/i, route);
      const body = await response.text();
      assert.match(body, new RegExp(`<h1>${heading}<\\/h1>`), route);
      assert.match(body, /markjohnsonbanatao888@gmail\.com/, route);
      if (route === "/privacy") {
        assert.match(body, /Facebook account sign-in/);
        assert.match(body, /Proposed on 27 September 2026 for Owner review; not yet approved for publication/);
        assert.match(body, /an email address if Meta provides one/);
        assert.match(body, /separate from the optional Meta business connection/);
        assert.match(body, /<h2>Optional Meta business connection<\/h2>/);
      }
      if (route === "/data-deletion") {
        assert.match(body, /Facebook account sign-in requests/);
        assert.match(body, /Proposed on 27 September 2026 for Owner review; not yet approved for publication/);
        assert.match(body, /Pandora account data deletion request/);
        assert.match(body, /Removing the Facebook identity separately may be unavailable/);
        assert.match(body, /Meta business-connection requests/);
        assert.match(body, /Pandora Meta data deletion request/);
      }
      if (route === "/terms") {
        assert.match(body, /Draft for Owner review\. Not approved or in effect\./);
        assert.match(body, /only your public profile and email for sign-in/);
        assert.match(body, /does not authorize access to Facebook Pages, ad accounts, or business portfolios/);
        assert.match(body, /Facebook sign-in account information or Meta business-connection data/);
      }
      assert.doesNotMatch(body, /main\.dart\.js/, route);
    }
  } finally {
    server.close();
    await once(server, "close");
  }
});
