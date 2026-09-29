import {
  createPandoraMcpHandler,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';
import { GitHubConnectResolver } from '../src/runtime/github-connect-resolver.js';
import { buildToolConfiguration } from '../src/runtime/service-config.js';
import { toolRegistry } from '../src/tools/index.js';
import { loadOperatorPublicConfig } from '../src/operator-public-config.js';
import {
  SupabaseOrganizationMembershipResolver,
} from '../apps/meta-business-mcp/src/auth/membership.js';

const CONNECTOR_UID = 'github/pandora';
const INSTALLATION_ID = '158056492';
const CANONICAL_REPOSITORY = 'pandora-rvw-314296438-20260820/pandoras-box';
const CANONICAL_LOGIN = 'pandora-rvw-314296438-20260820';
const CONSUMER_RESOURCE_PATH = '/api/gemini-consumer-mcp';
const CONSUMER_OAUTH_SCOPES = Object.freeze(['openid', 'email', 'profile']);

const GEMINI_CONSUMER_TOOLS = new Set([
  // Existing canonical GitHub access.
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

  // Supabase reads plus governed, non-delete writes.
  'supabase.list-accounts',
  'supabase.list-organizations',
  'supabase.list-projects',
  'supabase.get-project',
  'supabase.get-auth-security-config',
  'supabase.read-project-api',
  'supabase.read-organization-api',
  'supabase.read-branch-api',
  'supabase.enable-leaked-password-protection',
  'supabase.restore-project',
  'supabase.write-project-api',
  'supabase.write-organization-api',
  'supabase.write-branch-api',
]);

const operatorConfig = loadOperatorPublicConfig();
const baseMembership = new SupabaseOrganizationMembershipResolver({
  supabaseUrl: operatorConfig.supabaseUrl,
  publishableKey: operatorConfig.supabasePublishableKey,
});

class GeminiConsumerMembershipResolver {
  async resolve(organizationId: string, userId: string, accessToken: string) {
    const membership = await baseMembership.resolve(organizationId, userId, accessToken);
    if (!membership || !['owner', 'admin', 'operator'].includes(membership.role)) {
      return null;
    }
    // Consumer Gemini is an additional operator access path. It may never inherit
    // owner/admin approval authority from the signed-in human account.
    return {
      ...membership,
      role: 'operator',
    };
  }
}

const githubConnect = new GitHubConnectResolver();

async function consumerToolConfiguration(
  toolName: string,
  context: { vercelOidcToken?: string } = {},
) {
  const definition = toolRegistry[toolName];
  if (!definition || definition.handler !== 'github') {
    return buildToolConfiguration(toolName, context);
  }
  if (!GEMINI_CONSUMER_TOOLS.has(toolName)) {
    throw new Error('GitHub tool is not available on the consumer Gemini MCP surface');
  }
  const oidcToken = context.vercelOidcToken?.trim()
    || process.env.VERCEL_OIDC_TOKEN?.trim();
  return {
    github: await githubConnect.resolve(oidcToken, {
      connectorUid: CONNECTOR_UID,
      installationId: INSTALLATION_ID,
      accountId: 'github-primary',
      label: 'Pandora GitHub via consumer Gemini',
      login: CANONICAL_LOGIN,
      allowMutations: true,
      allowedRepositories: [CANONICAL_REPOSITORY],
      grantedScopes: definition.manifest.requiredProviderScopes,
      requiredProviderScopes: definition.manifest.requiredProviderScopes,
      toolName,
    }),
  };
}

const consumerMembership = new GeminiConsumerMembershipResolver();
const resourceOrigin =
  process.env.PANDORA_MCP_RESOURCE_ORIGIN?.trim() || 'https://mcpmaster.vercel.app';

export const config = pandoraMcpVercelConfig;
export default createPandoraMcpHandler({
  allowedToolNames: GEMINI_CONSUMER_TOOLS,
  membershipResolver: consumerMembership,
  canExecutePlan: (actor: any) => actor?.membership?.role === 'operator',
  toolConfiguration: consumerToolConfiguration,
  resourceOrigin,
  resourcePath: CONSUMER_RESOURCE_PATH,
  resourceName: "Pandora's Box — Consumer Gemini",
  resourceMetadataUrl: `${resourceOrigin}${CONSUMER_RESOURCE_PATH}?metadata=mcp`,
  oauthScopes: CONSUMER_OAUTH_SCOPES,
  allowedOrigins: [
    ...new Set([...operatorConfig.allowedOrigins, 'https://gemini.google.com']),
  ],
});
