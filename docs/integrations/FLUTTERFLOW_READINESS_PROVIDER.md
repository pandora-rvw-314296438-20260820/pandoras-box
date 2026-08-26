# FlutterFlow readiness provider

**Delivery record:** `pandora-rvw-314296438-20260820/pandoras-box#26`  
**Provider status:** implemented read-only; production activation and project verification remain separate gates  
**Bound project:** `pandoras-box-gj9hnb`

## Outcome

MCPMaster can discover only explicitly allowlisted FlutterFlow projects and inspect bounded project-structure evidence through FlutterFlow's official Project API. It does not expose the bearer token, project YAML, collaborator data, owner email, sessions, or arbitrary project metadata.

The provider registers three read-only tools:

- `flutterflow.list-accounts`
- `flutterflow.list-projects`
- `flutterflow.inspect-readiness`

No FlutterFlow mutation, YAML update, code export, deployment, or store-release tool is registered.

## Provider boundary

- Production origin is fixed to `https://api.flutterflow.io/v2`.
- An operation requires an explicit configured account ID.
- Project inspection requires an exact project ID present in that account's allowlist.
- Unknown accounts, alternate origins, missing scopes, and non-allowlisted projects fail before a provider request.
- Responses are bounded by time and byte limits and pass through MCPMaster's result redaction.
- Project discovery is reduced to ID, name, dates, main-branch path, branch count, update count, project version, main-branch state, and the deployment-critical Library flag. FlutterFlow owner and collaborator fields are discarded.
- Readiness returns counts and configuration signals, not file names or YAML contents.

FlutterFlow documents the Project API as beta. The adapter therefore rejects an unrecognized response contract instead of guessing through provider drift. Official reference: <https://docs.flutterflow.io/resources/projects/settings/project-apis/>.

## Protected configuration

`vercel.json` contains only the non-secret binding:

```json
[
  {
    "id": "pandora-mobile",
    "label": "Pandora Mobile (FlutterFlow)",
    "tokenEnv": "FLUTTERFLOW_API_TOKEN",
    "allowedProjectIds": ["pandoras-box-gj9hnb"],
    "grantedScopes": ["projects:read", "project_schema:read"]
  }
]
```

The token itself must be installed as the protected server-side `FLUTTERFLOW_API_TOKEN` environment secret. It must never be placed in `vercel.json`, GitHub, logs, MCP results, screenshots, browser storage, or semantic Memory.

Optional bounded settings:

- `FLUTTERFLOW_API_TIMEOUT_MS`: 250–30,000 ms; default 10,000.
- `FLUTTERFLOW_API_MAX_RESPONSE_BYTES`: 1,024–2,000,000 bytes; default 1,000,000.

## Readiness semantics

`flutterflow.inspect-readiness` verifies that the API token can see the exact project and that FlutterFlow returns partitioned-file metadata with a schema fingerprint. It records whether `app-details`, authentication, app state, theme, pages, components, and custom files are structurally present. It also fails the `deployable_project_type` gate when FlutterFlow reports `isLibrary: true`, and fails closed when that signal is absent.

FlutterFlow documents that publishing a project as a Library is irreversible and disables both web and mobile deployment. Restoring an application project requires cloning the Library, which clears deployment and Firestore settings: <https://docs.flutterflow.io/resources/projects/libraries/>.

### Current bound-project finding

The protected Vault-backed check on 2026-08-13 returned HTTP 200 for `pandoras-box-gj9hnb`, partitioner version 13, schema fingerprint `1ae5bba3c4f3415753be1563417e3a510488ff4e`, and 795 partitioned files. FlutterFlow reports the exact project as `isLibrary: true`. It is the only Pandora-named project visible to the bound account, so this project is not deployable as an app. A non-Library clone must be created and its cleared deployment and backend settings restored before the remaining release gates can be evaluated.

The returned deployment status is always `blocked` until separate evidence exists for all remaining release gates:

1. Project YAML validation.
2. Generated Flutter code build.
3. Android and iOS signing configuration.
4. Authenticated device journeys on supported mobile viewports.
5. Environment and backend binding verification.
6. Independent review.
7. Explicit release authorization.
8. Rollback proof.

FlutterFlow's current AI/CLI documentation is explicit that editing a project does not execute or deploy the app and that app deployment is outside the agent's project-editing scope: <https://docs.flutterflow.io/flutterflow-cli/build/>.

## Activation gate

Before any production promotion:

- install the protected token without copying it into source;
- run `flutterflow.list-projects` and prove that only `pandoras-box-gj9hnb` survives filtering;
- run `flutterflow.inspect-readiness` and record the schema fingerprint without project YAML;
- run the repository test and security suite at the exact candidate SHA;
- obtain independent review;
- keep production promotion as a separate owner-authorized action.

If the token currently stored in the canonical Pandora Memory Vault is used, move or broker it through an approved server-only workflow. Do not reveal it to a client or copy it through chat.

## Rollback

Revert the provider commit and remove `FLUTTERFLOW_ACCOUNTS_JSON` plus the protected `FLUTTERFLOW_API_TOKEN` environment secret. Because the provider has no mutation surface, rollback does not require restoring FlutterFlow project data.
