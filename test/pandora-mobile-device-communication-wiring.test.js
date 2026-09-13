"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const ask = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "features", "simple", "ask_pandora_screen.dart"),
  "utf8",
);
const command = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "device", "pandora_communication_command.dart"),
  "utf8",
);

test("Ask Pandora dispatches explicit device communications before model chat", () => {
  const parse = ask.indexOf("PandoraDeviceCommunicationCommand.tryParse(objective)");
  const cloud = ask.indexOf("final turn = await intelligence.chat(");
  assert.ok(parse >= 0, "device communication pre-router missing");
  assert.ok(cloud > parse, "device communication must be resolved before model chat");
  assert.match(ask, /_communications\.open\(/);
  assert.match(ask, /userConfirmationRequired/);
});

test("named recipients fail closed instead of fabricating execution", () => {
  assert.match(command, /recipientIsBounded/);
  assert.match(ask, /need .*phone number/i);
  assert.match(ask, /No call was placed|No message was sent/);
  assert.doesNotMatch(ask, /Calling .* now/);
});
