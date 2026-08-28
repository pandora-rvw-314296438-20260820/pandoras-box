'use strict';
const { requireString } = require('./contracts.js');

function defineFunnel(input) {
  if (!input || !Array.isArray(input.steps) || input.steps.length < 2) throw new TypeError('funnel requires at least two steps');
  return Object.freeze({
    key: requireString(input.key,'funnel.key',160),
    objectiveId: requireString(input.objectiveId,'funnel.objectiveId',160),
    steps: Object.freeze(input.steps.map((step,i)=>requireString(step,`steps[${i}]`,160))),
  });
}
function analyzeFunnel(definition, counts) {
  const steps = definition.steps.map((event, index) => {
    const count = Number(counts[event] ?? 0);
    if (!Number.isFinite(count) || count < 0) throw new TypeError(`invalid count for ${event}`);
    const priorEvent = index === 0 ? null : definition.steps[index - 1];
    const priorCount = priorEvent == null ? count : Number(counts[priorEvent] ?? 0);
    return Object.freeze({ event, count, stepConversion: index === 0 ? 1 : priorCount === 0 ? null : count / priorCount, dropOff: index === 0 ? 0 : Math.max(0, priorCount - count) });
  });
  const first = steps[0].count;
  const last = steps[steps.length - 1].count;
  return Object.freeze({ key:definition.key, entryCount:first, completionCount:last, completionRate:first === 0 ? null : last / first, steps:Object.freeze(steps) });
}
module.exports = { analyzeFunnel, defineFunnel };
