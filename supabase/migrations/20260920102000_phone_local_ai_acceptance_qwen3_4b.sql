create or replace function private.enforce_phone_local_ai_qwen3_4b_target()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if lower(new.model_sha256) <> '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6' then
    raise exception 'physical phone-local acceptance requires the approved Qwen3 4B Q4_K_M model'
      using errcode='22023';
  end if;
  return new;
end;
$$;

drop trigger if exists phone_local_ai_acceptance_qwen3_4b_target
  on private.phone_local_ai_acceptance_receipts;

create trigger phone_local_ai_acceptance_qwen3_4b_target
before insert on private.phone_local_ai_acceptance_receipts
for each row execute function private.enforce_phone_local_ai_qwen3_4b_target();

revoke all on function private.enforce_phone_local_ai_qwen3_4b_target()
  from public, anon, authenticated, service_role;
