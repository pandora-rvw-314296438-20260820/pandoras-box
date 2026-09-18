'use strict';
const test=require('node:test'); const assert=require('node:assert/strict'); const fs=require('node:fs');
const read=p=>fs.readFileSync(p,'utf8');
test('active entrypoints are Pandora-native',()=>{ for(const p of ['api/mcp.ts','vercel-entrypoint.js','src/container-entrypoint.js','Dockerfile']){const s=read(p); assert.doesNotMatch(s,/projectos-mcp-handler|projectos-container-server|MCPMASTER_CONTAINER_MODE=projectos/i,p);}});
test('skill mutation authority belongs to Pandora Runtime Tool Gateway',()=>{const s=read('.agents/runtime/pandora-skill-runtime.mjs'); assert.match(s,/pandora-runtime-tool-gateway/); assert.doesNotMatch(s,/projectos-governed/);});
test('legacy ProjectOS implementation remains rollback-only and is not an active import',()=>{assert.equal(fs.existsSync('src/projectos-mcp-handler.js'),true); assert.equal(fs.existsSync('src/projectos-container-server.js'),true);});
