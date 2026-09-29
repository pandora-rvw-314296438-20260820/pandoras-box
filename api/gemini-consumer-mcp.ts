import {
  createPandoraMcpHandler,
  pandoraMcpVercelConfig,
} from '../src/pandora-mcp-handler.js';

const GEMINI_CONSUMER_PROVIDER_TOOLS = new Set([
  // GitHub: same bounded repository capabilities as Pandora's existing Gemini worker surface.
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

  // Supabase: reads plus governed mutations. Delete operations stay unexposed initially.
  'supabase.list-accounts',
  'supabase.list-organizations',
  'supabase.list-projects',
  'supabase.get-project',
  'supabase.get-auth-security-config',
  'supabase.enable-leaked-password-protection',
  'supabase.pause-project',
  'supabase.restore-project',
  'supabase.read-project-api',
  'supabase.write-project-api',
  'supabase.read-organization-api',
  'supabase.write-organization-api',
  'supabase.read-branch-api',
  'supabase.write-branch-api',
]);

const GEMINI_CONSUMER_CONTROL_TOOLS = new Set([
  'pandora_tool_catalog',
  'pandora_capability_catalog',
  'pandora_capability_search',
  'pandora_capability_readiness',
  'pandora_skill_catalog',
  'pandora_skill_route',
  'pandora_skill_load',
  'pandora_list_plans',
  'pandora_list_audit',
  'pandora_verify_audit',
  'pandora_create_plan',
  // Deliberately no pandora_approve_plan: consumer Gemini cannot self-approve.
  'pandora_execute_plan',
]);

export const config = pandoraMcpVercelConfig;

export default createPandoraMcpHandler({
  allowedToolNames: GEMINI_CONSUMER_PROVIDER_TOOLS,
  allowedControlToolNames: GEMINI_CONSUMER_CONTROL_TOOLS,
  resourcePath: '/gemini-consumer-mcp',
  resourceMetadataPath:
    '/.well-known/oauth-protected-resource/gemini-consumer-mcp',
  metadataSelector: 'gemini-consumer-mcp',
  resourceName: 'Pandora for Gemini',
  // Supabase OAuth discovery currently advertises standard OIDC scopes only.
  // Pandora authorization remains enforced by this route's control/provider
  // allowlists, membership checks, durable-plan gates, and provider scoping.
  oauthScopes: [
    'openid',
    'email',
    'profile',
  ],
});
