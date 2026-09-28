// Vercel trace anchor: keep the canonical skill runtime in the MCP function bundle.
import '../.agents/runtime/pandora-skill-runtime.mjs';
import {
  handlePandoraMcp,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';

export const config = pandoraMcpVercelConfig;
export default handlePandoraMcp;
