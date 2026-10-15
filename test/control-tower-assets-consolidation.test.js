'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const tower = path.join(root, 'apps/control-tower');
const read = (name) => fs.readFileSync(path.join(tower, name), 'utf8');

test('numbered CSS overrides are removed after flattening into canonical stylesheets', () => {
  const index = read('index.html');
  const first = read('owner-first.css');
  const components = read('owner-components.css');
  const tokens = read('owner-design-system.css');
  for (const name of ['owner-first-2.css','owner-first-3.css','owner-first-4.css','owner-components-2.css','owner-components-3.css','owner-components-4.css']) {
    assert.equal(fs.existsSync(path.join(tower, name)), false, 'obsolete stylesheet remains: ' + name);
    assert.equal(index.includes(name), false, 'index still links a numbered stylesheet: ' + name);
  }
  assert.ok(first.includes('.owner-brand-copy strong'));
  assert.ok(first.includes('.owner-decision-meta'));
  assert.ok(first.includes('.owner-activity-copy'));
  assert.ok(components.includes('.owner-bottom-nav'));
  assert.ok(components.includes('.owner-detail-list'));
  assert.ok(components.includes('.owner-skeleton'));
  assert.ok(tokens.includes(':root'));
  assert.ok(tokens.includes('--owner-bg:'));
  assert.ok(index.includes('owner-first.css?v=control-tower-esm-v1-20261015-1'));
  assert.ok(index.includes('owner-components.css?v=control-tower-esm-v1-20261015-1'));
});

test('the owner app is the sole application entrypoint', () => {
  for (const name of ['app.js','owner-first.js','owner-screens.js','simple-language.js']) {
    assert.equal(fs.existsSync(path.join(tower, name)), false, 'retired entrypoint remains: ' + name);
  }
  const bootstrap = read('bootstrap.js');
  const index = read('index.html');
  const app = read('owner-app.js');
  assert.ok(bootstrap.includes('owner-app.js'));
  assert.ok(!bootstrap.includes('owner-first.js'));
  assert.ok(!bootstrap.includes('/control-tower/app.js'));
  assert.ok(!index.includes('data-advanced-script-order'));
  assert.ok(!index.includes('/control-tower/app.js'));
  assert.ok(index.includes('bootstrap.js?v=control-tower-esm-v1-20261015-1'));
  assert.ok(!app.includes('window.PandorasOwnerScreens'));
  assert.ok(!app.includes('window.PandorasOwnerDialogs'));
  assert.ok(!app.includes('window.PandorasOwnerProjectWorkspace'));
});

test('screens are named ES module exports consumed by the canonical router', () => {
  const app = read('owner-app.js');
  const modules = [
    ['owner-screens-core.js','export const ownerScreenCore'],
    ['owner-screens-activity.js','export const ownerScreenActivity'],
    ['owner-screens-more.js','export const ownerScreenMore'],
    ['owner-screens-experience.js','export const ownerScreenExperience'],
    ['owner-project-workspace.js','export const ownerProjectWorkspace'],
    ['owner-professional.js','export const ownerProfessionalScreens'],
    ['owner-dialogs.js','export const ownerDialogs'],
  ];
  for (const [file, exportDeclaration] of modules) {
    assert.ok(read(file).includes(exportDeclaration), file + ' must export a named module surface');
    assert.ok(app.includes(file + '?v=control-tower-esm-v1-20261015-1'), file + ' must be imported by owner-app');
  }
});
