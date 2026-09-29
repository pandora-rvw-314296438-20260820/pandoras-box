import {
  handlePandoraMcp,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';
import { handleGeminiConsumerMcp } from '../src/gemini-consumer-mcp-handler.js';

function requestUrl(request: any) {
  const value =
    typeof request?.originalUrl === 'string'
      ? request.originalUrl
      : typeof request?.url === 'string'
      ? request.url
      : '/';
  try {
    return new URL(value, 'https://mcpmaster.vercel.app');
  } catch {
    return new URL('/', 'https://mcpmaster.vercel.app');
  }
}

function isGeminiConsumerRequest(request: any) {
  const url = requestUrl(request);
  return url.searchParams.get('surface') === 'gemini-consumer'
    || url.searchParams.get('metadata') === 'gemini-consumer-mcp';
}

export const config = pandoraMcpVercelConfig;

export default function handleMcp(request: any, response: any) {
  return isGeminiConsumerRequest(request)
    ? handleGeminiConsumerMcp(request, response)
    : handlePandoraMcp(request, response);
}
