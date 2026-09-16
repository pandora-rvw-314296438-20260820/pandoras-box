-- Pandora Base44 Build Theatre truth repair.
-- A verified preview is REVIEW/Preview ready until a real production runtime exists.
-- Base44 publishability must respect the server-side project/action rollout gate.

do $patch$
declare
  v_def text;
  v_before text;
begin
  select pg_get_functiondef(
    'private.pandora_compute_project_experience_v1(uuid)'::regprocedure
  ) into v_def;
  v_before := v_def;

  v_def := replace(
    v_def,
$old_failure$
      when n.current_version_id is not null
        and (
          n.latest_failure_is_relevant
          or n.normalized_candidate_verification_state in ('failed','blocked')
        )
        then 'LIVE'
$old_failure$,
$new_failure$
      when n.current_version_id is not null
        and (
          n.latest_failure_is_relevant
          or n.normalized_candidate_verification_state in ('failed','blocked')
        )
        then case when n.production_version_id is not null then 'LIVE' else 'REVIEW' end
$new_failure$
  );
  if v_def = v_before then
    raise exception 'experience projection failure-state patch anchor missing' using errcode='55000';
  end if;
  v_before := v_def;

  v_def := replace(
    v_def,
$old_current$
      when n.current_version_id is not null or n.production_version_id is not null
        then 'LIVE'
$old_current$,
$new_current$
      when n.production_version_id is not null
        then 'LIVE'
      when n.current_version_id is not null
        then 'REVIEW'
$new_current$
  );
  if v_def = v_before then
    raise exception 'experience projection current-state patch anchor missing' using errcode='55000';
  end if;
  v_before := v_def;

  v_def := replace(
    v_def,
$old_review$
    when s.normalized_experience_state = 'REVIEW' then 'Change verified'
$old_review$,
$new_review$
    when s.normalized_experience_state = 'REVIEW'
      and s.production_version_id is null then 'Preview ready'
    when s.normalized_experience_state = 'REVIEW' then 'Change verified'
$new_review$
  );
  if v_def = v_before then
    raise exception 'experience projection review-message patch anchor missing' using errcode='55000';
  end if;
  v_before := v_def;

  v_def := replace(
    v_def,
$old_publish$
  (
    (
      s.candidate_version_id is not null
      and s.normalized_candidate_verification_state = 'passed'
      and s.candidate_preview_ready
    )
    or (
      s.current_version_id is not null
      and s.is_current_verified
      and s.current_version_id is distinct from s.production_version_id
    )
  ) as can_publish,
$old_publish$,
$new_publish$
  (
    (
      (
        s.candidate_version_id is not null
        and s.normalized_candidate_verification_state = 'passed'
        and s.candidate_preview_ready
      )
      or (
        s.current_version_id is not null
        and s.is_current_verified
        and s.current_version_id is distinct from s.production_version_id
      )
    )
    and public.pandora_base44_action_allowed_v1(s.project_id, 'publish')
  ) as can_publish,
$new_publish$
  );
  if v_def = v_before then
    raise exception 'experience projection publish-gate patch anchor missing' using errcode='55000';
  end if;

  execute v_def;
end
$patch$;

do $refresh$
declare
  v_project_id uuid;
begin
  for v_project_id in
    select e.project_id
    from public.pandora_project_experience_projection e
    where e.current_version_id is not null
      and e.production_version_id is null
    union
    select r.project_id
    from public.pandora_base44_rollout_projects r
    where r.enabled = true
  loop
    perform private.pandora_refresh_project_experience_projection_v1(v_project_id);
  end loop;
end
$refresh$;

comment on function private.pandora_compute_project_experience_v1(uuid) is
  'Canonical owner experience projection. LIVE requires a production runtime; verified preview-only state is REVIEW. Publishability also respects Base44 project/action rollout controls.';
