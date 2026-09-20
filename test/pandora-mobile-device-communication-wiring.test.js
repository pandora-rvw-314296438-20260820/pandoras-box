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
const executor = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "device", "pandora_communication_action_executor.dart"),
  "utf8",
);
const contacts = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "device", "pandora_contacts.dart"),
  "utf8",
);

test("Ask Pandora dispatches explicit device communications before model chat", () => {
  const parse = ask.search(
    /PandoraDeviceCommunicationCommand\.tryParse\(\s*objective\s*,?\s*\)/,
  );
  const cloud = ask.indexOf("final execution = await intelligence.startChatExecution(");
  assert.ok(parse >= 0, "device communication pre-router missing");
  assert.ok(cloud > parse, "device communication must be resolved before model chat");
  assert.match(ask, /PandoraCommunicationActionExecutor\(/);
  assert.match(ask, /final result = await executor\.execute\(/);
  assert.match(executor, /_communications\.executeDirect\(request\)/);
  assert.match(executor, /authorizedByCurrentIntent: true/);
});

test("named recipients resolve only through bounded Android Contacts evidence", () => {
  assert.match(command, /recipientIsBounded/);
  assert.match(executor, /_contacts\.resolve\(requestedRecipient\)/);
  assert.match(contacts, /'resolvePhoneContact'/);
  assert.match(contacts, /source != 'android_contacts'/);
  assert.match(contacts, /android\.permission\.READ_CONTACTS/);
  assert.match(executor, /PandoraContactResolutionStatus\.ambiguous/);
  assert.match(executor, /'needs_choice'/);
  assert.doesNotMatch(ask, /sendDirect|placeCallDirect/);
});
