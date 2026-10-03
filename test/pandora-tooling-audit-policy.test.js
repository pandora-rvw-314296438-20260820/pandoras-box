'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');

test('tooling audit policy allows only the exact temporary unfixed braces advisory and its transitive chain', async()=>{
  const {evaluateAuditReport,TEMPORARY_AUDIT_EXCEPTION}=await import('../scripts/audit-tooling-dependencies.mjs');
  const report={vulnerabilities:{
    braces:{severity:'high',via:[{severity:'high',url:TEMPORARY_AUDIT_EXCEPTION.advisory}]},
    micromatch:{severity:'high',via:['braces']},
    'fast-glob':{severity:'high',via:['micromatch']}
  }};
  assert.deepEqual(evaluateAuditReport(report,new Date('2026-10-03T00:00:00Z')).blocked,[]);
});

test('tooling audit policy blocks unrelated high findings and expires the exception', async()=>{
  const {evaluateAuditReport,TEMPORARY_AUDIT_EXCEPTION}=await import('../scripts/audit-tooling-dependencies.mjs');
  const unrelated={vulnerabilities:{other:{severity:'high',via:[{severity:'high',url:'https://github.com/advisories/GHSA-other'}]}}};
  assert.deepEqual(evaluateAuditReport(unrelated,new Date('2026-10-03T00:00:00Z')).blocked,['other']);
  const braces={vulnerabilities:{braces:{severity:'high',via:[{severity:'high',url:TEMPORARY_AUDIT_EXCEPTION.advisory}]}}};
  assert.deepEqual(evaluateAuditReport(braces,new Date('2026-10-18T00:00:00Z')).blocked,['braces']);
});
