"use strict";

class MemoryLineageSink {
  constructor() { this.durability = "memory"; this.events = []; }
  async record(event) { this.events.push(structuredClone(event)); }
  list() { return structuredClone(this.events); }
}

async function recordLineage(sink, kind, payload) {
  if (!sink) return;
  await sink.record({ kind, at: new Date().toISOString(), ...payload });
}

module.exports = { MemoryLineageSink, recordLineage };
