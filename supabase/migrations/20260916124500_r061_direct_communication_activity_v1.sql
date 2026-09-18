
-- R-061 direct communication canonical Activity bridge v1.
-- Authenticated mobile callers may submit only bounded device facts for their
-- own Activity job. Canonical identity, sequence, evidence and messages are
-- minted by this trusted RPC; clients cannot write arbitrary Activity JSON.

create or replace function public.pandora_activity_device_fact_v1(
  p_organization_id uuid,
  p_job_id uuid,
  p_operation_id text,
  p_capability text,
  p_stage text,
  p_observed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_uid uuid := auth.uid();
  v_job public.pandora_activity_jobs%rowtype;
  v_existing public.pandora_activity_events%rowtype;
  v_operation text := trim(coalesce(p_operation_id,''));
  v_capability text := trim(coalesce(p_capability,''));
  v_stage text := trim(coalesce(p_stage,''));
  v_event_id text;
  v_sequence bigint;
  v_state text;
  v_message text;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_admitted timestamptz := now();
  v_at_text text;
  v_admitted_text text;
  v_ref text;
  v_evidence jsonb;
  v_blocker jsonb := null;
  v_outcome jsonb := null;
  v_event jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_uid
      and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;
  if v_operation !~ '^[A-Za-z0-9._:-]{8,128}$' then
    raise exception 'pandora_device_operation_id_invalid' using errcode='22023';
  end if;
  if v_capability not in ('calendar.events','reminder.local','communication.sms','communication.call') then
    raise exception 'pandora_device_capability_invalid' using errcode='22023';
  end if;
  if v_stage not in (
    'acting','verifying','result','failed','needs_permission',
    'needs_special_access','needs_choice'
  ) then
    raise exception 'pandora_device_stage_invalid' using errcode='22023';
  end if;
  if v_at > now() + interval '5 minutes'
     or v_at < now() - interval '30 days' then
    raise exception 'pandora_device_observed_at_invalid' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_activity_jobs
  where id=p_job_id
    and organization_id=p_organization_id
  for update;
  if not found or v_job.requested_by <> v_uid then
    raise exception 'pandora_activity_job_not_available' using errcode='42501';
  end if;

  v_event_id := 'device:' || replace(v_capability,'.','-') || ':' || v_operation || ':' || v_stage;
  select * into v_existing
  from public.pandora_activity_events
  where job_id=p_job_id and event_id=v_event_id;
  if found then
    return jsonb_build_object(
      'ok',true,'duplicate',true,'jobId',p_job_id,
      'eventId',v_existing.event_id,'sequence',v_existing.sequence,
      'state',v_existing.state
    );
  end if;

  if v_job.terminal_state is not null then
    raise exception 'pandora_activity_job_terminal' using errcode='55000';
  end if;

  case v_stage
    when 'acting' then
      v_state := 'acting';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar action started.'
        when 'reminder.local' then 'Android local reminder action started.'
        when 'communication.sms' then 'Android direct SMS action started.'
        when 'communication.call' then 'Android direct call action started.'
        else 'Android device action started.'
      end;
    when 'verifying' then
      v_state := 'verifying';
      v_message := case v_capability
        when 'calendar.events' then 'Pandora is verifying Android calendar provider readback.'
        when 'reminder.local' then 'Pandora is verifying the Android reminder schedule.'
        when 'communication.sms' then 'Pandora is verifying Android SMS native status.'
        when 'communication.call' then 'Pandora is verifying Android call launch status.'
        else 'Pandora is verifying Android device status.'
      end;
    when 'result' then
      v_state := 'result';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar result verified by provider readback.'
        when 'reminder.local' then 'Android local reminder schedule verified on-device.'
        when 'communication.sms' then 'Android SMS result verified from native callback/readback.'
        when 'communication.call' then 'Android call launch result verified from native readback; connection is not claimed.'
        else 'Android device result verified.'
      end;
      v_outcome := jsonb_build_object(
        'summary',v_message,
        'physicalDevice',false
      );
    when 'failed' then
      v_state := 'failed';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar action failed or could not be verified.'
        when 'reminder.local' then 'Android local reminder action failed or could not be verified.'
        when 'communication.sms' then 'Android SMS action failed or could not be verified.'
        when 'communication.call' then 'Android call launch failed or could not be verified.'
        else 'Android device action failed or could not be verified.'
      end;
    when 'needs_permission' then
      v_state := 'needs_you';
      v_message := 'Android permission is required before Pandora can continue.';
      v_blocker := jsonb_build_object(
        'reasonCode','authorization_required',
        'reason','Android has not granted the required runtime permission.',
        'requiredAction',case v_capability
          when 'calendar.events' then 'Grant Calendar permission to Pandora in Android app permissions.'
          when 'reminder.local' then 'Grant Notifications permission to Pandora in Android app permissions.'
          when 'communication.sms' then 'Grant SMS permission to Pandora in Android app permissions.'
          when 'communication.call' then 'Grant Phone permission to Pandora in Android app permissions.'
          else 'Grant the required Android permission to Pandora.'
        end,
        'approvalRequired',false,
        'policyRef','android-runtime-permission'
      );
    when 'needs_special_access' then
      v_state := 'needs_you';
      v_message := 'Android exact-alarm special access is required for this exact reminder.';
      v_blocker := jsonb_build_object(
        'reasonCode','external_blocker_only_user_can_resolve',
        'reason','Android controls exact-alarm special access outside normal runtime permissions.',
        'requiredAction','Enable Alarms & reminders special access for Pandora in Android settings.',
        'approvalRequired',false,
        'policyRef','android-exact-alarm-special-access'
      );
    when 'needs_choice' then
      v_state := 'needs_you';
      v_message := case v_capability
        when 'communication.sms' then 'Pandora needs one contact or SIM choice before sending the SMS.'
        when 'communication.call' then 'Pandora needs one contact or call-routing choice before placing the call.'
        else 'Pandora needs one calendar choice before making a consequential change.'
      end;
      v_blocker := jsonb_build_object(
        'reasonCode','missing_consequential_user_choice',
        'reason',case when v_capability like 'communication.%' then 'More than one safe communication target or route matches the request.' else 'More than one safe calendar target matches the request.' end,
        'requiredAction',case when v_capability like 'communication.%' then 'Choose the exact contact or system route to use.' else 'Choose the exact calendar or event to change.' end,
        'approvalRequired',false,
        'policyRef',case when v_capability like 'communication.%' then 'r061-communication-target-disambiguation' else 'm4-018-calendar-target-disambiguation' end
      );
  end case;

  v_sequence := v_job.last_sequence + 1;
  v_at_text := to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_admitted_text := to_char(v_admitted at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_ref := 'device://pandora/' || replace(v_capability,'.','-') || '/' || v_operation || '/' || v_stage;

  if v_state='result' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','verification','ref',v_ref),
      jsonb_build_object('type','verification_receipt','relation','verification','ref',v_ref || '/verified')
    );
  elsif v_state='failed' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','failure','ref',v_ref)
    );
  elsif v_state='verifying' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','readback','ref',v_ref)
    );
  else
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','source','ref',v_ref)
    );
  end if;

  v_event := jsonb_build_object(
    'schemaVersion',1,
    'eventId',v_event_id,
    'jobId',p_job_id,
    'sequence',v_sequence,
    'writerEpoch',v_job.writer_epoch,
    'admittedBy',v_job.writer_id,
    'admissionMode','online',
    'state',v_state,
    'message',v_message,
    'occurredAt',v_at_text,
    'admittedAt',v_admitted_text,
    'provenance',jsonb_build_object(
      'sourceType','device',
      'sourceId','pandora-android-device-v1',
      'sourceEventId',v_event_id,
      'observedAt',v_at_text
    ),
    'evidence',v_evidence,
    'domain','device',
    'capability',v_capability,
    'executionId',p_job_id,
    'blocker',v_blocker,
    'outcome',v_outcome
  );

  insert into public.pandora_activity_events(
    job_id,organization_id,sequence,event_id,writer_epoch,state,message,
    event,occurred_at,admitted_at
  ) values (
    p_job_id,p_organization_id,v_sequence,v_event_id,v_job.writer_epoch,
    v_state,v_message,v_event,v_at,v_admitted
  );

  update public.pandora_activity_jobs
  set last_sequence=v_sequence,
      terminal_state=case when v_state in ('result','failed','cancelled') then v_state else null end,
      updated_at=v_admitted
  where id=p_job_id;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'jobId',p_job_id,
    'eventId',v_event_id,'sequence',v_sequence,'state',v_state
  );
end;
$body$;

revoke all on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
  from public, anon;
grant execute on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
  to authenticated;

comment on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
is 'R-061 bounded authenticated calendar/reminder/SMS/call device-fact ingress into canonical Activity Theatre/History.';
