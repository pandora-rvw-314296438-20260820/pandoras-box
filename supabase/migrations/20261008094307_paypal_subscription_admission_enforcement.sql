alter table public.pandora_paypal_plan_change_sessions enable row level security;
drop policy if exists "service_role_manage_pandora_paypal_plan_change_sessions" on public.pandora_paypal_plan_change_sessions;
create policy "service_role_manage_pandora_paypal_plan_change_sessions"
  on public.pandora_paypal_plan_change_sessions
  as permissive
  for all
  to service_role
  using (true)
  with check (true);

update public.pandora_service_plans
set request_admission_policy='block',
    updated_at=now()
where code in ('launch','professional')
  and state='active'
  and currency='USD';