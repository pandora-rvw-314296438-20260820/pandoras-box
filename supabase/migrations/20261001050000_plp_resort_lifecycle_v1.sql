create table if not exists plp_runtime.plp_operation_receipts (
  request_id text primary key,
  action text not null,
  actor_user_id uuid not null,
  organization_id uuid not null,
  entity_type text not null,
  entity_key text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint plp_operation_receipts_request_id_check
    check (length(request_id) between 8 and 160)
);

alter table plp_runtime.plp_operation_receipts enable row level security;
revoke all on table plp_runtime.plp_operation_receipts
  from public,anon,authenticated;

create or replace function private.plp_operation_receipt_immutable_v1()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  raise exception 'PLP operation receipts are immutable' using errcode='42501';
end;
$$;

drop trigger if exists plp_operation_receipts_immutable_v1
  on plp_runtime.plp_operation_receipts;
create trigger plp_operation_receipts_immutable_v1
before update or delete on plp_runtime.plp_operation_receipts
for each row execute function private.plp_operation_receipt_immutable_v1();

create or replace function private.plp_actor_context_v1(
  p_roles text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  if p_roles is not null
     and not (lower(member.role::text)=any(p_roles)) then
    raise exception 'PLP role is not authorized for this action'
      using errcode='42501';
  end if;

  return jsonb_build_object(
    'userId',uid,
    'organizationId',prop.organization_id,
    'propertyId',prop.id,
    'role',lower(member.role::text),
    'timezone',coalesce(nullif(prop.timezone,''),'Asia/Manila')
  );
end;
$$;

create or replace function private.plp_operation_replay_v1(
  p_request_id text,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  receipt plp_runtime.plp_operation_receipts%rowtype;
begin
  select * into receipt
  from plp_runtime.plp_operation_receipts r
  where r.request_id=p_request_id;

  if receipt.request_id is null then
    return null;
  end if;

  if receipt.action<>p_action then
    raise exception 'request id was already used for another PLP action'
      using errcode='22023';
  end if;

  return receipt.result || jsonb_build_object('idempotentReplay',true);
end;
$$;

create or replace function private.plp_operation_store_v1(
  p_request_id text,
  p_action text,
  p_actor_user_id uuid,
  p_organization_id uuid,
  p_entity_type text,
  p_entity_key text,
  p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into plp_runtime.plp_operation_receipts(
    request_id,action,actor_user_id,organization_id,
    entity_type,entity_key,result
  ) values (
    p_request_id,p_action,p_actor_user_id,p_organization_id,
    p_entity_type,p_entity_key,p_result
  );

  return p_result || jsonb_build_object('idempotentReplay',false);
end;
$$;

create or replace function public.plp_reservation_detail_v1(
  p_booking_reference text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor jsonb;
  b plp_runtime.plp_bookings%rowtype;
  g plp_runtime.plp_guests%rowtype;
begin
  actor := private.plp_actor_context_v1(array['owner','admin','operator','member']);

  select * into b
  from plp_runtime.plp_bookings x
  where x.booking_reference=trim(p_booking_reference)
  limit 1;

  if b.id is null then
    raise exception 'booking not found' using errcode='P0002';
  end if;

  select * into g
  from plp_runtime.plp_guests x
  where x.id=b.guest_id;

  return jsonb_build_object(
    'schemaVersion','plp.reservation.detail.v1',
    'bookingReference',b.booking_reference,
    'bookingId',b.id,
    'guestId',g.id,
    'fullName',g.full_name,
    'email',g.email,
    'phone',g.phone,
    'accommodationId',b.accommodation_id,
    'accommodationName',b.accommodation_name,
    'checkIn',b.check_in,
    'checkOut',b.check_out,
    'guestCount',b.guest_count,
    'nights',b.nights,
    'ratePerNightPhp',b.rate_per_night_php,
    'totalAmountPhp',b.total_amount_php,
    'balanceAmountPhp',b.balance_amount_php,
    'status',b.status,
    'paymentStatus',b.payment_status,
    'specialRequests',b.special_requests,
    'source',b.source,
    'canManage',actor->>'role' in ('owner','admin','operator')
  );
end;
$$;

create or replace function public.plp_reservation_create_v1(
  p_request_id text,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text,
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
  actor jsonb;
  replay jsonb;
  room plp_runtime.plp_accommodations%rowtype;
  guest plp_runtime.plp_guests%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  uid uuid;
  org_id uuid;
  v_email text := lower(trim(coalesce(p_guest_email,'')));
  v_guest_name text := trim(coalesce(p_guest_name,''));
  reference text;
  nights_count integer;
  result jsonb;
begin
  if p_request_id is null or length(trim(p_request_id))<8 then
    raise exception 'valid request id required' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );

  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'create_reservation'
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin','operator']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  if v_guest_name='' then
    raise exception 'guest name required' using errcode='22023';
  end if;
  if v_email='' or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'valid guest email required' using errcode='22023';
  end if;
  if p_check_in is null or p_check_out is null or p_check_out<=p_check_in then
    raise exception 'valid stay dates required' using errcode='22023';
  end if;
  if coalesce(p_guest_count,0)<=0 then
    raise exception 'guest count must be positive' using errcode='22023';
  end if;

  select * into room
  from plp_runtime.plp_accommodations a
  where a.id=p_accommodation_id and a.is_active=true
  for share;
  if room.id is null then
    raise exception 'active room not found' using errcode='P0002';
  end if;
  if p_guest_count>room.capacity then
    raise exception 'guest count exceeds room capacity' using errcode='22023';
  end if;

  if exists (
    select 1 from plp_runtime.plp_bookings b
    where b.accommodation_id=room.id
      and b.check_in<p_check_out
      and b.check_out>p_check_in
      and upper(coalesce(b.status,'')) not in
        ('CANCELLED','CANCELED','CHECKED_OUT')
  ) then
    raise exception 'room is not available for the requested dates'
      using errcode='23P01';
  end if;

  select * into guest
  from plp_runtime.plp_guests g
  where lower(coalesce(nullif(g.normalized_email,''),g.email))=v_email
  order by g.updated_at desc,g.id
  limit 1
  for update;

  if guest.id is null then
    insert into plp_runtime.plp_guests(
      full_name,email,phone,metadata
    ) values (
      v_guest_name,v_email,nullif(trim(coalesce(p_guest_phone,'')),''),

      jsonb_build_object('source','pandora_plp_mobile')
    )
    returning * into guest;
  else
    update plp_runtime.plp_guests
    set full_name=v_guest_name,
        email=v_email,
        phone=nullif(trim(coalesce(p_guest_phone,'')),''),
        updated_at=clock_timestamp()
    where id=guest.id
    returning * into guest;
  end if;

  nights_count := p_check_out-p_check_in;
  reference := 'PLP-' ||
    upper(substr(pg_catalog.md5(trim(p_request_id)),1,10));

  if exists (
    select 1 from plp_runtime.plp_bookings b
    where b.booking_reference=reference
  ) then
    raise exception 'generated booking reference collision'
      using errcode='23505';
  end if;

  insert into plp_runtime.plp_bookings(
    booking_reference,guest_id,accommodation_id,accommodation_name,
    check_in,check_out,guest_count,nights,rate_per_night_php,
    total_amount_php,deposit_amount_php,balance_amount_php,
    status,payment_status,special_requests,source,confirmed_at
  ) values (
    reference,guest.id,room.id,room.name,
    p_check_in,p_check_out,p_guest_count,nights_count,room.nightly_rate_php,
    room.nightly_rate_php*nights_count,0,room.nightly_rate_php*nights_count,
    'CONFIRMED','PENDING',
    nullif(trim(coalesce(p_special_requests,'')),''),
    'pandora_plp_mobile',clock_timestamp()
  )
  returning * into booking;

  select jsonb_build_object(
    'schemaVersion','plp.reservation.write.v1',
    'verified',true,
    'providerReadbackVerified',
      b.id=booking.id and b.booking_reference=reference,
    'action','create_reservation',
    'bookingId',b.id,
    'bookingReference',b.booking_reference,
    'guestId',b.guest_id,
    'accommodationId',b.accommodation_id,
    'accommodationName',b.accommodation_name,
    'checkIn',b.check_in,
    'checkOut',b.check_out,
    'guestCount',b.guest_count,
    'status',b.status,
    'paymentStatus',b.payment_status,
    'totalAmountPhp',b.total_amount_php,
    'balanceAmountPhp',b.balance_amount_php
  ) into result
  from plp_runtime.plp_bookings b
  where b.id=booking.id;

  return private.plp_operation_store_v1(
    trim(p_request_id),'create_reservation',uid,org_id,
    'booking',booking.id::text,result
  );
end;
$$;

create or replace function public.plp_reservation_update_v1(
  p_request_id text,
  p_booking_reference text,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor jsonb;
  replay jsonb;
  b plp_runtime.plp_bookings%rowtype;
  room plp_runtime.plp_accommodations%rowtype;
  uid uuid;
  org_id uuid;
  new_room_id uuid;
  new_check_in date;
  new_check_out date;
  new_guest_count integer;
  new_special text;
  new_rate numeric;
  result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );
  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'update_reservation'
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin','operator']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  select * into b
  from plp_runtime.plp_bookings x
  where x.booking_reference=trim(p_booking_reference)
  for update;
  if b.id is null then
    raise exception 'booking not found' using errcode='P0002';
  end if;
  if upper(coalesce(b.status,'')) in
    ('CANCELLED','CANCELED','CHECKED_OUT') then
    raise exception 'finalized booking cannot be edited' using errcode='22023';
  end if;

  new_room_id := case when p_patch ? 'accommodationId'
    then (p_patch->>'accommodationId')::uuid else b.accommodation_id end;
  new_check_in := case when p_patch ? 'checkIn'
    then (p_patch->>'checkIn')::date else b.check_in end;
  new_check_out := case when p_patch ? 'checkOut'
    then (p_patch->>'checkOut')::date else b.check_out end;
  new_guest_count := case when p_patch ? 'guestCount'
    then (p_patch->>'guestCount')::integer else b.guest_count end;
  new_special := case when p_patch ? 'specialRequests'
    then nullif(trim(coalesce(p_patch->>'specialRequests','')),'')
    else b.special_requests end;

  if new_check_out<=new_check_in then
    raise exception 'valid stay dates required' using errcode='22023';
  end if;
  if new_guest_count<=0 then
    raise exception 'guest count must be positive' using errcode='22023';
  end if;

  select * into room
  from plp_runtime.plp_accommodations a
  where a.id=new_room_id and a.is_active=true
  for share;
  if room.id is null then
    raise exception 'active room not found' using errcode='P0002';
  end if;
  if new_guest_count>room.capacity then
    raise exception 'guest count exceeds room capacity' using errcode='22023';
  end if;

  if exists (
    select 1 from plp_runtime.plp_bookings other
    where other.accommodation_id=room.id
      and other.id<>b.id
      and other.check_in<new_check_out
      and other.check_out>new_check_in
      and upper(coalesce(other.status,'')) not in
        ('CANCELLED','CANCELED','CHECKED_OUT')
  ) then
    raise exception 'room is not available for the requested dates'
      using errcode='23P01';
  end if;

  new_rate := case
    when new_room_id is distinct from b.accommodation_id
      then room.nightly_rate_php
    else b.rate_per_night_php
  end;

  update plp_runtime.plp_bookings
  set accommodation_id=room.id,
      accommodation_name=room.name,
      check_in=new_check_in,
      check_out=new_check_out,
      guest_count=new_guest_count,
      nights=new_check_out-new_check_in,
      rate_per_night_php=new_rate,
      total_amount_php=new_rate*(new_check_out-new_check_in),
      balance_amount_php=greatest(
        new_rate*(new_check_out-new_check_in)
        - coalesce((
          select sum(p.amount_php)
          from plp_runtime.plp_payments p
          where p.booking_id=b.id
            and lower(coalesce(p.status,'')) in
              ('paid','succeeded','complete','completed')
        ),0),
        0
      ),
      special_requests=new_special,
      updated_at=clock_timestamp()
  where id=b.id
  returning * into b;

  result := jsonb_build_object(
    'schemaVersion','plp.reservation.write.v1',
    'verified',true,
    'providerReadbackVerified',true,
    'action','update_reservation',
    'bookingId',b.id,
    'bookingReference',b.booking_reference,
    'accommodationId',b.accommodation_id,
    'accommodationName',b.accommodation_name,
    'checkIn',b.check_in,
    'checkOut',b.check_out,
    'guestCount',b.guest_count,
    'status',b.status,
    'paymentStatus',b.payment_status,
    'totalAmountPhp',b.total_amount_php,
    'balanceAmountPhp',b.balance_amount_php,
    'specialRequests',b.special_requests
  );

  return private.plp_operation_store_v1(
    trim(p_request_id),'update_reservation',uid,org_id,
    'booking',b.id::text,result
  );
end;
$$;

create or replace function public.plp_reservation_transition_v1(
  p_request_id text,
  p_booking_reference text,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor jsonb;
  replay jsonb;
  b plp_runtime.plp_bookings%rowtype;
  uid uuid;
  org_id uuid;
  action_name text := lower(trim(coalesce(p_action,'')));
  old_status text;
  result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );
  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'transition_reservation:'||action_name
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin','operator']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  select * into b
  from plp_runtime.plp_bookings x
  where x.booking_reference=trim(p_booking_reference)
  for update;
  if b.id is null then
    raise exception 'booking not found' using errcode='P0002';
  end if;

  old_status := upper(coalesce(b.status,''));
  if action_name='check_in' then
    if old_status not in ('CONFIRMED','PENDING_PAYMENT') then
      raise exception 'booking is not eligible for check-in' using errcode='22023';
    end if;
    update plp_runtime.plp_bookings
    set status='CHECKED_IN',
        confirmed_at=coalesce(confirmed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=b.id returning * into b;
  elsif action_name='check_out' then
    if old_status not in ('CHECKED_IN','IN_HOUSE') then
      raise exception 'booking is not eligible for check-out' using errcode='22023';
    end if;
    update plp_runtime.plp_bookings
    set status='CHECKED_OUT',updated_at=clock_timestamp()
    where id=b.id returning * into b;
  elsif action_name='cancel' then
    if old_status in ('CHECKED_OUT','CANCELLED','CANCELED') then
      raise exception 'booking is already finalized' using errcode='22023';
    end if;
    update plp_runtime.plp_bookings
    set status='CANCELLED',
        cancelled_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=b.id returning * into b;
  else
    raise exception 'unsupported reservation transition' using errcode='22023';
  end if;

  result := jsonb_build_object(
    'schemaVersion','plp.reservation.write.v1',
    'verified',true,
    'providerReadbackVerified',true,
    'action',action_name,
    'bookingId',b.id,
    'bookingReference',b.booking_reference,
    'previousStatus',old_status,
    'status',b.status,
    'paymentStatus',b.payment_status,
    'balanceAmountPhp',b.balance_amount_php
  );

  return private.plp_operation_store_v1(
    trim(p_request_id),'transition_reservation:'||action_name,
    uid,org_id,'booking',b.id::text,result
  );
end;
$$;

create or replace function public.plp_guest_update_v1(
  p_request_id text,
  p_booking_reference text,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor jsonb;
  replay jsonb;
  b plp_runtime.plp_bookings%rowtype;
  g plp_runtime.plp_guests%rowtype;
  uid uuid;
  org_id uuid;
  new_name text;
  new_email text;
  new_phone text;
  new_special text;
  result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );
  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'update_guest'
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin','operator']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  select * into b
  from plp_runtime.plp_bookings x
  where x.booking_reference=trim(p_booking_reference)
  for update;
  if b.id is null then
    raise exception 'booking not found' using errcode='P0002';
  end if;

  select * into g
  from plp_runtime.plp_guests x
  where x.id=b.guest_id
  for update;
  if g.id is null then
    raise exception 'guest not found' using errcode='P0002';
  end if;

  new_name := case when p_patch ? 'fullName'
    then trim(coalesce(p_patch->>'fullName','')) else g.full_name end;
  new_email := lower(case when p_patch ? 'email'
    then trim(coalesce(p_patch->>'email','')) else g.email end);
  new_phone := case when p_patch ? 'phone'
    then nullif(trim(coalesce(p_patch->>'phone','')),'') else g.phone end;
  new_special := case when p_patch ? 'specialRequests'
    then nullif(trim(coalesce(p_patch->>'specialRequests','')),'')
    else b.special_requests end;

  if new_name='' then
    raise exception 'guest name required' using errcode='22023';
  end if;
  if new_email='' or new_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'valid guest email required' using errcode='22023';
  end if;
  if exists (
    select 1 from plp_runtime.plp_guests other
    where other.id<>g.id
      and lower(coalesce(nullif(other.normalized_email,''),other.email))=new_email
  ) then
    raise exception 'guest email already belongs to another guest'
      using errcode='23505';
  end if;

  update plp_runtime.plp_guests
  set full_name=new_name,
      email=new_email,
      phone=new_phone,
      updated_at=clock_timestamp()
  where id=g.id
  returning * into g;

  update plp_runtime.plp_bookings
  set special_requests=new_special,
      updated_at=clock_timestamp()
  where id=b.id
  returning * into b;

  result := jsonb_build_object(
    'schemaVersion','plp.guest.write.v1',
    'verified',true,
    'providerReadbackVerified',true,
    'action','update_guest',
    'bookingReference',b.booking_reference,
    'guestId',g.id,
    'fullName',g.full_name,
    'specialRequests',b.special_requests
  );

  return private.plp_operation_store_v1(
    trim(p_request_id),'update_guest',uid,org_id,
    'guest',g.id::text,result
  );
end;
$$;

create or replace function public.plp_payment_record_v1(
  p_request_id text,
  p_booking_reference text,
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
  actor jsonb;
  replay jsonb;
  b plp_runtime.plp_bookings%rowtype;
  payment plp_runtime.plp_payments%rowtype;
  uid uuid;
  org_id uuid;
  method_name text := lower(trim(coalesce(p_method,'')));
  paid_total numeric := 0;
  new_balance numeric := 0;
  result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );
  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'record_payment'
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin','operator']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  select * into b
  from plp_runtime.plp_bookings x
  where x.booking_reference=trim(p_booking_reference)
  for update;
  if b.id is null then
    raise exception 'booking not found' using errcode='P0002';
  end if;
  if upper(coalesce(b.status,'')) in ('CANCELLED','CANCELED') then
    raise exception 'cannot record payment on a cancelled booking'
      using errcode='22023';
  end if;
  if coalesce(p_amount_php,0)<=0 then
    raise exception 'payment amount must be positive' using errcode='22023';
  end if;
  if p_amount_php>b.balance_amount_php then
    raise exception 'payment amount exceeds outstanding balance'
      using errcode='22023';
  end if;
  if method_name not in ('cash','card','bank_transfer','wallet','other') then
    raise exception 'unsupported payment method' using errcode='22023';
  end if;

  if nullif(trim(coalesce(p_reference,'')),'') is not null
     and exists (
       select 1 from plp_runtime.plp_payments p
       where p.booking_id=b.id
         and p.provider_reference_id=trim(p_reference)
     ) then
    raise exception 'payment reference already recorded' using errcode='23505';
  end if;

  insert into plp_runtime.plp_payments(
    booking_id,provider,provider_reference_id,
    amount_php,currency,status,verification_status,
    raw_response,paid_at
  ) values (
    b.id,'manual:'||method_name,
    nullif(trim(coalesce(p_reference,'')),''),
    p_amount_php,'PHP','PAID','VERIFIED',
    jsonb_build_object(
      'source','pandora_plp_mobile',
      'recordedBy',uid,
      'method',method_name
    ),
    clock_timestamp()
  )
  returning * into payment;

  select coalesce(sum(p.amount_php),0)
  into paid_total
  from plp_runtime.plp_payments p
  where p.booking_id=b.id
    and lower(coalesce(p.status,'')) in
      ('paid','succeeded','complete','completed');

  new_balance := greatest(b.total_amount_php-paid_total,0);
  update plp_runtime.plp_bookings
  set balance_amount_php=new_balance,
      payment_status=case
        when new_balance=0 then 'PAID'
        when paid_total>0 then 'PARTIALLY_PAID'
        else payment_status
      end,
      updated_at=clock_timestamp()
  where id=b.id
  returning * into b;

  result := jsonb_build_object(
    'schemaVersion','plp.payment.write.v1',
    'verified',true,
    'providerReadbackVerified',
      payment.id is not null and b.id is not null,
    'action','record_payment',
    'paymentId',payment.id,
    'bookingReference',b.booking_reference,
    'amountPhp',payment.amount_php,
    'method',method_name,
    'paymentStatus',b.payment_status,
    'balanceAmountPhp',b.balance_amount_php
  );

  return private.plp_operation_store_v1(
    trim(p_request_id),'record_payment',uid,org_id,
    'payment',payment.id::text,result
  );
end;
$$;

create or replace function public.plp_room_update_v1(
  p_request_id text,
  p_accommodation_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor jsonb;
  replay jsonb;
  room plp_runtime.plp_accommodations%rowtype;
  uid uuid;
  org_id uuid;
  new_rate numeric;
  new_capacity integer;
  new_bedrooms integer;
  new_active boolean;
  new_metadata jsonb;
  result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(trim(p_request_id),0)
  );
  replay := private.plp_operation_replay_v1(
    trim(p_request_id),'update_room'
  );
  if replay is not null then return replay; end if;

  actor := private.plp_actor_context_v1(array['owner','admin']);
  uid := (actor->>'userId')::uuid;
  org_id := (actor->>'organizationId')::uuid;

  select * into room
  from plp_runtime.plp_accommodations a
  where a.id=p_accommodation_id
  for update;
  if room.id is null then
    raise exception 'room not found' using errcode='P0002';
  end if;

  new_rate := case when p_patch ? 'nightlyRatePhp'
    then (p_patch->>'nightlyRatePhp')::numeric else room.nightly_rate_php end;
  new_capacity := case when p_patch ? 'capacity'
    then (p_patch->>'capacity')::integer else room.capacity end;
  new_bedrooms := case when p_patch ? 'bedrooms'
    then (p_patch->>'bedrooms')::integer else room.bedrooms end;
  new_active := case when p_patch ? 'isActive'
    then (p_patch->>'isActive')::boolean else room.is_active end;
  new_metadata := room.metadata ||
    coalesce(p_patch->'metadataPatch','{}'::jsonb);

  if new_rate<0 or new_capacity<=0 or new_bedrooms<0 then
    raise exception 'invalid room configuration' using errcode='22023';
  end if;

  if room.is_active and not new_active and exists (
    select 1 from plp_runtime.plp_bookings b
    where b.accommodation_id=room.id
      and b.check_out>=current_date
      and upper(coalesce(b.status,'')) not in
        ('CANCELLED','CANCELED','CHECKED_OUT')
  ) then
    raise exception 'room with active/future bookings cannot be deactivated'
      using errcode='22023';
  end if;

  update plp_runtime.plp_accommodations
  set nightly_rate_php=new_rate,
      capacity=new_capacity,
      bedrooms=new_bedrooms,
      is_active=new_active,
      metadata=new_metadata,
      updated_at=clock_timestamp()
  where id=room.id
  returning * into room;

  result := jsonb_build_object(
    'schemaVersion','plp.room.write.v1',
    'verified',true,
    'providerReadbackVerified',true,
    'action','update_room',
    'accommodationId',room.id,
    'name',room.name,
    'nightlyRatePhp',room.nightly_rate_php,
    'capacity',room.capacity,
    'bedrooms',room.bedrooms,
    'isActive',room.is_active
  );

  return private.plp_operation_store_v1(
    trim(p_request_id),'update_room',uid,org_id,
    'room',room.id::text,result
  );
end;
$$;

revoke all on function public.plp_reservation_detail_v1(text)
  from public,anon;
grant execute on function public.plp_reservation_detail_v1(text)
  to authenticated;

revoke all on function public.plp_reservation_create_v1(
  text,text,text,text,uuid,date,date,integer,text
) from public,anon;
grant execute on function public.plp_reservation_create_v1(
  text,text,text,text,uuid,date,date,integer,text
) to authenticated;

revoke all on function public.plp_reservation_update_v1(text,text,jsonb)
  from public,anon;
grant execute on function public.plp_reservation_update_v1(text,text,jsonb)
  to authenticated;

revoke all on function public.plp_reservation_transition_v1(text,text,text)
  from public,anon;
grant execute on function public.plp_reservation_transition_v1(text,text,text)
  to authenticated;

revoke all on function public.plp_guest_update_v1(text,text,jsonb)
  from public,anon;
grant execute on function public.plp_guest_update_v1(text,text,jsonb)
  to authenticated;

revoke all on function public.plp_payment_record_v1(
  text,text,numeric,text,text
) from public,anon;
grant execute on function public.plp_payment_record_v1(
  text,text,numeric,text,text
) to authenticated;

revoke all on function public.plp_room_update_v1(text,uuid,jsonb)
  from public,anon;
grant execute on function public.plp_room_update_v1(text,uuid,jsonb)
  to authenticated;
