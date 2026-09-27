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

export const config = pandoraMcpVercelConfig;
export default createPandoraMcpHandler({
  allowedToolNames: GEMINI_GITHUB_TOOLS,
  toolConfiguration: geminiToolConfiguration,
});
