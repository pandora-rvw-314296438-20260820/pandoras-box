-- Source-only staged guard. Apply to production only in a separately approved
-- database release, then prove real Supabase Auth behavior before enabling Facebook.
-- GoTrue's Before User Created hook cannot intercept an automatic same-email link.
-- A creation receipt from an auth.users INSERT proves the target account is new.
create table if not exists private.pandora_facebook_new_user_receipts_v1 (
  user_id uuid primary key,
  creating_txid bigint not null,
  recorded_at timestamptz not null default now()
);
revoke all on private.pandora_facebook_new_user_receipts_v1
  from public, anon, authenticated;

create or replace function private.pandora_facebook_record_new_user_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.raw_app_meta_data ->> 'provider' = 'facebook' then
    insert into private.pandora_facebook_new_user_receipts_v1
      (user_id, creating_txid)
    values (new.id, pg_catalog.txid_current());
  end if;
  return new;
end
$function$;
revoke all on function private.pandora_facebook_record_new_user_v1()
  from public, anon, authenticated;
drop trigger if exists pandora_facebook_record_new_user_v1 on auth.users;
create trigger pandora_facebook_record_new_user_v1
after insert on auth.users
for each row execute function private.pandora_facebook_record_new_user_v1();

create or replace function private.pandora_facebook_identity_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_email text;
begin
  if new.provider <> 'facebook' then
    return new;
  end if;
  select lower(btrim(u.email))
    into v_email
    from auth.users as u
   where u.id = new.user_id;

  -- The user must have been inserted by Auth as a Facebook user in this
  -- transaction. An UPDATE to an old user cannot create this receipt.
  if v_email is null or v_email = ''
     or lower(btrim(coalesce(new.identity_data ->> 'email', ''))) <> v_email
     or not exists (
       select 1 from private.pandora_facebook_new_user_receipts_v1 r
        where r.user_id = new.user_id
          and r.creating_txid = pg_catalog.txid_current()
     )
  then
    raise exception 'facebook_identity_requires_new_user'
      using errcode = '23514';
  end if;

  if exists (
    select 1 from auth.identities as i where i.user_id = new.user_id
  ) then
    raise exception 'facebook_identity_cannot_link_other_identity'
      using errcode = '23514';
  end if;

  -- Serialize new Facebook identities for one email before checking for a
  -- different Auth user, including users in other linking domains.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('pandora_facebook_identity:' || v_email)
  );
  if exists (
    select 1 from auth.users as u
     where u.id <> new.user_id and lower(btrim(u.email)) = v_email
  ) then
    raise exception 'facebook_identity_email_already_registered'
      using errcode = '23505';
  end if;
  delete from private.pandora_facebook_new_user_receipts_v1
   where user_id = new.user_id and creating_txid = pg_catalog.txid_current();
  return new;
end
$function$;

revoke all on function private.pandora_facebook_identity_guard_v1()
  from public, anon, authenticated;

drop trigger if exists pandora_facebook_identity_guard_v1 on auth.identities;
create trigger pandora_facebook_identity_guard_v1
before insert on auth.identities
for each row execute function private.pandora_facebook_identity_guard_v1();
