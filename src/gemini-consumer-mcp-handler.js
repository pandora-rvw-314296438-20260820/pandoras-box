"use strict";

const { createPandoraMcpHandler } = require("./pandora-mcp-handler.js");
const { buildToolConfiguration } = require("./runtime/service-config.js");
const { toolRegistry } = require("./tools/index.js");

const CANONICAL_REPOSITORY =
    "pandora-rvw-314296438-20260820/pandoras-box";
const CANONICAL_SUPABASE_ACCOUNT = "pandoras-box";
const CANONICAL_SUPABASE_PROJECT_REF = "jcyqixttuebxqqfkjonq";

const GEMINI_CONSUMER_PROVIDER_TOOLS = new Set([
    // GitHub: same bounded repository capabilities as Pandora's existing Gemini worker surface.
    "github.get-repository",
    "github.get-issue",
    "github.list-issues",
    "github.create-issue",
    "github.update-issue",
    "github.get-pull-request",
    "github.list-pull-requests",
    "github.create-pull-request",
    "github.merge-pull-request",
    "github.list-workflow-runs",
    "github.get-workflow-run",
    "github.read-repository-api",
    "github.write-repository-api",

    // Supabase: reads plus governed mutations. Delete operations stay unexposed initially.
    "supabase.list-accounts",
    "supabase.list-projects",
    "supabase.get-project",
    "supabase.get-auth-security-config",
    "supabase.enable-leaked-password-protection",
    "supabase.pause-project",
    "supabase.restore-project",
    "supabase.read-project-api",
    "supabase.write-project-api",
    "supabase.read-branch-api",
    "supabase.write-branch-api",
]);

const GEMINI_CONSUMER_CONTROL_TOOLS = new Set([
    "pandora_tool_catalog",
    "pandora_capability_catalog",
    "pandora_capability_search",
    "pandora_capability_readiness",
    "pandora_skill_catalog",
    "pandora_skill_route",
    "pandora_skill_load",
    "pandora_list_plans",
    "pandora_list_audit",
    "pandora_verify_audit",
    "pandora_create_plan",
    // Deliberately no pandora_approve_plan: consumer Gemini cannot self-approve.
    "pandora_execute_plan",
]);

async function geminiConsumerToolConfiguration(toolName, context = {}) {
    const configuration = await buildToolConfiguration(toolName, context);
    const definition = toolRegistry[toolName];

    if (definition?.handler === "github") {
        const github = configuration.github;
        if (!github?.allowedRepositories?.includes(CANONICAL_REPOSITORY)) {
            throw new Error("Canonical Pandora GitHub repository is unavailable");
        }
        return {
            github: {
                ...github,
                allowedRepositories: [CANONICAL_REPOSITORY],
            },
        };
    }

    if (toolName.startsWith("supabase.")) {
        const supabase = configuration.supabase;
        const account = supabase?.accounts?.find(
            (candidate) => candidate.id === CANONICAL_SUPABASE_ACCOUNT,
        );
        if (!account?.allowedProjectRefs?.includes(CANONICAL_SUPABASE_PROJECT_REF)) {
            throw new Error("Canonical Pandora Supabase project is unavailable");
        }
        return {
            supabase: {
                ...supabase,
                accounts: [{
                    ...account,
                    allowedOrganizationSlugs: [],
                    allowedProjectRefs: [CANONICAL_SUPABASE_PROJECT_REF],
                }],
            },
        };
    }

    return configuration;
}

const handleGeminiConsumerMcp = createPandoraMcpHandler({
    allowedToolNames: GEMINI_CONSUMER_PROVIDER_TOOLS,
    allowedControlToolNames: GEMINI_CONSUMER_CONTROL_TOOLS,
    allowedMembershipRoles: new Set(["owner"]),
    resourcePath: "/gemini-consumer-mcp",
    resourceMetadataPath:
        "/.well-known/oauth-protected-resource/gemini-consumer-mcp",
    metadataSelector: "gemini-consumer-mcp",
    resourceName: "Pandora for Gemini",
    toolConfiguration: geminiConsumerToolConfiguration,
    // Supabase OAuth discovery currently advertises standard OIDC scopes only.
    // Pandora authorization remains enforced by this route's control/provider
    // allowlists, membership checks, durable-plan gates, and provider scoping.
    oauthScopes: [
        "openid",
        "email",
        "profile",
    ],
});

module.exports = {
    handleGeminiConsumerMcp,
};
