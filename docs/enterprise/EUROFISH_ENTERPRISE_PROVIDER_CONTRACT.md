# Euro-Fish Enterprise provider contract

Euro-Fish Enterprise is the isolated business workspace for 1064 Euro-Fish Trading.

## Canonical identity

- Source repository: \`pandora-rvw-314296438-20260820/pandoras-box\`
- Source branch: \`enterprise-ui-business-1\`
- Memory repository: \`pandora-rvw-314296438-20260820/pandoras-box-memory\`
- Memory project key: \`enterprise-eurofish\`
- Memory namespace: \`real_life\`
- Supabase project: \`jcyqixttuebxqqfkjonq\`
- Isolated database schema: \`eurofish\`
- Production Vercel project: \`pandora-enterprise-business-1\`

## Product contract

Every Euro-Fish operating surface is a dashboard, workspace and adaptive canvas. Pandora stays on the page through a persistent command dock and an inline Activity Theatre. Enterprise commands must not navigate to the generic Ask Pandora screen.

Surfaces: Command Center, Commercial, Import Operations, Aquaculture, Floriculture, Customers, Suppliers, Compliance, Finance, Evidence & Documents, Integrations & Admin.

## Data-truth contract

Operational values may be displayed only from an authoritative connected source. Unknown values render as an em dash, never zero.

Supported truth states: Live, Verified, Manual, Stale, Not Connected, External Intelligence.

External intelligence is never silently merged into internal business truth.

## Backend boundary

The public read contract is \`public.pandora_eurofish_workspace_v1(text)\`.

The private workspace contract is \`public.pandora_eurofish_private_workspace_v1(text)\`; anonymous execution is forbidden. Operational tables in the \`eurofish\` schema are RLS-enabled and direct client table access remains closed until an authorized Euro-Fish membership is provisioned.

Business events queue project-scoped memory candidates through \`eurofish.memory_outbox\`. Cross-project Memory publication stays fail-closed until a Pandora-native principal is authorized; old ProjectOS-named principals are not used.
