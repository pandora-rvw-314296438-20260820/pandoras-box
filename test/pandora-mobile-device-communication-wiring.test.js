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
  const parse = ask.search(
    /PandoraDeviceCommunicationCommand\.tryParse\(\s*objective\s*,?\s*\)/,
  );
  const cloud = ask.indexOf("final execution = await intelligence.startChatExecution(");
  assert.ok(parse >= 0, "device communication pre-router missing");
  assert.ok(cloud > parse, "device communication must be resolved before model chat");
  assert.match(ask, /_communications\.open\(/);
  assert.match(ask, /userConfirmationRequired/);
});

test("named recipients resolve only through bounded system contact selection", () => {
  assert.match(command, /recipientIsBounded/);
  assert.match(ask, /PandoraNativeIo\.pickPhoneContact\(\)/);
  assert.match(ask, /userConfirmationRequired/);
  assert.match(ask, /No call was placed|No message was sent/);
  assert.doesNotMatch(ask, /Calling .* now/);
  assert.doesNotMatch(ask, /sendDirect|placeCallDirect/);
});
