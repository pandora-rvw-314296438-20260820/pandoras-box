"use strict";
const fs=require("node:fs"),path=require("node:path"),test=require("node:test"),assert=require("node:assert/strict");
const root="apps/pandora-mobile/lib";
const tokens=fs.readFileSync(path.join(root,"core/design/pandora_tokens.dart"),"utf8");
const theme=fs.readFileSync(path.join(root,"core/design/pandora_theme.dart"),"utf8");
const nav=fs.readFileSync(path.join(root,"core/widgets/pandora_navigation.dart"),"utf8");
const layer=fs.readFileSync(path.join(root,"app/pandora_conversation_layer.dart"),"utf8");
test("Pandora app theme contains no legacy indigo action colours",()=>{
 const all=[tokens,theme,nav,layer].join("\n");
 assert.doesNotMatch(all,/0xFF7C83FF|0xFF3F51B5/i);
 assert.match(theme,/dialogTheme: DialogThemeData/);
 assert.match(theme,/textButtonTheme: TextButtonThemeData/);
});
test("shared top bar uses a soft fade with no divider edge",()=>{
 assert.match(nav,/pandora-page-header-soft-fade/);
 assert.match(nav,/LinearGradient/);
 assert.match(nav,/background\.withValues\(alpha: 0\)/);
 const header=nav.slice(nav.indexOf("class PandoraPageHeader"),nav.indexOf("class _PandoraMenuGlyph"));
 assert.doesNotMatch(header,/BorderSide|Divider/);
});
test("business content reserves the real compact composer lane",()=>{
 assert.match(layer,/compactComposerHeight = 80/);
 assert.match(layer,/businessBottomInset = compactComposerHeight \+ safeAreaBottom/);
 assert.doesNotMatch(layer,/compactComposerHeight = 68/);
});
