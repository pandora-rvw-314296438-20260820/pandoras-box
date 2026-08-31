const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const mobile = join(root, 'apps', 'pandora-mobile');
const platform = join(mobile, 'lib', 'core', 'platform');
const host = readFileSync(join(platform, 'pandora_preview_host.dart'), 'utf8');
const ios = readFileSync(join(platform, 'pandora_ios_preview.dart'), 'utf8');
const desktop = readFileSync(join(platform, 'pandora_desktop_preview.dart'), 'utf8');
const webFacade = readFileSync(join(platform, 'pandora_web_preview.dart'), 'utf8');
const web = readFileSync(join(platform, 'pandora_web_preview_web.dart'), 'utf8');
const swift = readFileSync(join(mobile, 'platform', 'ios', 'Runner', 'PandoraExactPreviewView.swift'), 'utf8');
const appDelegate = readFileSync(join(mobile, 'platform', 'ios', 'Runner', 'AppDelegate.swift'), 'utf8');

const forbiddenBridge = /WKScriptMessageHandler|addJavascriptInterface|javaScriptChannel|allow-same-origin/;

test('PandoraPreviewHost dispatches behind one exact-version platform boundary', () => {
  assert.match(host, /PandoraAndroidPreview\.isSupported/);
  assert.match(host, /PandoraIosPreview\.isSupported/);
  assert.match(host, /PandoraWebPreview\.isSupported/);
  assert.match(host, /PandoraDesktopPreview\(/);
  assert.match(host, /files\.isEmpty \|\| versionId\.trim\(\)\.isEmpty/);
  assert.doesNotMatch(host, /AndroidView\(|UiKitView\(|HtmlElementView\(/);
});

test('iOS exact preview uses WKWebView without a project JavaScript bridge', () => {
  assert.match(ios, /UiKitView\(/);
  assert.match(ios, /pandora\/exact_preview/);
  assert.match(swift, /WKWebView/);
  assert.match(swift, /WKURLSchemeHandler/);
  assert.match(swift, /pandora-preview/);
  assert.match(swift, /websiteDataStore = \.nonPersistent\(\)/);
  assert.match(swift, /UITapGestureRecognizer/);
  assert.match(swift, /elementFromPoint/);
  assert.match(swift, /evaluateJavaScript/);
  assert.match(swift, /data-pandora-source-file/);
  assert.match(swift, /versionId/);
  assert.doesNotMatch(swift, forbiddenBridge);
  assert.match(appDelegate, /register\(/);
  assert.match(appDelegate, /withId: "pandora\/exact_preview"/);
});

test('web exact preview is opaque, network-denied, and uses an unforgeable transferred port', () => {
  assert.match(webFacade, /dart\.library\.html/);
  assert.match(web, /HtmlElementView\(/);
  assert.match(web, /setAttribute\('sandbox', 'allow-scripts'\)/);
  assert.match(web, /MessageChannel\(\)/);
  assert.match(web, /event\.isTrusted/);
  assert.match(web, /event\.stopImmediatePropagation\(\)/);
  assert.match(web, /event\.ports/);
  assert.match(web, /versionId/);
  assert.match(web, /default-src 'none'/);
  assert.match(web, /connect-src 'none'/);
  assert.match(web, /frame-src 'none'/);
  assert.match(web, /form-action 'none'/);
  assert.match(web, /_maxBundleBytes = 12 \* 1024 \* 1024/);
  assert.doesNotMatch(web, forbiddenBridge);
  assert.doesNotMatch(web, /window\.parent\.postMessage|parent\.postMessage/);
});

test('desktop stays fail-closed instead of substituting an unrelated URL', () => {
  assert.match(desktop, /static bool get isSupported => false/);
  assert.match(desktop, /Widget build\(BuildContext context\) => fallback/);
  assert.doesNotMatch(desktop, /url_launcher|http:|https:|WebView/);
});
