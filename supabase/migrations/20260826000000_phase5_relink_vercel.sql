do $$
declare
  v_org_id uuid;
  v_inst_id uuid;
begin
  select organization_id, id into v_org_id, v_inst_id
  from public.connector_installations
  where provider = 'vercel' limit 1;
  
  if v_inst_id is not null then
    perform public.queue_vercel_git_link_change(
      v_org_id,
      v_inst_id,
      'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
      'pandora-rvw-314296438-20260820/pandoras-box',
      true
    );
  end if;
end;
$$;
