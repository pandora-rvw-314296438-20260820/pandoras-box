# Pandora Unified Capability Registry v1 — M3-004

Status: implementation candidate for **M3-004**.

## Purpose

Pandora needs one discovery contract for models, governed tools, Device Agent capabilities, future cloud/service adapters, and apps. The registry answers **what exists, what scope it belongs to, what authority and permissions it requires, whether it is actually available, and which adapter would execute it**.

Discovery is not permission. Registration is not authorization. A model seeing a capability does not grant itself authority to execute it.

## Descriptor contract

Every descriptor exposes:

- stable `id`, `version`, and `key`
- `kind`: tool, model, device, service, cloud, or app
- `scope`: project, device, provider, service, cloud, or app
- human-readable description
- authority class
- current availability
- risk and side-effect class
- approval mode
- required actor policy capabilities
- required platform permissions
- execution adapter, when one exists
- whether the existing Tool Gateway may execute it now
- evidence source and bounded metadata

The contract deliberately keeps three concerns separate:

1. **actor policy capabilities** — what Pandora policy says this actor may do;
2. **platform permissions / roles** — what Android or another platform has actually granted;
3. **runtime availability** — whether the adapter/device/provider is actually available now.

Runtime truth may temporarily narrow a declared-available capability and later restore its declared executable state. It does not alter authority, risk, permissions, or adapter identity, and it cannot promote `implementation_pending`, `unsupported`, `forbidden`, or `disabled` capability declarations to `available`.

## Existing project Tool Gateway

The existing `pandora-tools` registry remains the execution authority for project-scoped tools. M3-004 projects those definitions into the universal discovery registry without changing their policy, approval, idempotency, side-effect, retry, or executor semantics.

Project tools that are currently available remain `gatewayExecutable=true`.

## Models and providers

Model declarations can be projected into the same registry as `kind=model`. Provider/model discovery remains separate from Tool Gateway execution authority. Model entries never become executable tools merely by being present in this registry.

M3 routing continues to own provider/model selection.

## Device Agent tools

M3-004 registers Device Agent inspection/diagnostic work as first-class tool descriptors:

- `tool.device.get_capability_manifest`
- `tool.device.get_permission_states`
- `tool.device.run_safe_diagnostic`
- `tool.device.get_resource_snapshot`
- `tool.device.run_resource_benchmark`

The first three correspond to existing M4-001 Device Agent read-only surfaces. M4-009 now implements resource snapshot and bounded benchmark locally on Android, so those two descriptors are `available` when the Device Agent runtime is present. They remain phone-local reads, not project Tool Gateway operations.

All five use `DeviceAgentExecutor` as the adapter identity and remain `gatewayExecutable=false`: the project Tool Gateway is project-resource-bound, while these reads execute only inside the authenticated Pandora Android app through an allowlisted Device Agent executor. The M4-009 continuation contract permits only resource snapshot and bounded benchmark, validates typed results locally, then resumes the same authenticated intelligence turn. Device disconnect, unsupported public APIs, malformed results, or unlisted methods fail closed.

**M3-005 remains the authority owner for governed execution semantics.** This phone-local read path does not create mutation authority, provider credentials, arbitrary shell, or project-resource authority.

## Live Device Agent capability truth

The registry can also ingest the live M4 capability manifest as `kind=device` descriptors. This preserves states such as:

- `available`
- `permission_required`
- `implementation_pending`
- `unsupported`
- `forbidden`

`policy_denied + forbidden` remains the required shape for protected application private data, arbitrary shell, root-control, or equivalent prohibited surfaces. Runtime ingestion cannot convert prediction or desired architecture into permission.

## Security invariants

M3-004 does not:

- add Android permissions;
- grant Device Owner, HOME, dialer, SMS, accessibility, or protected-app authority;
- expose arbitrary shell or provider credentials;
- weaken Tool Gateway policy, approvals, idempotency, or readback;
- execute tools merely because they are discoverable;
- claim M4-009 telemetry/benchmarking is implemented;
- treat model self-selection as authority.

## Acceptance

M3-004 source acceptance requires:

1. project tools project into the unified descriptor format without authority drift;
2. model/provider declarations can join the same discovery registry without becoming tools;
3. Device Agent inspection and diagnostics are first-class device-scoped tool descriptors;
4. live Device Agent capability states can be represented truthfully;
5. runtime state can narrow availability but cannot grant execution authority;
6. implemented resource introspection/benchmarks advertise available only through the bounded Android-local read boundary;
7. device-scoped reads fail closed when the Device Agent is unavailable or returns invalid data, and never become project-gateway mutation authority;
8. focused tests and repository CI pass on the exact candidate head.
