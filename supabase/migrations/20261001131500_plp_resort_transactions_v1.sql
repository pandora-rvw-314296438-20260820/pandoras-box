create table if not exists plp_runtime.plp_operation_receipts (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id text not null,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  operation text not null,
  entity_kind text not null,
  entity_id uuid,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, request_id),
  constraint plp_operation_receipts_request_id_check
    check (length(request_id) between 8 and 120),
  constraint plp_operation_receipts_operation_check
    check (length(operation) between 3 and 80),
  constraint plp_operation_receipts_entity_kind_check
    check (length(entity_kind) between 2 and 80)
);

alter table plp_runtime.plp_operation_receipts enable row level security;
revoke all on table plp_runtime.plp_operation_receipts from public,anon,authenticated;

create or replace function private.plp_reject_operation_receipt_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $receipt$
begin
  raise exception 'PLP operation receipts are immutable' using errcode='42501';
end;
$receipt$;

drop trigger if exists plp_operation_receipts_immutable_v1
  on plp_runtime.plp_operation_receipts;
create trigger plp_operation_receipts_immutable_v1
before update or delete on plp_runtime.plp_operation_receipts
for each row execute function private.plp_reject_operation_receipt_mutation_v1();

create table if not exists plp_runtime.plp_room_states (
  accommodation_id uuid primary key
    references plp_runtime.plp_accommodations(id) on delete cascade,
  state text not null default 'ready',
  note text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint plp_room_states_state_check
    check (state in ('ready','dirty','cleaning','inspection','maintenance','out_of_order'))
);

alter table plp_runtime.plp_room_states enable row level security;
revoke all on table plp_runtime.plp_room_states from public,anon,authenticated;

alter table plp_runtime.plp_bookings
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_out_at timestamptz,
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

create unique index if not exists plp_guests_normalized_email_uidx
  on plp_runtime.plp_guests ((lower(normalized_email)))
  where normalized_email is not null and trim(normalized_email)<>'';

create or replace function private.plp_membership_context_v1(
  p_allowed_roles text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  role_name text;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties
  where slug='plp-boracay'
  order by updated_at desc,id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select m.role::text into role_name
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if role_name is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  if p_allowed_roles is not null and not (role_name=any(p_allowed_roles)) then
    raise exception 'PLP role is not authorized for this operation' using errcode='42501';
  end if;

  return jsonb_build_object(
    'userId',uid,
    'organizationId',prop.organization_id,
    'propertyId',prop.id,
    'role',role_name
  );
end;
$$;

create or replace function private.plp_operation_replay_v1(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_request_id text,
  p_operation text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  existing plp_runtime.plp_operation_receipts%rowtype;
begin
  if p_request_id is null
     or length(p_request_id) not between 8 and 120
     or p_request_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,119}$' then
    raise exception 'invalid request id' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_organization_id::text||':'||p_request_id,0)
  );

  select * into existing
  from plp_runtime.plp_operation_receipts
  where organization_id=p_organization_id
    and request_id=p_request_id;

  if existing.request_id is null then
    return null;
  end if;

  if existing.actor_user_id<>p_actor_user_id or existing.operation<>p_operation then
    raise exception 'request id already belongs to another operation' using errcode='23505';
  end if;

  return existing.response;
end;
$$;

create or replace function private.plp_operation_record_v1(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_request_id text,
  p_operation text,
  p_entity_kind text,
  p_entity_id uuid,
  p_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into plp_runtime.plp_operation_receipts(
    organization_id,request_id,actor_user_id,operation,entity_kind,entity_id,response
  ) values (
    p_organization_id,p_request_id,p_actor_user_id,p_operation,p_entity_kind,p_entity_id,p_response
  );
  return p_response;
end;
$$;

create or replace function public.plp_create_reservation_v1(
  p_request_id text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_accommodation_id uuid,
  p_check_in date,
  p_check_out date,
  p_guest_count integer,
  p_special_requests text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  room plp_runtime.plp_accommodations%rowtype;
  guest plp_runtime.plp_guests%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  nights integer;
  reference text;
  response jsonb;
  email_key text := lower(trim(coalesce(p_email,'')));
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'reservation.create');
  if replay is not null then return replay; end if;

  if nullif(trim(coalesce(p_full_name,'')),'') is null then
    raise exception 'guest name is required' using errcode='22023';
  end if;
  if email_key='' or position('@' in email_key)<2 then
    raise exception 'valid guest email is required' using errcode='22023';
  end if;
  if p_check_in is null or p_check_out is null or p_check_out<=p_check_in then
    raise exception 'check-out must be after check-in' using errcode='22023';
  end if;
  if p_guest_count is null or p_guest_count<1 then
    raise exception 'guest count must be positive' using errcode='22023';
  end if;

  select * into room
  from plp_runtime.plp_accommodations
  where id=p_accommodation_id and is_active=true
  for update;

  if room.id is null then
    raise exception 'active room not found' using errcode='P0002';
  end if;
  if p_guest_count>room.capacity then
    raise exception 'guest count exceeds room capacity' using errcode='22023';
  end if;

  if exists (
    select 1
    from plp_runtime.plp_bookings b
    where b.accommodation_id=room.id
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
      and b.check_in<p_check_out
      and b.check_out>p_check_in
  ) then
    raise exception 'room is not available for those dates' using errcode='23P01';
  end if;

  select * into guest
  from plp_runtime.plp_guests g
  where lower(coalesce(g.normalized_email,g.email))=email_key
  order by g.updated_at desc,g.id
  limit 1
  for update;

  if guest.id is null then
    insert into plp_runtime.plp_guests(full_name,email,phone,metadata)
    values(trim(p_full_name),email_key,nullif(trim(coalesce(p_phone,'')),''),'{}'::jsonb)
    returning * into guest;
  else
    update plp_runtime.plp_guests
    set full_name=trim(p_full_name),
        email=email_key,
        phone=coalesce(nullif(trim(coalesce(p_phone,'')),''),phone),
        updated_at=clock_timestamp()
    where id=guest.id
    returning * into guest;
  end if;

  nights := (p_check_out-p_check_in);
  reference := 'PLP-'||to_char(clock_timestamp(),'YYMMDD')||'-'||
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  insert into plp_runtime.plp_bookings(
    booking_reference,guest_id,accommodation_id,accommodation_name,
    check_in,check_out,guest_count,nights,rate_per_night_php,total_amount_php,
    deposit_amount_php,balance_amount_php,status,payment_status,special_requests,
    source,confirmed_at,updated_by
  ) values (
    reference,guest.id,room.id,room.name,
    p_check_in,p_check_out,p_guest_count,nights,room.nightly_rate_php,
    room.nightly_rate_php*nights,0,room.nightly_rate_php*nights,
    'CONFIRMED','PENDING',nullif(trim(coalesce(p_special_requests,'')),''),
    'pandora_plp_mobile',clock_timestamp(),uid
  )
  returning * into booking;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  select * into booking from plp_runtime.plp_bookings where id=booking.id;
  response := jsonb_build_object(
    'verified',true,
    'providerReadbackVerified',booking.id is not null,
    'operation','reservation.create',
    'requestId',p_request_id,
    'actorRole',ctx->>'role',
    'booking',jsonb_build_object(
      'id',booking.id,
      'bookingReference',booking.booking_reference,
      'guestId',booking.guest_id,
      'fullName',guest.full_name,
      'accommodationId',booking.accommodation_id,
      'accommodationName',booking.accommodation_name,
      'checkIn',booking.check_in,
      'checkOut',booking.check_out,
      'guestCount',booking.guest_count,
      'status',booking.status,
      'paymentStatus',booking.payment_status,
      'totalAmountPhp',booking.total_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,
      'specialRequest',booking.special_requests
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'reservation.create','booking',booking.id,response
  );
end;
$$;

create or replace function public.plp_update_reservation_v1(
  p_request_id text,
  p_booking_id uuid,
  p_accommodation_id uuid,
  p_check_in date,
  p_check_out date,
  p_guest_count integer,
  p_special_requests text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  room plp_runtime.plp_accommodations%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  night_count integer;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'reservation.update');
  if replay is not null then return replay; end if;

  select * into booking from plp_runtime.plp_bookings
  where id=p_booking_id for update;
  if booking.id is null then
    raise exception 'reservation not found' using errcode='P0002';
  end if;
  if upper(booking.status) not in ('PENDING_PAYMENT','CONFIRMED') then
    raise exception 'reservation can no longer be edited' using errcode='22023';
  end if;
  if p_check_out<=p_check_in or p_guest_count<1 then
    raise exception 'invalid reservation dates or guest count' using errcode='22023';
  end if;

  select * into room from plp_runtime.plp_accommodations
  where id=p_accommodation_id and is_active=true for update;
  if room.id is null then raise exception 'active room not found' using errcode='P0002'; end if;
  if p_guest_count>room.capacity then raise exception 'guest count exceeds room capacity' using errcode='22023'; end if;

  if exists (
    select 1 from plp_runtime.plp_bookings b
    where b.accommodation_id=room.id
      and b.id<>booking.id
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
      and b.check_in<p_check_out
      and b.check_out>p_check_in
  ) then
    raise exception 'room is not available for those dates' using errcode='23P01';
  end if;

  night_count := p_check_out-p_check_in;
  update plp_runtime.plp_bookings
  set accommodation_id=room.id,
      accommodation_name=room.name,
      check_in=p_check_in,
      check_out=p_check_out,
      guest_count=p_guest_count,
      nights=night_count,
      rate_per_night_php=room.nightly_rate_php,
      total_amount_php=room.nightly_rate_php*night_count,
      balance_amount_php=greatest(room.nightly_rate_php*night_count-deposit_amount_php,0),
      special_requests=nullif(trim(coalesce(p_special_requests,'')),''),
      payment_status=case
        when greatest(room.nightly_rate_php*night_count-deposit_amount_php,0)=0 then 'PAID'
        when deposit_amount_php>0 then 'PARTIAL'
        else 'PENDING'
      end,
      updated_by=uid,
      updated_at=clock_timestamp()
  where id=booking.id
  returning * into booking;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','reservation.update','requestId',p_request_id,
    'booking',to_jsonb(booking)-'updated_by'
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'reservation.update','booking',booking.id,response
  );
end;
$$;

create or replace function public.plp_transition_reservation_v1(
  p_request_id text,
  p_booking_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  booking plp_runtime.plp_bookings%rowtype;
  action_name text := lower(trim(coalesce(p_action,'')));
  new_status text;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'reservation.'||action_name);
  if replay is not null then return replay; end if;

  select * into booking from plp_runtime.plp_bookings where id=p_booking_id for update;
  if booking.id is null then raise exception 'reservation not found' using errcode='P0002'; end if;

  if action_name='confirm' then
    if upper(booking.status) not in ('PENDING_PAYMENT','CONFIRMED') then
      raise exception 'reservation cannot be confirmed from its current state' using errcode='22023';
    end if;
    new_status := 'CONFIRMED';
    update plp_runtime.plp_bookings
    set status=new_status,confirmed_at=coalesce(confirmed_at,clock_timestamp()),
        updated_by=uid,updated_at=clock_timestamp()
    where id=booking.id returning * into booking;
  elsif action_name='check_in' then
    if upper(booking.status) not in ('PENDING_PAYMENT','CONFIRMED') then
      raise exception 'reservation cannot be checked in from its current state' using errcode='22023';
    end if;
    new_status := 'CHECKED_IN';
    update plp_runtime.plp_bookings
    set status=new_status,confirmed_at=coalesce(confirmed_at,clock_timestamp()),
        checked_in_at=clock_timestamp(),updated_by=uid,updated_at=clock_timestamp()
    where id=booking.id returning * into booking;
  elsif action_name='check_out' then
    if upper(booking.status)<>'CHECKED_IN' then
      raise exception 'only a checked-in stay can be checked out' using errcode='22023';
    end if;
    new_status := 'CHECKED_OUT';
    update plp_runtime.plp_bookings
    set status=new_status,checked_out_at=clock_timestamp(),
        updated_by=uid,updated_at=clock_timestamp()
    where id=booking.id returning * into booking;
  elsif action_name='cancel' then
    if upper(booking.status) not in ('PENDING_PAYMENT','CONFIRMED') then
      raise exception 'reservation cannot be cancelled from its current state' using errcode='22023';
    end if;
    if booking.deposit_amount_php>0 then
      raise exception 'recorded payments must be reversed before cancellation' using errcode='22023';
    end if;
    new_status := 'CANCELLED';
    update plp_runtime.plp_bookings
    set status=new_status,cancelled_at=clock_timestamp(),
        updated_by=uid,updated_at=clock_timestamp()
    where id=booking.id returning * into booking;
  else
    raise exception 'unsupported reservation action' using errcode='22023';
  end if;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','reservation.'||action_name,'requestId',p_request_id,
    'bookingId',booking.id,'bookingReference',booking.booking_reference,
    'status',booking.status,'updatedAt',booking.updated_at
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'reservation.'||action_name,'booking',booking.id,response
  );
end;
$$;

create or replace function public.plp_update_guest_v1(
  p_request_id text,
  p_guest_id uuid,
  p_full_name text,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  guest plp_runtime.plp_guests%rowtype;
  email_key text := lower(trim(coalesce(p_email,'')));
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'guest.update');
  if replay is not null then return replay; end if;
  if nullif(trim(coalesce(p_full_name,'')),'') is null or email_key='' then
    raise exception 'guest name and email are required' using errcode='22023';
  end if;
  if exists (
    select 1 from plp_runtime.plp_guests
    where id<>p_guest_id and lower(coalesce(normalized_email,email))=email_key
  ) then
    raise exception 'another guest already uses that email' using errcode='23505';
  end if;

  update plp_runtime.plp_guests
  set full_name=trim(p_full_name),email=email_key,
      phone=nullif(trim(coalesce(p_phone,'')),''),
      updated_at=clock_timestamp()
  where id=p_guest_id
  returning * into guest;

  if guest.id is null then raise exception 'guest not found' using errcode='P0002'; end if;

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','guest.update','requestId',p_request_id,
    'guest',jsonb_build_object(
      'id',guest.id,'fullName',guest.full_name,'email',guest.email,'phone',guest.phone
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'guest.update','guest',guest.id,response
  );
end;
$$;

create or replace function public.plp_record_payment_v1(
  p_request_id text,
  p_booking_id uuid,
  p_amount_php numeric,
  p_method text,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  booking plp_runtime.plp_bookings%rowtype;
  payment plp_runtime.plp_payments%rowtype;
  new_balance numeric;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'payment.record');
  if replay is not null then return replay; end if;

  select * into booking from plp_runtime.plp_bookings where id=p_booking_id for update;
  if booking.id is null then raise exception 'reservation not found' using errcode='P0002'; end if;
  if p_amount_php is null or p_amount_php<=0 or p_amount_php>booking.balance_amount_php then
    raise exception 'payment amount must be positive and no greater than the balance' using errcode='22023';
  end if;

  insert into plp_runtime.plp_payments(
    booking_id,provider,provider_reference_id,amount_php,currency,status,
    verification_status,raw_response,paid_at
  ) values (
    booking.id,
    'manual:'||lower(trim(coalesce(p_method,'manual'))),
    nullif(trim(coalesce(p_reference,'')),''),
    p_amount_php,'PHP','PAID','MANUAL_RECORDED',
    jsonb_build_object('requestId',p_request_id,'actorUserId',uid),
    clock_timestamp()
  ) returning * into payment;

  new_balance := greatest(booking.balance_amount_php-p_amount_php,0);
  update plp_runtime.plp_bookings
  set deposit_amount_php=deposit_amount_php+p_amount_php,
      balance_amount_php=new_balance,
      payment_status=case when new_balance=0 then 'PAID' else 'PARTIAL' end,
      updated_by=uid,updated_at=clock_timestamp()
  where id=booking.id
  returning * into booking;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',payment.id is not null,
    'operation','payment.record','requestId',p_request_id,
    'payment',jsonb_build_object(
      'id',payment.id,'bookingId',payment.booking_id,'amountPhp',payment.amount_php,
      'status',payment.status,'verificationStatus',payment.verification_status,
      'paidAt',payment.paid_at
    ),
    'booking',jsonb_build_object(
      'id',booking.id,'paymentStatus',booking.payment_status,
      'balanceAmountPhp',booking.balance_amount_php
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'payment.record','payment',payment.id,response
  );
end;
$$;

create or replace function public.plp_void_manual_payment_v1(
  p_request_id text,
  p_payment_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $voidpay$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  payment plp_runtime.plp_payments%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  new_deposit numeric;
  new_balance numeric;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'payment.void_manual');
  if replay is not null then return replay; end if;

  select * into payment
  from plp_runtime.plp_payments
  where id=p_payment_id
  for update;
  if payment.id is null then
    raise exception 'payment not found' using errcode='P0002';
  end if;
  if payment.provider not like 'manual:%' or upper(payment.status)<>'PAID' then
    raise exception 'only a recorded manual payment can be reversed here' using errcode='22023';
  end if;

  select * into booking
  from plp_runtime.plp_bookings
  where id=payment.booking_id
  for update;
  if booking.id is null then
    raise exception 'reservation not found' using errcode='P0002';
  end if;

  update plp_runtime.plp_payments
  set status='REFUNDED',
      verification_status='MANUAL_REVERSED',
      verification_error=nullif(trim(coalesce(p_note,'')),''),
      raw_response=coalesce(raw_response,'{}'::jsonb) ||
        jsonb_build_object(
          'voidRequestId',p_request_id,
          'voidActorUserId',uid,
          'voidedAt',clock_timestamp()
        ),
      updated_at=clock_timestamp()
  where id=payment.id
  returning * into payment;

  new_deposit := greatest(booking.deposit_amount_php-payment.amount_php,0);
  new_balance := greatest(booking.total_amount_php-new_deposit,0);
  update plp_runtime.plp_bookings
  set deposit_amount_php=new_deposit,
      balance_amount_php=new_balance,
      payment_status=case
        when new_balance=0 then 'PAID'
        when new_deposit>0 then 'PARTIAL'
        else 'PENDING'
      end,
      updated_by=uid,
      updated_at=clock_timestamp()
  where id=booking.id
  returning * into booking;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,
    'providerReadbackVerified',payment.status='REFUNDED',
    'operation','payment.void_manual',
    'requestId',p_request_id,
    'payment',jsonb_build_object(
      'id',payment.id,
      'status',payment.status,
      'verificationStatus',payment.verification_status,
      'amountPhp',payment.amount_php
    ),
    'booking',jsonb_build_object(
      'id',booking.id,
      'paymentStatus',booking.payment_status,
      'depositAmountPhp',booking.deposit_amount_php,
      'balanceAmountPhp',booking.balance_amount_php
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'payment.void_manual','payment',payment.id,response
  );
end;
$voidpay$;

create or replace function public.plp_resort_access_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $access$
declare
  ctx jsonb := private.plp_membership_context_v1(null);
  role_name text := ctx->>'role';
begin
  return jsonb_build_object(
    'schemaVersion','plp.resort.access.v1',
    'role',role_name,
    'canOperate',role_name in ('owner','admin','operator'),
    'canAdmin',role_name in ('owner','admin'),
    'canManageTeam',role_name in ('owner','admin'),
    'canManageOwners',role_name='owner',
    'canView',true
  );
end;
$access$;

create or replace function public.plp_room_board_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $board$
declare
  ctx jsonb := private.plp_membership_context_v1(null);
  prop public.enterprise_properties%rowtype;
  business_date date;
  rooms jsonb;
  total_count integer;
  occupied_count integer;
  arrival_count integer;
  departure_count integer;
  available_count integer;
  not_ready_count integer;
begin
  select * into prop
  from public.enterprise_properties
  where slug='plp-boracay'
  order by updated_at desc,id desc
  limit 1;
  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  with board as (
    select
      a.*,
      coalesce(rs.state,'ready') as operational_state,
      rs.note as operational_note,
      rs.updated_at as operational_updated_at,
      case
        when exists (
          select 1 from plp_runtime.plp_bookings b
          where b.accommodation_id=a.id
            and b.check_out=business_date
            and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        ) then 'departure'
        when exists (
          select 1 from plp_runtime.plp_bookings b
          where b.accommodation_id=a.id
            and b.check_in=business_date
            and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        ) then 'arrival'
        when exists (
          select 1 from plp_runtime.plp_bookings b
          where b.accommodation_id=a.id
            and b.check_in<=business_date
            and b.check_out>business_date
            and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        ) then 'occupied'
        else 'available'
      end as stay_state
    from plp_runtime.plp_accommodations a
    left join plp_runtime.plp_room_states rs on rs.accommodation_id=a.id
    where a.is_active=true
  ), effective as (
    select *,
      case
        when operational_state<>'ready' then operational_state
        else stay_state
      end as effective_state
    from board
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'id',id,
        'name',name,
        'capacity',capacity,
        'bedrooms',bedrooms,
        'nightlyRatePhp',nightly_rate_php,
        'state',effective_state,
        'stayState',stay_state,
        'operationalState',operational_state,
        'operationalNote',operational_note,
        'operationalUpdatedAt',operational_updated_at
      ) order by name
    ),'[]'::jsonb),
    count(*)::integer,
    count(*) filter (where stay_state='occupied')::integer,
    count(*) filter (where stay_state='arrival')::integer,
    count(*) filter (where stay_state='departure')::integer,
    count(*) filter (where effective_state='available')::integer,
    count(*) filter (where operational_state<>'ready')::integer
  into rooms,total_count,occupied_count,arrival_count,departure_count,available_count,not_ready_count
  from effective;

  return jsonb_build_object(
    'schemaVersion','plp.room.board.v1',
    'businessDate',business_date,
    'rooms',rooms,
    'roomPulse',jsonb_build_object(
      'total',coalesce(total_count,0),
      'occupied',coalesce(occupied_count,0),
      'arriving',coalesce(arrival_count,0),
      'departing',coalesce(departure_count,0),
      'available',coalesce(available_count,0),
      'notReady',coalesce(not_ready_count,0)
    ),
    'truth',jsonb_build_object(
      'source','plp_accommodations + plp_bookings + plp_room_states',
      'projectionOnly',true
    )
  );
end;
$board$;

create or replace function public.plp_update_room_v1(
  p_request_id text,
  p_accommodation_id uuid,
  p_nightly_rate_php numeric,
  p_capacity integer,
  p_bedrooms integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  room plp_runtime.plp_accommodations%rowtype;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'room.update');
  if replay is not null then return replay; end if;
  if p_nightly_rate_php<0 or p_capacity<1 or p_bedrooms<0 then
    raise exception 'invalid room configuration' using errcode='22023';
  end if;

  update plp_runtime.plp_accommodations
  set nightly_rate_php=p_nightly_rate_php,capacity=p_capacity,bedrooms=p_bedrooms,
      is_active=p_is_active,updated_at=clock_timestamp()
  where id=p_accommodation_id
  returning * into room;
  if room.id is null then raise exception 'room not found' using errcode='P0002'; end if;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','room.update','requestId',p_request_id,
    'room',jsonb_build_object(
      'id',room.id,'name',room.name,'nightlyRatePhp',room.nightly_rate_php,
      'capacity',room.capacity,'bedrooms',room.bedrooms,'isActive',room.is_active
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'room.update','room',room.id,response
  );
end;
$$;

create or replace function public.plp_update_room_state_v1(
  p_request_id text,
  p_accommodation_id uuid,
  p_state text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  state_name text := lower(trim(coalesce(p_state,'')));
  room_state plp_runtime.plp_room_states%rowtype;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'room.state');
  if replay is not null then return replay; end if;
  if state_name not in ('ready','dirty','cleaning','inspection','maintenance','out_of_order') then
    raise exception 'invalid room operational state' using errcode='22023';
  end if;
  if not exists(select 1 from plp_runtime.plp_accommodations where id=p_accommodation_id) then
    raise exception 'room not found' using errcode='P0002';
  end if;

  insert into plp_runtime.plp_room_states(accommodation_id,state,note,updated_by,updated_at)
  values(p_accommodation_id,state_name,nullif(trim(coalesce(p_note,'')),''),uid,clock_timestamp())
  on conflict(accommodation_id) do update
  set state=excluded.state,note=excluded.note,updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning * into room_state;

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','room.state','requestId',p_request_id,
    'roomState',jsonb_build_object(
      'accommodationId',room_state.accommodation_id,'state',room_state.state,
      'note',room_state.note,'updatedAt',room_state.updated_at
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'room.state','room',p_accommodation_id,response
  );
end;
$$;

create or replace function public.plp_update_staff_task_v1(
  p_request_id text,
  p_task_id uuid,
  p_status text,
  p_priority text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  status_name text := lower(trim(coalesce(p_status,'')));
  priority_name text := lower(trim(coalesce(p_priority,'')));
  task plp_runtime.plp_staff_tasks%rowtype;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'task.update');
  if replay is not null then return replay; end if;
  if status_name not in ('open','in_progress','done','cancelled') then
    raise exception 'invalid task status' using errcode='22023';
  end if;
  if priority_name<>'' and priority_name not in ('normal','medium','high','critical') then
    raise exception 'invalid task priority' using errcode='22023';
  end if;

  update plp_runtime.plp_staff_tasks
  set status=status_name,
      priority=case when priority_name='' then priority else priority_name end,
      actor=uid::text,
      completed_at=case when status_name='done' then clock_timestamp() else null end,
      updated_at=clock_timestamp()
  where id=p_task_id
  returning * into task;
  if task.id is null then raise exception 'task not found' using errcode='P0002'; end if;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','task.update','requestId',p_request_id,
    'task',to_jsonb(task)
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'task.update','task',task.id,response
  );
end;
$$;

create or replace function public.plp_resolve_ota_conflict_v1(
  p_request_id text,
  p_conflict_id uuid,
  p_resolution_type text,
  p_resolution_note text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(array['owner','admin','operator']);
  uid uuid := (ctx->>'userId')::uuid;
  org uuid := (ctx->>'organizationId')::uuid;
  replay jsonb;
  conflict plp_runtime.plp_ota_conflicts%rowtype;
  response jsonb;
begin
  replay := private.plp_operation_replay_v1(org,uid,p_request_id,'channel.resolve');
  if replay is not null then return replay; end if;

  update plp_runtime.plp_ota_conflicts
  set status='resolved',
      resolution_status='resolved',
      resolution_type=nullif(trim(coalesce(p_resolution_type,'')),''),
      resolution_note=nullif(trim(coalesce(p_resolution_note,'')),''),
      resolved_by=uid::text,
      resolved_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=p_conflict_id
  returning * into conflict;
  if conflict.id is null then raise exception 'channel conflict not found' using errcode='P0002'; end if;

  perform public.enterprise_refresh_plp_runtime_overview_v1();

  response := jsonb_build_object(
    'verified',true,'providerReadbackVerified',true,
    'operation','channel.resolve','requestId',p_request_id,
    'conflict',jsonb_build_object(
      'id',conflict.id,'status',conflict.status,
      'resolutionStatus',conflict.resolution_status,
      'resolutionType',conflict.resolution_type,
      'resolutionNote',conflict.resolution_note
    )
  );
  return private.plp_operation_record_v1(
    org,uid,p_request_id,'channel.resolve','conflict',conflict.id,response
  );
end;
$$;

create or replace function public.plp_reservation_detail_v1(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(null);
  booking plp_runtime.plp_bookings%rowtype;
  guest plp_runtime.plp_guests%rowtype;
  payments jsonb;
begin
  select * into booking from plp_runtime.plp_bookings where id=p_booking_id;
  if booking.id is null then raise exception 'reservation not found' using errcode='P0002'; end if;
  select * into guest from plp_runtime.plp_guests where id=booking.guest_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'provider',p.provider,'reference',p.provider_reference_id,
    'amountPhp',p.amount_php,'status',p.status,
    'verificationStatus',p.verification_status,'paidAt',p.paid_at
  ) order by coalesce(p.paid_at,p.created_at) desc),'[]'::jsonb)
  into payments
  from plp_runtime.plp_payments p
  where p.booking_id=booking.id;

  return jsonb_build_object(
    'schemaVersion','plp.reservation.detail.v1',
    'actorRole',ctx->>'role',
    'permissions',jsonb_build_object(
      'canOperate',(ctx->>'role') in ('owner','admin','operator'),
      'canAdmin',(ctx->>'role') in ('owner','admin')
    ),
    'booking',jsonb_build_object(
      'id',booking.id,'bookingReference',booking.booking_reference,
      'accommodationId',booking.accommodation_id,'accommodationName',booking.accommodation_name,
      'checkIn',booking.check_in,'checkOut',booking.check_out,'guestCount',booking.guest_count,
      'nights',booking.nights,'ratePerNightPhp',booking.rate_per_night_php,
      'totalAmountPhp',booking.total_amount_php,'depositAmountPhp',booking.deposit_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,'status',booking.status,
      'paymentStatus',booking.payment_status,'specialRequest',booking.special_requests,
      'confirmedAt',booking.confirmed_at,'checkedInAt',booking.checked_in_at,
      'checkedOutAt',booking.checked_out_at,'cancelledAt',booking.cancelled_at
    ),
    'guest',jsonb_build_object(
      'id',guest.id,'fullName',guest.full_name,'email',guest.email,'phone',guest.phone
    ),
    'payments',payments
  );
end;
$$;

create or replace function public.plp_room_detail_v1(p_accommodation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  ctx jsonb := private.plp_membership_context_v1(null);
  room plp_runtime.plp_accommodations%rowtype;
  state_row plp_runtime.plp_room_states%rowtype;
begin
  select * into room from plp_runtime.plp_accommodations where id=p_accommodation_id;
  if room.id is null then raise exception 'room not found' using errcode='P0002'; end if;
  select * into state_row from plp_runtime.plp_room_states where accommodation_id=room.id;

  return jsonb_build_object(
    'schemaVersion','plp.room.detail.v1',
    'actorRole',ctx->>'role',
    'permissions',jsonb_build_object(
      'canOperate',(ctx->>'role') in ('owner','admin','operator'),
      'canAdmin',(ctx->>'role') in ('owner','admin')
    ),
    'room',jsonb_build_object(
      'id',room.id,'name',room.name,'nightlyRatePhp',room.nightly_rate_php,
      'capacity',room.capacity,'bedrooms',room.bedrooms,'isActive',room.is_active,
      'operationalState',coalesce(state_row.state,'ready'),
      'operationalNote',state_row.note,'stateUpdatedAt',state_row.updated_at
    )
  );
end;
$$;

revoke execute on function private.plp_reject_operation_receipt_mutation_v1() from public,anon,authenticated;
revoke execute on function private.plp_membership_context_v1(text[]) from public,anon,authenticated;
revoke execute on function private.plp_operation_replay_v1(uuid,uuid,text,text) from public,anon,authenticated;
revoke execute on function private.plp_operation_record_v1(uuid,uuid,text,text,text,uuid,jsonb) from public,anon,authenticated;

revoke execute on function public.plp_create_reservation_v1(text,text,text,text,uuid,date,date,integer,text) from public,anon;
revoke execute on function public.plp_update_reservation_v1(text,uuid,uuid,date,date,integer,text) from public,anon;
revoke execute on function public.plp_transition_reservation_v1(text,uuid,text) from public,anon;
revoke execute on function public.plp_update_guest_v1(text,uuid,text,text,text) from public,anon;
revoke execute on function public.plp_record_payment_v1(text,uuid,numeric,text,text) from public,anon;
revoke execute on function public.plp_void_manual_payment_v1(text,uuid,text) from public,anon;
revoke execute on function public.plp_resort_access_v1() from public,anon;
revoke execute on function public.plp_room_board_v1() from public,anon;
revoke execute on function public.plp_update_room_v1(text,uuid,numeric,integer,integer,boolean) from public,anon;
revoke execute on function public.plp_update_room_state_v1(text,uuid,text,text) from public,anon;
revoke execute on function public.plp_update_staff_task_v1(text,uuid,text,text) from public,anon;
revoke execute on function public.plp_resolve_ota_conflict_v1(text,uuid,text,text) from public,anon;
revoke execute on function public.plp_reservation_detail_v1(uuid) from public,anon;
revoke execute on function public.plp_room_detail_v1(uuid) from public,anon;

grant execute on function public.plp_create_reservation_v1(text,text,text,text,uuid,date,date,integer,text) to authenticated;
grant execute on function public.plp_update_reservation_v1(text,uuid,uuid,date,date,integer,text) to authenticated;
grant execute on function public.plp_transition_reservation_v1(text,uuid,text) to authenticated;
grant execute on function public.plp_update_guest_v1(text,uuid,text,text,text) to authenticated;
grant execute on function public.plp_record_payment_v1(text,uuid,numeric,text,text) to authenticated;
grant execute on function public.plp_void_manual_payment_v1(text,uuid,text) to authenticated;
grant execute on function public.plp_resort_access_v1() to authenticated;
grant execute on function public.plp_room_board_v1() to authenticated;
grant execute on function public.plp_update_room_v1(text,uuid,numeric,integer,integer,boolean) to authenticated;
grant execute on function public.plp_update_room_state_v1(text,uuid,text,text) to authenticated;
grant execute on function public.plp_update_staff_task_v1(text,uuid,text,text) to authenticated;
grant execute on function public.plp_resolve_ota_conflict_v1(text,uuid,text,text) to authenticated;
grant execute on function public.plp_reservation_detail_v1(uuid) to authenticated;
grant execute on function public.plp_room_detail_v1(uuid) to authenticated;
