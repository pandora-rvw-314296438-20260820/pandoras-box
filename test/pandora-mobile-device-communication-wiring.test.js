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
const adapters = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "features", "simple", "chat", "pandora_chat_action_adapters.dart"),
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
  const route = ask.indexOf("await _executeLocalRoute(dispatch, input, dependencies)");
  const cloud = ask.indexOf("intelligence.executeChatTurn(dispatch)", route);
  assert.ok(route >= 0, "native action adapter is not called");
  assert.ok(cloud > route, "device communication must be resolved before model chat");
  assert.match(ask.slice(route, cloud), /if \(handled \|\| !_current\(token\)\) return;/);
  assert.match(ask, /part 'chat\/pandora_chat_action_adapters\.dart'/);
  assert.match(adapters, /PandoraDeviceCommunicationCommand\.tryParse\(dispatch\.message\)/);
  assert.match(adapters, /await _executeCommunication\(dispatch, communication, dependencies\)/);

  const start = adapters.indexOf("Future<String> _executeCommunication(");
  const end = adapters.indexOf("Future<String?> _executeProjectHandoff(", start);
  assert.ok(start >= 0 && end > start, "communication execution adapter missing");
  const communication = adapters.slice(start, end);
  assert.match(communication, /final operationId = dispatch\.token\.attemptId;/);
  assert.match(communication, /PandoraCommunicationActionExecutor\(/);
  assert.match(communication, /startDeviceActivity\([\s\S]*?requestId: operationId/);
  assert.match(communication, /recordDeviceActivity\([\s\S]*?operationId: operationId/);
  assert.match(communication, /beforeEffect: \(\) => _beginEffect\(dispatch, 'device'\)/);
  assert.match(communication, /final result = await executor\.execute\(command, operationId: operationId\);/);
  assert.doesNotMatch(communication, /if \(!_beginEffect\(dispatch, 'device'\)\)/);
  assert.match(communication, /if \(result\.outcomeUnknown\)\s*\{[\s\S]*?recoverable: false, outcomeUnknown: true/);
  assert.match(communication, /return result\.reply;/);
  assert.match(executor, /_communications\.executeDirect\(request\)/);
  assert.match(executor, /if \(_beforeEffect\?\.call\(\) == false\) return await _cancelled\(capability\);\s*result = await _communications\.executeDirect\(request\)/);
  assert.match(executor, /if \(_beforeEffect\?\.call\(\) == false\) return await _cancelled\(capability\);\s*final handoff = await _communications\.open\(request\)/);
  assert.match(executor, /authorizedByCurrentIntent: true/);
  assert.match(executor, /_communications\.getDirectStatus\(operationId\)/);
  assert.match(executor, /outcomeUnknown: true/);
});

test("named recipients resolve only through bounded Android Contacts evidence", () => {
  assert.match(command, /recipientIsBounded/);
  assert.match(executor, /_contacts\.resolve\(requestedRecipient\)/);
  assert.match(contacts, /'resolvePhoneContact'/);
  assert.match(contacts, /source != 'android_contacts'/);
  assert.match(contacts, /android\.permission\.READ_CONTACTS/);
  assert.match(executor, /PandoraContactResolutionStatus\.ambiguous/);
  assert.match(executor, /'needs_choice'/);
  assert.doesNotMatch(ask + adapters, /sendDirect|placeCallDirect/);
});
