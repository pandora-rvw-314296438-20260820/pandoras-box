"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.githubTools = exports.GitHubMCPServer = void 0;
exports.executeGitHubTool = executeGitHubTool;
const zod_1 = require("zod");
// GitHub MCP Server Integration
// Provides tools for interacting with GitHub repositories, issues, pull requests, and actions
const GitHubConfigSchema = zod_1.z.object({
    token: zod_1.z.string().min(1, 'GitHub token is required'),
    baseUrl: zod_1.z.string().default('https://api.github.com'),
    owner: zod_1.z.string().optional(),
    repo: zod_1.z.string().optional()
});
// GitHub returns JSON `null` — not an absent key — wherever its OpenAPI
// description declares a value nullable. Each field below is matched to the
// exact schema the endpoint returns: `full-repository` for a single
// repository, `issue`, and `pull-request`. Nullability differs between those
// and their list-endpoint counterparts, so the variant matters.
//
// A bare `.optional()` accepts only `undefined` and rejects `null`, which
// fails the whole read for an otherwise healthy resource. Normalize `null` to
// `undefined` so the parsed contract callers rely on stays `T | undefined`
// rather than widening to `T | null`.
const nullableToUndefined = (schema) => schema.nullish().transform((value) => value ?? undefined);
const optionalString = () => nullableToUndefined(zod_1.z.string());
const optionalBoolean = () => nullableToUndefined(zod_1.z.boolean());
// GitHub's `simple-user`.
const GitHubSimpleUserSchema = zod_1.z.object({
    id: zod_1.z.number(),
    login: zod_1.z.string(),
    avatar_url: zod_1.z.string()
});
// GitHub's issue `labels` is OneOf<[string, object]>, and every property of
// the object form is optional with `name` and `color` nullable.
const GitHubIssueLabelSchema = zod_1.z.union([
    zod_1.z.string(),
    zod_1.z.object({
        id: zod_1.z.number().optional(),
        name: optionalString(),
        color: optionalString()
    })
]);
const GitHubRepositorySchema = zod_1.z.object({
    id: zod_1.z.number(),
    name: zod_1.z.string(),
    full_name: zod_1.z.string(),
    description: optionalString(),
    html_url: zod_1.z.string(),
    clone_url: zod_1.z.string(),
    ssh_url: zod_1.z.string(),
    language: optionalString(),
    stargazers_count: zod_1.z.number(),
    forks_count: zod_1.z.number(),
    open_issues_count: zod_1.z.number(),
    // `full-repository` declares these non-nullable. Only the list-endpoint
    // `minimal-repository` variant makes them `string | null`, and this reader
    // never parses that variant.
    created_at: zod_1.z.string(),
    updated_at: zod_1.z.string(),
    default_branch: zod_1.z.string(),
    private: zod_1.z.boolean(),
    archived: zod_1.z.boolean(),
    disabled: zod_1.z.boolean()
});
const GitHubIssueSchema = zod_1.z.object({
    id: zod_1.z.number(),
    number: zod_1.z.number(),
    title: zod_1.z.string(),
    body: optionalString(),
    state: zod_1.z.enum(['open', 'closed']),
    labels: zod_1.z.array(GitHubIssueLabelSchema),
    // `assignees?: simple-user[] | null` — optional and nullable.
    assignees: nullableToUndefined(zod_1.z.array(GitHubSimpleUserSchema)),
    // Only the issue schema uses `nullable-simple-user`; the author may be a
    // deleted account. The pull request schema does not.
    user: nullableToUndefined(GitHubSimpleUserSchema),
    created_at: zod_1.z.string(),
    updated_at: zod_1.z.string(),
    closed_at: optionalString(),
    html_url: zod_1.z.string()
});
const GitHubPullRequestSchema = zod_1.z.object({
    id: zod_1.z.number(),
    number: zod_1.z.number(),
    title: zod_1.z.string(),
    body: optionalString(),
    // `pull-request` declares `state: "open" | "closed"`. A merged pull request
    // reports state "closed" with a separate `merged` boolean, so "merged" was
    // an impossible value that a consumer could compare against forever.
    state: zod_1.z.enum(['open', 'closed']),
    head: zod_1.z.object({
        ref: zod_1.z.string(),
        sha: zod_1.z.string()
    }),
    base: zod_1.z.object({
        ref: zod_1.z.string(),
        sha: zod_1.z.string()
    }),
    // `pull-request` declares `user: simple-user`, non-nullable — unlike the
    // issue schema. Kept strict so this does not claim to tolerate a value the
    // endpoint never returns.
    user: GitHubSimpleUserSchema,
    created_at: zod_1.z.string(),
    updated_at: zod_1.z.string(),
    merged_at: optionalString(),
    closed_at: optionalString(),
    html_url: zod_1.z.string(),
    // GitHub reports `mergeable: null` while it is still computing the merge.
    mergeable: optionalBoolean(),
    // Declared non-nullable by GitHub; it reports "unknown", never null, while
    // the merge is being computed. Kept optional but not null-accepting so the
    // schema does not claim to tolerate a value the API never sends.
    mergeable_state: zod_1.z.string().optional()
});
class GitHubMCPServer {
    constructor(config) {
        this.config = GitHubConfigSchema.parse(config);
        this.headers = {
            'Authorization': `token ${this.config.token}`,
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'EdenOS-MCP-Bridge'
        };
    }
    // Get repository information
    async getRepository(owner, repo) {
        try {
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return GitHubRepositorySchema.parse(data);
        }
        catch (error) {
            throw new Error(`Failed to get repository: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // List repositories
    async listRepositories(owner, type = 'all', sort = 'updated', direction = 'desc', perPage = 30) {
        try {
            const url = owner
                ? `${this.config.baseUrl}/users/${owner}/repos`
                : `${this.config.baseUrl}/user/repos`;
            const params = new URLSearchParams({
                type,
                sort,
                direction,
                per_page: perPage.toString()
            });
            const response = await fetch(`${url}?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to list repositories: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Get issue by number
    async getIssue(owner, repo, issueNumber) {
        try {
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/issues/${issueNumber}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return GitHubIssueSchema.parse(data);
        }
        catch (error) {
            throw new Error(`Failed to get issue: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // List issues
    async listIssues(owner, repo, state = 'open', labels, assignee, creator, mentioned, sort = 'created', direction = 'desc', since, perPage = 30) {
        try {
            const params = new URLSearchParams({
                state,
                sort,
                direction,
                per_page: perPage.toString()
            });
            if (labels)
                params.append('labels', labels.join(','));
            if (assignee)
                params.append('assignee', assignee);
            if (creator)
                params.append('creator', creator);
            if (mentioned)
                params.append('mentioned', mentioned);
            if (since)
                params.append('since', since);
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/issues?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to list issues: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Create issue
    async createIssue(owner, repo, title, body, assignees, labels, milestone) {
        try {
            const issueData = { title };
            if (body)
                issueData.body = body;
            if (assignees)
                issueData.assignees = assignees;
            if (labels)
                issueData.labels = labels;
            if (milestone)
                issueData.milestone = milestone;
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/issues`, {
                method: 'POST',
                headers: this.headers,
                body: JSON.stringify(issueData)
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to create issue: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Update issue
    async updateIssue(owner, repo, issueNumber, title, body, state, assignees, labels, milestone) {
        try {
            const issueData = {};
            if (title)
                issueData.title = title;
            if (body)
                issueData.body = body;
            if (state)
                issueData.state = state;
            if (assignees)
                issueData.assignees = assignees;
            if (labels)
                issueData.labels = labels;
            if (milestone)
                issueData.milestone = milestone;
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/issues/${issueNumber}`, {
                method: 'PATCH',
                headers: this.headers,
                body: JSON.stringify(issueData)
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to update issue: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Get pull request by number
    async getPullRequest(owner, repo, pullNumber) {
        try {
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/pulls/${pullNumber}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return GitHubPullRequestSchema.parse(data);
        }
        catch (error) {
            throw new Error(`Failed to get pull request: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // List pull requests
    async listPullRequests(owner, repo, state = 'open', head, base, sort = 'created', direction = 'desc', perPage = 30) {
        try {
            const params = new URLSearchParams({
                state,
                sort,
                direction,
                per_page: perPage.toString()
            });
            if (head)
                params.append('head', head);
            if (base)
                params.append('base', base);
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/pulls?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to list pull requests: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Create pull request
    async createPullRequest(owner, repo, title, head, base, body, draft) {
        try {
            const prData = { title, head, base };
            if (body)
                prData.body = body;
            if (draft)
                prData.draft = draft;
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/pulls`, {
                method: 'POST',
                headers: this.headers,
                body: JSON.stringify(prData)
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to create pull request: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Merge pull request
    async mergePullRequest(owner, repo, pullNumber, expectedHeadSha, commitTitle, commitMessage, mergeMethod = 'merge') {
        try {
            const normalizedExpectedHeadSha = typeof expectedHeadSha === 'string' ? expectedHeadSha.trim() : '';
            if (!/^[0-9a-fA-F]{40}$/.test(normalizedExpectedHeadSha)) {
                throw new Error('expectedHeadSha must be an exact 40-character Git commit SHA');
            }
            const mergeData = { merge_method: mergeMethod, sha: normalizedExpectedHeadSha };
            if (commitTitle)
                mergeData.commit_title = commitTitle;
            if (commitMessage)
                mergeData.commit_message = commitMessage;
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/pulls/${pullNumber}/merge`, {
                method: 'PUT',
                headers: this.headers,
                body: JSON.stringify(mergeData)
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to merge pull request: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // List workflow runs
    async listWorkflowRuns(owner, repo, workflowId, actor, branch, event, status, conclusion, perPage = 30) {
        try {
            const params = new URLSearchParams({
                per_page: perPage.toString()
            });
            if (workflowId)
                params.append('workflow_id', workflowId);
            if (actor)
                params.append('actor', actor);
            if (branch)
                params.append('branch', branch);
            if (event)
                params.append('event', event);
            if (status)
                params.append('status', status);
            if (conclusion)
                params.append('conclusion', conclusion);
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/actions/runs?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to list workflow runs: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Get workflow run
    async getWorkflowRun(owner, repo, runId) {
        try {
            const response = await fetch(`${this.config.baseUrl}/repos/${owner}/${repo}/actions/runs/${runId}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to get workflow run: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Search repositories
    async searchRepositories(query, sort = 'stars', order = 'desc', perPage = 30) {
        try {
            const params = new URLSearchParams({
                q: query,
                sort,
                order,
                per_page: perPage.toString()
            });
            const response = await fetch(`${this.config.baseUrl}/search/repositories?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to search repositories: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Search issues
    async searchIssues(query, sort = 'created', order = 'desc', perPage = 30) {
        try {
            const params = new URLSearchParams({
                q: query,
                sort,
                order,
                per_page: perPage.toString()
            });
            const response = await fetch(`${this.config.baseUrl}/search/issues?${params}`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to search issues: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    // Get current user
    async getMe() {
        try {
            const response = await fetch(`${this.config.baseUrl}/user`, {
                method: 'GET',
                headers: this.headers
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
            }
            const data = await response.json();
            return data;
        }
        catch (error) {
            throw new Error(`Failed to get user info: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
}
exports.GitHubMCPServer = GitHubMCPServer;
// MCP Tools for GitHub
exports.githubTools = {
    'github.get-repository': {
        description: 'Get a GitHub repository by owner and name',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' }
            },
            required: ['owner', 'repo']
        }
    },
    'github.list-repositories': {
        description: 'List GitHub repositories',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Filter by owner' },
                type: { type: 'string', enum: ['all', 'owner', 'public', 'private', 'member'], description: 'Repository type' },
                sort: { type: 'string', enum: ['created', 'updated', 'pushed', 'full_name'], description: 'Sort field' },
                direction: { type: 'string', enum: ['asc', 'desc'], description: 'Sort direction' },
                perPage: { type: 'number', description: 'Number of results per page' }
            }
        }
    },
    'github.get-issue': {
        description: 'Get a GitHub issue by number',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                issueNumber: { type: 'number', description: 'Issue number' }
            },
            required: ['owner', 'repo', 'issueNumber']
        }
    },
    'github.list-issues': {
        description: 'List GitHub issues',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                state: { type: 'string', enum: ['open', 'closed', 'all'], description: 'Issue state' },
                labels: { type: 'array', items: { type: 'string' }, description: 'Filter by labels' },
                assignee: { type: 'string', description: 'Filter by assignee' },
                sort: { type: 'string', enum: ['created', 'updated', 'comments'], description: 'Sort field' },
                direction: { type: 'string', enum: ['asc', 'desc'], description: 'Sort direction' },
                perPage: { type: 'number', description: 'Number of results per page' }
            },
            required: ['owner', 'repo']
        }
    },
    'github.create-issue': {
        description: 'Create a new GitHub issue',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                title: { type: 'string', description: 'Issue title' },
                body: { type: 'string', description: 'Issue body' },
                assignees: { type: 'array', items: { type: 'string' }, description: 'Assignees' },
                labels: { type: 'array', items: { type: 'string' }, description: 'Labels' },
                milestone: { type: 'number', description: 'Milestone number' }
            },
            required: ['owner', 'repo', 'title']
        }
    },
    'github.update-issue': {
        description: 'Update a GitHub issue',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                issueNumber: { type: 'number', description: 'Issue number' },
                title: { type: 'string', description: 'New title' },
                body: { type: 'string', description: 'New body' },
                state: { type: 'string', enum: ['open', 'closed'], description: 'New state' },
                assignees: { type: 'array', items: { type: 'string' }, description: 'New assignees' },
                labels: { type: 'array', items: { type: 'string' }, description: 'New labels' },
                milestone: { type: 'number', description: 'New milestone' }
            },
            required: ['owner', 'repo', 'issueNumber']
        }
    },
    'github.get-pull-request': {
        description: 'Get a GitHub pull request by number',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                pullNumber: { type: 'number', description: 'Pull request number' }
            },
            required: ['owner', 'repo', 'pullNumber']
        }
    },
    'github.list-pull-requests': {
        description: 'List GitHub pull requests',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                state: { type: 'string', enum: ['open', 'closed', 'all'], description: 'PR state' },
                head: { type: 'string', description: 'Filter by head branch' },
                base: { type: 'string', description: 'Filter by base branch' },
                sort: { type: 'string', enum: ['created', 'updated', 'popularity', 'long-running'], description: 'Sort field' },
                direction: { type: 'string', enum: ['asc', 'desc'], description: 'Sort direction' },
                perPage: { type: 'number', description: 'Number of results per page' }
            },
            required: ['owner', 'repo']
        }
    },
    'github.create-pull-request': {
        description: 'Create a new GitHub pull request',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                title: { type: 'string', description: 'PR title' },
                head: { type: 'string', description: 'Head branch' },
                base: { type: 'string', description: 'Base branch' },
                body: { type: 'string', description: 'PR body' },
                draft: { type: 'boolean', description: 'Create as draft' }
            },
            required: ['owner', 'repo', 'title', 'head', 'base']
        }
    },
    'github.merge-pull-request': {
        description: 'Merge a GitHub pull request only when its current head exactly matches the reviewed SHA',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                pullNumber: { type: 'number', description: 'Pull request number' },
                expectedHeadSha: { type: 'string', pattern: '^[0-9a-fA-F]{40}$', description: 'Exact reviewed pull request head SHA; GitHub rejects the merge if the head moved' },
                commitTitle: { type: 'string', description: 'Merge commit title' },
                commitMessage: { type: 'string', description: 'Merge commit message' },
                mergeMethod: { type: 'string', enum: ['merge', 'squash', 'rebase'], description: 'Merge method' }
            },
            required: ['owner', 'repo', 'pullNumber', 'expectedHeadSha']
        }
    },
    'github.list-workflow-runs': {
        description: 'List GitHub workflow runs',
        parameters: {
            type: 'object',
            properties: {
                owner: { type: 'string', description: 'Repository owner' },
                repo: { type: 'string', description: 'Repository name' },
                workflowId: { type: 'string', description: 'Filter by workflow ID' },
                actor: { type: 'string', description: 'Filter by actor' },
                branch: { type: 'string', description: 'Filter by branch' },
                event: { type: 'string', description: 'Filter by event' },
                status: { type: 'string', enum: ['queued', 'in_progress', 'completed'], description: 'Filter by status' },
                conclusion: { type: 'string', enum: ['success', 'failure', 'neutral', 'cancelled', 'skipped', 'timed_out', 'action_required'], description: 'Filter by conclusion' },
                perPage: { type: 'number', description: 'Number of results per page' }
            },
            required: ['owner', 'repo']
        }
    },
    'github.search-repositories': {
        description: 'Search GitHub repositories',
        parameters: {
            type: 'object',
            properties: {
                query: { type: 'string', description: 'Search query' },
                sort: { type: 'string', enum: ['stars', 'forks', 'help-wanted-issues', 'updated'], description: 'Sort field' },
                order: { type: 'string', enum: ['asc', 'desc'], description: 'Sort order' },
                perPage: { type: 'number', description: 'Number of results per page' }
            },
            required: ['query']
        }
    },
    'github.search-issues': {
        description: 'Search GitHub issues',
        parameters: {
            type: 'object',
            properties: {
                query: { type: 'string', description: 'Search query' },
                sort: { type: 'string', enum: ['created', 'updated', 'comments'], description: 'Sort field' },
                order: { type: 'string', enum: ['asc', 'desc'], description: 'Sort order' },
                perPage: { type: 'number', description: 'Number of results per page' }
            },
            required: ['query']
        }
    },
    'github.get-me': {
        description: 'Get current GitHub user information',
        parameters: {
            type: 'object',
            properties: {}
        }
    }
};
// Tool execution handler
async function executeGitHubTool(tool, args, config) {
    const github = new GitHubMCPServer(config);
    switch (tool) {
        case 'github.get-repository':
            return await github.getRepository(args.owner, args.repo);
        case 'github.list-repositories':
            return await github.listRepositories(args.owner, args.type, args.sort, args.direction, args.perPage);
        case 'github.get-issue':
            return await github.getIssue(args.owner, args.repo, args.issueNumber);
        case 'github.list-issues':
            return await github.listIssues(args.owner, args.repo, args.state, args.labels, args.assignee, args.creator, args.mentioned, args.sort, args.direction, args.since, args.perPage);
        case 'github.create-issue':
            return await github.createIssue(args.owner, args.repo, args.title, args.body, args.assignees, args.labels, args.milestone);
        case 'github.update-issue':
            return await github.updateIssue(args.owner, args.repo, args.issueNumber, args.title, args.body, args.state, args.assignees, args.labels, args.milestone);
        case 'github.get-pull-request':
            return await github.getPullRequest(args.owner, args.repo, args.pullNumber);
        case 'github.list-pull-requests':
            return await github.listPullRequests(args.owner, args.repo, args.state, args.head, args.base, args.sort, args.direction, args.perPage);
        case 'github.create-pull-request':
            return await github.createPullRequest(args.owner, args.repo, args.title, args.head, args.base, args.body, args.draft);
        case 'github.merge-pull-request':
            return await github.mergePullRequest(args.owner, args.repo, args.pullNumber, args.expectedHeadSha, args.commitTitle, args.commitMessage, args.mergeMethod);
        case 'github.list-workflow-runs':
            return await github.listWorkflowRuns(args.owner, args.repo, args.workflowId, args.actor, args.branch, args.event, args.status, args.conclusion, args.perPage);
        case 'github.get-workflow-run':
            return await github.getWorkflowRun(args.owner, args.repo, args.runId);
        case 'github.search-repositories':
            return await github.searchRepositories(args.query, args.sort, args.order, args.perPage);
        case 'github.search-issues':
            return await github.searchIssues(args.query, args.sort, args.order, args.perPage);
        case 'github.get-me':
            return await github.getMe();
        default:
            throw new Error(`Unknown GitHub tool: ${tool}`);
    }
}
//# sourceMappingURL=github.js.map