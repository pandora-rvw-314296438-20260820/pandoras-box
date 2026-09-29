import {
  handlePandoraMcp,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';
import {
  handleGeminiConsumerMcp,
} from '../src/gemini-consumer-mcp-handler.js';

function requestTargetsConsumerGemini(request: any) {
  const rawValues = [request?.originalUrl, request?.url]
    .filter((value) => typeof value === 'string' && value.length > 0);

  return rawValues.some((raw) => {
    let url: URL;
    try {
      url = new URL(raw, 'https://mcpmaster.vercel.app');
    } catch {
      return false;
    }
    return url.pathname === '/gemini-consumer-mcp'
      || url.pathname === '/.well-known/oauth-protected-resource/gemini-consumer-mcp'
      || url.searchParams.get('surface') === 'gemini-consumer'
      || url.searchParams.get('metadata') === 'gemini-consumer-mcp';
  });
}

export const config = pandoraMcpVercelConfig;
export default function handleMcpRequest(request: any, response: any) {
  if (requestTargetsConsumerGemini(request)) {
    return handleGeminiConsumerMcp(request, response);
  }
  return handlePandoraMcp(request, response);
}
