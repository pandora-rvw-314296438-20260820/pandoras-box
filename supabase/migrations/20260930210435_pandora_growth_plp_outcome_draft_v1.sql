
begin;

create table if not exists public.pandora_growth_client_outcome_dictionaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  client_project_id uuid not null,
  client_key text not null,
  version text not null,
  approval_state text not null check(approval_state in ('client_approval_required','approved','retired')),
  event_dictionary jsonb not null check(jsonb_typeof(event_dictionary)='array'),
  metric_dictionary jsonb not null check(jsonb_typeof(metric_dictionary)='array'),
  generic_conversion_imposed boolean not null default false check(generic_conversion_imposed is false),
  proposed_by text not null,
  proposed_at timestamptz not null default clock_timestamp(),
  approved_by_client text,
  approved_at timestamptz,
  evidence_refs jsonb not null default '[]'::jsonb check(jsonb_typeof(evidence_refs)='array'),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,client_project_id,client_key,version),
  check (
    (approval_state='approved' and approved_by_client is not null and approved_at is not null)
    or
    (approval_state<>'approved' and approved_by_client is null and approved_at is null)
  )
);
alter table public.pandora_growth_client_outcome_dictionaries enable row level security;
revoke all on public.pandora_growth_client_outcome_dictionaries from public,anon,authenticated;
grant select on public.pandora_growth_client_outcome_dictionaries to service_role;

insert into public.pandora_growth_client_outcome_dictionaries(
  organization_id,client_project_id,client_key,version,approval_state,
  event_dictionary,metric_dictionary,generic_conversion_imposed,proposed_by,evidence_refs
) values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  '73b1afe9-91b5-4bf5-864c-22c071c4471a'::uuid,
  'plp-boracay','v1','client_approval_required',
  '[
    {"event":"plp_enquiry_received","meaning":"A genuine resort enquiry was received through an approved PLP channel.","requiredEvidence":["enquiry_ref","channel_ref"],"money":false},
    {"event":"plp_deposit_settled","meaning":"A booking deposit was provider-settled and reconciled to a PLP booking.","requiredEvidence":["booking_ref","payment_ref","settlement_ref"],"money":true},
    {"event":"plp_booking_paid","meaning":"The booking reached the client-approved paid-booking state with reconciled payment evidence.","requiredEvidence":["booking_ref","payment_ref","reconciliation_ref"],"money":true},
    {"event":"plp_booking_cancelled","meaning":"A PLP booking was cancelled with a reason/evidence reference; refund is a separate financial event when applicable.","requiredEvidence":["booking_ref","cancellation_ref"],"money":false}
  ]'::jsonb,
  '[
    {"metric":"enquiries","sourceEvent":"plp_enquiry_received","aggregation":"count"},
    {"metric":"settled_deposits","sourceEvent":"plp_deposit_settled","aggregation":"count_and_value"},
    {"metric":"paid_bookings","sourceEvent":"plp_booking_paid","aggregation":"count_and_value"},
    {"metric":"cancellations","sourceEvent":"plp_booking_cancelled","aggregation":"count"},
    {"metric":"enquiry_to_deposit_rate","numerator":"plp_deposit_settled","denominator":"plp_enquiry_received","claimType":"descriptive"},
    {"metric":"deposit_to_paid_booking_rate","numerator":"plp_booking_paid","denominator":"plp_deposit_settled","claimType":"descriptive"}
  ]'::jsonb,
  false,
  'owner-current-chat-2026-10-01',
  jsonb_build_array(
    jsonb_build_object('type','project','ref','73b1afe9-91b5-4bf5-864c-22c071c4471a'),
    jsonb_build_object('type','repository','ref','pandora-rvw-314296438-20260820/plp'),
    jsonb_build_object('type','requirement','ref','FB-058')
  )
)
on conflict(organization_id,client_project_id,client_key,version) do update
set approval_state='client_approval_required',
    event_dictionary=excluded.event_dictionary,
    metric_dictionary=excluded.metric_dictionary,
    generic_conversion_imposed=false,
    proposed_by=excluded.proposed_by,
    proposed_at=clock_timestamp(),
    approved_by_client=null,
    approved_at=null,
    evidence_refs=excluded.evidence_refs,
    updated_at=clock_timestamp();

create or replace function public.pandora_growth_client_outcome_dictionary_status_v1(
  p_organization_id uuid,
  p_client_project_id uuid
) returns jsonb
language sql
security definer
set search_path='pg_catalog','public'
as $function$
  select coalesce(
    (
      select jsonb_build_object(
        'ok',true,
        'clientKey',client_key,
        'version',version,
        'approvalState',approval_state,
        'eventDictionary',event_dictionary,
        'metricDictionary',metric_dictionary,
        'genericConversionImposed',generic_conversion_imposed,
        'approvedByClient',approved_by_client,
        'approvedAt',approved_at,
        'activationAllowed',approval_state='approved'
      )
      from public.pandora_growth_client_outcome_dictionaries
      where organization_id=p_organization_id
        and client_project_id=p_client_project_id
      order by proposed_at desc
      limit 1
    ),
    jsonb_build_object('ok',false,'approvalState','missing','activationAllowed',false)
  );
$function$;
revoke all on function public.pandora_growth_client_outcome_dictionary_status_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function public.pandora_growth_client_outcome_dictionary_status_v1(uuid,uuid)
to service_role;

commit;
;
