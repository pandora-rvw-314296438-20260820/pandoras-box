import {
  createPandoraMcpHandler,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';
import { GitHubConnectResolver } from '../src/runtime/github-connect-resolver.js';
import { buildToolConfiguration } from '../src/runtime/service-config.js';
import { toolRegistry } from '../src/tools/index.js';

const CONNECTOR_UID = 'github/pandora';
const INSTALLATION_ID = '158056492';
const CANONICAL_REPOSITORY = 'pandora-rvw-314296438-20260820/pandoras-box';
const CANONICAL_LOGIN = 'pandora-rvw-314296438-20260820';
const ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const WORKER_IDENTITY_URL =
  'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control/gemini-worker/identity';
const WORKER_PRINCIPAL = 'vercel:mbanatao:mcpmaster:development:gemini-worker';

const GEMINI_GITHUB_TOOLS = new Set([
  'github.get-repository',
  'github.get-issue',
  'github.list-issues',
  'github.create-issue',
  'github.update-issue',
  'github.get-pull-request',
  'github.list-pull-requests',
  'github.create-pull-request',
  'github.merge-pull-request',
  'github.list-workflow-runs',
  'github.get-workflow-run',
  'github.read-repository-api',
  'github.write-repository-api',
]);

function bearerValue(value: unknown) {
  const header = typeof value === 'string'
    ? value
    : Array.isArray(value) && typeof value[0] === 'string'
    ? value[0]
    : '';
  const match = header.match(/^Bearer\s+([A-Za-z0-9._~-]{80,4096})$/);
  return match?.[1] || '';
}

class GeminiWorkerAuthenticator {
  async authenticate(authorization: unknown) {
    const token = bearerValue(authorization);
    if (!token) throw Object.assign(new Error('Gemini worker identity is required'), { status: 401 });

    let response: Response;
    try {
      response = await fetch(WORKER_IDENTITY_URL, {
        method: 'GET',
        headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
        redirect: 'error',
        signal: AbortSignal.timeout(8_000),
      });
    } catch {
      throw Object.assign(new Error('Gemini worker identity verification failed'), { status: 503 });
    }

    const text = await response.text();
    if (Buffer.byteLength(text, 'utf8') > 16_384) {
      throw Object.assign(new Error('Gemini worker identity response is invalid'), { status: 503 });
    }

    let payload: any;
    try { payload = JSON.parse(text); } catch { payload = null; }
    if (
      !response.ok
      || payload?.ok !== true
      || payload?.principalId !== WORKER_PRINCIPAL
      || payload?.project !== 'mcpmaster'
      || payload?.projectId !== 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
      || payload?.owner !== 'mbanatao'
      || payload?.ownerId !== 'team_3yw1CN59ce4pj5SwyQGCAqN3'
      || payload?.environment !== 'development'
      || !Number.isFinite(Date.parse(String(payload?.expiresAt || '')))
      || Date.parse(String(payload.expiresAt)) <= Date.now()
    ) {
      throw Object.assign(new Error('Gemini worker identity is not authorized'), { status: 401 });
    }

    return {
      userId: WORKER_PRINCIPAL,
      accessToken: token,
      scopes: ['openid', 'pandora:read', 'pandora:plan', 'pandora:execute'],
      scopeClaimsPresent: true,
      aal: 'workload',
    };
  }
}

class GeminiWorkerMembershipResolver {
  async resolve(organizationId: string, userId: string, accessToken: string) {
    if (
      organizationId !== ORGANIZATION_ID
      || userId !== WORKER_PRINCIPAL
      || typeof accessToken !== 'string'
      || accessToken.length < 80
    ) return null;
    return {
      organizationId: ORGANIZATION_ID,
      userId: WORKER_PRINCIPAL,
      role: 'operator',
    };
  }
}

const githubConnect = new GitHubConnectResolver();

async function geminiToolConfiguration(
  toolName: string,
  context: { vercelOidcToken?: string } = {},
) {
  const definition = toolRegistry[toolName];
  if (!definition || definition.handler !== 'github') {
    return buildToolConfiguration(toolName, context);
  }
  if (!GEMINI_GITHUB_TOOLS.has(toolName)) {
    throw new Error('GitHub tool is not available on the Gemini MCP surface');
  }
  const oidcToken = context.vercelOidcToken?.trim()
    || process.env.VERCEL_OIDC_TOKEN?.trim();
  return {
    github: await githubConnect.resolve(oidcToken, {
      connectorUid: CONNECTOR_UID,
      installationId: INSTALLATION_ID,
      accountId: 'github-primary',
      label: 'Pandora GitHub via Vercel Connect',
      login: CANONICAL_LOGIN,
      allowMutations: true,
      allowedRepositories: [CANONICAL_REPOSITORY],
      grantedScopes: definition.manifest.requiredProviderScopes,
      requiredProviderScopes: definition.manifest.requiredProviderScopes,
      toolName,
    }),
  };
}

const workerAuthenticator = new GeminiWorkerAuthenticator();
const workerMembership = new GeminiWorkerMembershipResolver();

export const config = pandoraMcpVercelConfig;
export default createPandoraMcpHandler({
  allowedToolNames: GEMINI_GITHUB_TOOLS,
  authenticator: workerAuthenticator,
  membershipResolver: workerMembership,
  canExecutePlan: (actor: any) =>
    actor?.membership?.role === 'operator'
    && actor?.identity?.userId === WORKER_PRINCIPAL,
  toolConfiguration: geminiToolConfiguration,
});
