# Pandora tracking minimization v1

Status: source candidate only. It is not deployed or activated. The candidate is based on
main `16fc51ecb9cbe905730309a3d64e5ef4fd89c963`.

This contract closes the bounded source gap in tracker R-005 without deciding purpose,
lawful basis, retention, deletion, or customer-data authority. Decisions D-008 and D-009
remain open.

## New-write behavior

The redirect collector generates `pcid` and preserves the configured HTTPS destination,
including its configured query. It does not forward request UTM values, sub identifiers,
platform click identifiers, or arbitrary query values. Campaign source, medium, campaign,
content, and term labels are not injected into the destination.

The click ledger stores the tenant, campaign, generated click ID, timestamp, and configured
destination origin plus path. New collector writes set referrer, user agent, IP hash, and
visitor hash to null; platform IDs and request query maps are empty. The fixed server-authored
metadata value is `{"collector":"vercel"}`.

Event and cost writes accept absent or empty metadata only. Nonempty metadata and unsupported
top-level JSON fields fail with a 400 response; those rejected fields are not silently truncated
or retained. Existing typed string fields keep their prior bounded parsing behavior.
FB-017 remains unchanged: schema version 1, exact boolean `analytics` and `marketing`
consent flags with false/false defaults, `is_test`, event meaning, value, currency, and
occurrence time remain typed fields. Tenant, campaign, click, measurement, and deduplication
keys remain available. The existing reporting-view definitions are unchanged. Because minimized
new clicks have no visitor hash, `unique_visitors` will count historical hashed rows only and
will not increment for new clicks. Restoring that metric requires a separately approved,
purpose-scoped design after D-008; this candidate does not disguise a linkable hash as anonymity.

## Database enforcement

Migration `20260929014500_pandora_tracking_minimization_v1.sql` adds three `NOT VALID`
checks. PostgreSQL enforces them for subsequent inserts and updates while avoiding a scan
or rewrite of historical rows. Existing rows remain readable. The migration does not change
RLS, grants, policies, views, indexes, or historical data.

The click constraint permits empty metadata or the existing fixed collector marker. Event
and cost metadata must be empty. Click rows cannot add raw referrer or user agent values,
linkable IP/visitor hashes, incoming query maps, platform ID maps, URL userinfo, or stored
landing query/fragment values.

## Activation holds

Configured destination queries require an owner-approved inventory before activation.
Inventory query keys and value classes without publishing values. A configured query may
be necessary for navigation, but configuration alone does not prove minimization, purpose,
or authority.

External event and cost identifiers remain required for deduplication. Syntax or hashing
cannot prove they exclude personal data. Activation therefore remains on HOLD until a
tenant-bound trusted-adapter registration contract is approved and implemented in a
separate schema/source change.
Referrer collection remains disabled. Origin-only referrer collection may be reconsidered
only after D-008 defines its purpose and lawful basis. Raw or hashed user agent, IP, visitor,
query, sub, and platform identifiers are outside this contract.

D-008 must decide purpose and lawful basis for each retained field. D-009 must decide
retention, deletion, and lifecycle handling. This source candidate does not infer either
decision and performs no historical deletion or rewrite.

## Verification

The HTTP tests exercise the real Express routes with a synthetic storage adapter. Canary
UTM, platform, sub, IP, user-agent, and referrer values reach neither the redirect nor the
click write. They also verify configured query preservation, generated `pcid`, unknown
field rejection, metadata rejection, and unchanged accepted FB-017 consent/test/event
behavior.

The PGlite test inserts non-minimized historical fixtures before applying the migration.
It proves those rows remain readable, each new unsafe write is rejected, minimized writes
succeed, the event deduplication index still rejects duplicates, and daily click/event/spend
aggregates remain unchanged.

Production activation still requires the governed source-review, migration, deployment,
and provider-readback gates. No production database, destination, customer record, grant,
Memory record, or provider setting is changed by this source package.
