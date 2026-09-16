
-- CHAT-FINISH-002
-- Correct the historical ProjectOS Memory repository binding without
-- reactivating the archived project or erasing the prior repository identity.
-- Clean replays may not contain this historical row, so absence is a safe no-op.
do $$
declare
  v_repository text;
begin
  select repository
    into v_repository
  from public.projectos_projects
  where id = '0306198e-38e5-4b1d-8932-efd58da3b856'::uuid
    and project_key = 'pandoras-box-memory'
    and status = 'archived'
  for update;

  if not found then
    return;
  end if;

  if v_repository = 'banataosystems/pandoras-box-memory' then
    update public.projectos_projects
       set repository = 'pandora-rvw-314296438-20260820/pandoras-box-memory',
           config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
             'repositoryAuthorityCorrection',
             jsonb_build_object(
               'previousRepository', 'banataosystems/pandoras-box-memory',
               'canonicalRepository', 'pandora-rvw-314296438-20260820/pandoras-box-memory',
               'sourceTask', 'CHAT-FINISH-002',
               'migration', '20260912092000_correct_archived_memory_repository_binding_v1'
             )
           ),
           updated_at = now()
     where id = '0306198e-38e5-4b1d-8932-efd58da3b856'::uuid
       and project_key = 'pandoras-box-memory'
       and status = 'archived'
       and repository = 'banataosystems/pandoras-box-memory';
  elsif v_repository <> 'pandora-rvw-314296438-20260820/pandoras-box-memory' then
    raise exception 'CHAT-FINISH-002 refused unexpected Memory repository binding: %', v_repository;
  end if;
end
$$;
