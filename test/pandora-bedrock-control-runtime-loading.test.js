"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const source=fs.readFileSync("api/operations-inference.ts","utf8");
test("operations inference lazily loads ESM runtime after Bedrock control short-circuit",()=>{
 assert.doesNotMatch(source,/^import \{createVercelInferenceRuntime\} from .*vercel-runtime\.mjs/m);
 assert.match(source,/if\(operation==='bedrock-control'\) return await handleBedrockModelControl\(req,res\);/);
 assert.match(source,/const \{createVercelInferenceRuntime\}=await import\('\.\.\/packages\/pandora-operations-inference\/vercel-runtime\.mjs'\);/);
 const shortCircuit=source.indexOf("if(operation==='bedrock-control')");
 const lazyImport=source.indexOf("await import('../packages/pandora-operations-inference/vercel-runtime.mjs')");
 assert.ok(shortCircuit>=0&&lazyImport>shortCircuit);
});
