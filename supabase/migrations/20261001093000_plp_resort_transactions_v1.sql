
-- PLP resort business actions.
-- Normal resort pages call this bounded provider mutation surface; Pandora chat
-- remains an optional command layer, not the only way to operate the resort.

create table if not exists private.plp_resort_action_receipts (
  request_id text primary key,
  organization_id uuid not null,
  user_id uuid not null,
  action text not null,
  resource_type text not null,
  resource_id uuid,
  request_sha256 text not null,
  provider_readback jsonb not null,
  created_at timestamptz not null default now()
);

revoke all on table private.plp_resort_action_receipts
  from public, anon, authenticated;

create or replace function private.plp_resort_access_context_v1(
  p_allowed_roles text[] default null
)
returns table(
  organization_id uuid,
  property_id uuid,
  user_id uuid,
  access_role text,
  actor_label text,
  business_date date
)
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  label text;
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

  if p_allowed_roles is not null
     and not (member.role::text = any(p_allowed_roles)) then
    raise exception 'PLP role is not authorized for this action' using errcode='42501';
  end if;

  select nullif(trim(p.display_name),'') into label
  from public.profiles p
  where p.id=uid;

  return query
  select
    prop.organization_id,
    prop.id,
    uid,
    member.role::text,
    coalesce(label,'PLP user'),
    (clock_timestamp() at time zone
      coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;
end;
$$;

revoke all on function private.plp_resort_access_context_v1(text[])
  from public,anon,authenticated;

create or replace function public.plp_resort_guest_detail_v1(
  p_guest_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  ctx record;
  guest plp_runtime.plp_guests%rowtype;
  stays jsonb := '[]'::jsonb;
begin
  select * into ctx
  from private.plp_resort_access_context_v1(
    array['owner','admin','operator']::text[]
  );

  select * into guest
  from plp_runtime.plp_guests g
  where g.id=p_guest_id
    and exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.guest_id=g.id
    )
  limit 1;

  if guest.id is null then
    raise exception 'PLP guest not found' using errcode='P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',b.id,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'status',b.status,
        'paymentStatus',b.payment_status,
        'balanceAmountPhp',b.balance_amount_php
      )
      order by b.check_in desc
    ),
    '[]'::jsonb
  )
  into stays
  from plp_runtime.plp_bookings b
  where b.guest_id=guest.id;

  return jsonb_build_object(
    'schemaVersion','plp.resort.guest-detail.v1',
    'id',guest.id,
    'fullName',guest.full_name,
    'email',guest.email,
    'phone',guest.phone,
    'vip',coalesce((guest.metadata->>'vip')::boolean,false),
    'preferences',nullif(trim(coalesce(guest.metadata->>'preferences','')),''),
    'stays',stays,
    'contactDetailsAuthorized',true,
    'accessRole',ctx.access_role
  );
end;
$$;

revoke all on function public.plp_resort_guest_detail_v1(uuid)
  from public,anon;
grant execute on function public.plp_resort_guest_detail_v1(uuid)
  to authenticated,service_role;

create or replace function public.plp_resort_action_v1(
  p_request_id text,
  p_action text,
  p_resource_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  request_id text := trim(coalesce(p_request_id,''));
  action_name text := lower(trim(coalesce(p_action,'')));
  payload jsonb := coalesce(p_payload,'{}'::jsonb);
  ctx record;
  allowed_roles text[];
  request_sha text;
  prior private.plp_resort_action_receipts%rowtype;
  result jsonb;
  resource_type text;
  result_resource_id uuid;

  booking plp_runtime.plp_bookings%rowtype;
  booking_readback plp_runtime.plp_bookings%rowtype;
  guest plp_runtime.plp_guests%rowtype;
  guest_readback plp_runtime.plp_guests%rowtype;
  room plp_runtime.plp_accommodations%rowtype;
  room_readback plp_runtime.plp_accommodations%rowtype;
  payment plp_runtime.plp_payments%rowtype;
  task plp_runtime.plp_staff_tasks%rowtype;
  task_readback plp_runtime.plp_staff_tasks%rowtype;

  guest_full_name_value text;
  guest_email_value text;
  guest_normalized_email_value text;
  guest_phone_value text;
  guest_id uuid;
  room_id uuid;
  check_in_date date;
  check_out_date date;
  guest_count_value integer;
  nights_value integer;
  rate_value numeric;
  total_value numeric;
  paid_value numeric;
  balance_value numeric;
  special_requests_value text;
  booking_reference_value text;
  operational_state text;
  payment_method text;
  payment_reference text;
  payment_amount numeric;
  target_status text;
  target_priority text;
  target_note text;
  current_state text;
  can_override boolean;
  now_utc timestamptz := clock_timestamp();
begin
  if length(request_id) not between 8 and 160
     or request_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'invalid PLP resort action request id' using errcode='22023';
  end if;

  if action_name not in (
    'reservation.create',
    'reservation.update',
    'reservation.check_in',
    'reservation.check_out',
    'reservation.cancel',
    'guest.update',
    'room.update',
    'payment.record',
    'task.update'
  ) then
    raise exception 'unsupported PLP resort action' using errcode='22023';
  end if;

  allowed_roles := case
    when action_name='reservation.cancel'
      then array['owner','admin']::text[]
    when action_name='task.update'
      then array['owner','admin','operator','member']::text[]
    else array['owner','admin','operator']::text[]
  end;

  select * into ctx
  from private.plp_resort_access_context_v1(allowed_roles);

  can_override := ctx.access_role in ('owner','admin');

  request_sha := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          'plp-resort-action-v1',
          ctx.organization_id::text,
          ctx.user_id::text,
          request_id,
          action_name,
          coalesce(p_resource_id::text,''),
          payload::text
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into prior
  from private.plp_resort_action_receipts r
  where r.request_id=request_id;

  if prior.request_id is not null then
    if prior.organization_id<>ctx.organization_id
       or prior.user_id<>ctx.user_id
       or prior.action<>action_name
       or prior.request_sha256<>request_sha then
      raise exception 'PLP resort action request id collision' using errcode='23505';
    end if;

    return prior.provider_readback ||
      jsonb_build_object(
        'idempotentReplay',true,
        'providerReadbackVerified',true
      );
  end if;

  if action_name='reservation.create' then
    resource_type := 'reservation';

    guest_full_name_value := trim(coalesce(payload->>'guestFullName',''));
    guest_email_value := lower(trim(coalesce(payload->>'guestEmail','')));
    guest_normalized_email_value := nullif(guest_email_value,'');
    guest_phone_value := nullif(trim(coalesce(payload->>'guestPhone','')),'');
    room_id := nullif(trim(coalesce(payload->>'accommodationId','')),'')::uuid;
    check_in_date := nullif(trim(coalesce(payload->>'checkIn','')),'')::date;
    check_out_date := nullif(trim(coalesce(payload->>'checkOut','')),'')::date;
    guest_count_value := coalesce(nullif(payload->>'guestCount','')::integer,1);
    special_requests_value := nullif(trim(coalesce(payload->>'specialRequests','')),'');

    if length(guest_full_name_value) not between 2 and 160 then
      raise exception 'guest full name is required' using errcode='22023';
    end if;
    if guest_normalized_email_value is null
       or guest_normalized_email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      raise exception 'valid guest email is required' using errcode='22023';
    end if;
    if check_in_date is null or check_out_date is null
       or check_out_date<=check_in_date then
      raise exception 'valid reservation dates are required' using errcode='22023';
    end if;

    select * into room
    from plp_runtime.plp_accommodations a
    where a.id=room_id
      and a.is_active=true
    for update;

    if room.id is null then
      raise exception 'active PLP room not found' using errcode='P0002';
    end if;
    if guest_count_value<1 or guest_count_value>room.capacity then
      raise exception 'guest count exceeds room capacity' using errcode='22023';
    end if;
    if lower(coalesce(room.metadata->>'operational_state','ready'))='out_of_service' then
      raise exception 'room is out of service' using errcode='55000';
    end if;

    if exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id
        and b.check_in<check_out_date
        and b.check_out>check_in_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    ) then
      raise exception 'room is not available for the requested dates' using errcode='23514';
    end if;

    rate_value := room.nightly_rate_php;
    if payload ? 'ratePerNightPhp' then
      if not can_override then
        raise exception 'only owner or admin can override room rate' using errcode='42501';
      end if;
      rate_value := (payload->>'ratePerNightPhp')::numeric;
    end if;
    if rate_value<0 then
      raise exception 'room rate cannot be negative' using errcode='22023';
    end if;

    nights_value := check_out_date-check_in_date;
    total_value := rate_value*nights_value;

    select * into guest
    from plp_runtime.plp_guests g
    where g.normalized_email=guest_normalized_email_value
    limit 1
    for update;

    if guest.id is null then
      insert into plp_runtime.plp_guests(
        full_name,email,normalized_email,phone,metadata
      ) values (
        guest_full_name_value,guest_email_value,guest_normalized_email_value,guest_phone_value,'{}'::jsonb
      )
      returning * into guest;
    else
      update plp_runtime.plp_guests
      set full_name=guest_full_name_value,
          email=guest_email_value,
          phone=coalesce(guest_phone_value,plp_guests.phone),
          updated_at=now_utc
      where id=guest.id
      returning * into guest;
    end if;

    booking_reference_value :=
      'PLP-' || upper(substr(request_sha,1,12));

    insert into plp_runtime.plp_bookings(
      booking_reference,
      guest_id,
      accommodation_id,
      accommodation_name,
      check_in,
      check_out,
      guest_count,
      nights,
      rate_per_night_php,
      total_amount_php,
      deposit_amount_php,
      balance_amount_php,
      status,
      payment_status,
      special_requests,
      source,
      confirmed_at
    ) values (
      booking_reference_value,
      guest.id,
      room.id,
      room.name,
      check_in_date,
      check_out_date,
      guest_count_value,
      nights_value,
      rate_value,
      total_value,
      0,
      total_value,
      'CONFIRMED',
      'PENDING',
      special_requests_value,
      'pandora_plp_mobile',
      now_utc
    )
    returning * into booking;

    select * into booking_readback
    from plp_runtime.plp_bookings b
    where b.id=booking.id;

    if booking_readback.id is null
       or booking_readback.booking_reference<>booking_reference_value
       or upper(booking_readback.status)<>'CONFIRMED' then
      raise exception 'reservation provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := booking_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.reservation.create',
      'requestId',request_id,
      'resourceType','reservation',
      'resourceId',booking_readback.id,
      'bookingReference',booking_readback.booking_reference,
      'guestId',booking_readback.guest_id,
      'guestName',guest.full_name,
      'accommodationId',booking_readback.accommodation_id,
      'accommodationName',booking_readback.accommodation_name,
      'checkIn',booking_readback.check_in,
      'checkOut',booking_readback.check_out,
      'guestCount',booking_readback.guest_count,
      'status',booking_readback.status,
      'paymentStatus',booking_readback.payment_status,
      'totalAmountPhp',booking_readback.total_amount_php,
      'balanceAmountPhp',booking_readback.balance_amount_php,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  elsif action_name='reservation.update' then
    resource_type := 'reservation';
    if p_resource_id is null then
      raise exception 'reservation resource id is required' using errcode='22023';
    end if;

    select * into booking
    from plp_runtime.plp_bookings b
    where b.id=p_resource_id
    for update;

    if booking.id is null then
      raise exception 'PLP reservation not found' using errcode='P0002';
    end if;
    if upper(coalesce(booking.status,'')) in
      ('CANCELLED','CANCELED','CHECKED_OUT') then
      raise exception 'terminal reservation cannot be edited' using errcode='55000';
    end if;

    room_id := case
      when payload ? 'accommodationId'
        then nullif(trim(coalesce(payload->>'accommodationId','')),'')::uuid
      else booking.accommodation_id
    end;
    check_in_date := case
      when payload ? 'checkIn' then (payload->>'checkIn')::date
      else booking.check_in
    end;
    check_out_date := case
      when payload ? 'checkOut' then (payload->>'checkOut')::date
      else booking.check_out
    end;
    guest_count_value := case
      when payload ? 'guestCount' then (payload->>'guestCount')::integer
      else booking.guest_count
    end;
    special_requests_value := case
      when payload ? 'specialRequests'
        then nullif(trim(coalesce(payload->>'specialRequests','')),'')
      else booking.special_requests
    end;

    if check_out_date<=check_in_date then
      raise exception 'check-out must be after check-in' using errcode='22023';
    end if;

    select * into room
    from plp_runtime.plp_accommodations a
    where a.id=room_id
      and a.is_active=true
    for update;

    if room.id is null then
      raise exception 'active PLP room not found' using errcode='P0002';
    end if;
    if guest_count_value<1 or guest_count_value>room.capacity then
      raise exception 'guest count exceeds room capacity' using errcode='22023';
    end if;
    if lower(coalesce(room.metadata->>'operational_state','ready'))='out_of_service' then
      raise exception 'room is out of service' using errcode='55000';
    end if;

    if exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id
        and b.id<>booking.id
        and b.check_in<check_out_date
        and b.check_out>check_in_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    ) then
      raise exception 'room is not available for the requested dates' using errcode='23514';
    end if;

    rate_value := booking.rate_per_night_php;
    if payload ? 'ratePerNightPhp' then
      if not can_override then
        raise exception 'only owner or admin can override room rate' using errcode='42501';
      end if;
      rate_value := (payload->>'ratePerNightPhp')::numeric;
    end if;
    if rate_value<0 then
      raise exception 'room rate cannot be negative' using errcode='22023';
    end if;

    nights_value := check_out_date-check_in_date;
    total_value := rate_value*nights_value;
    paid_value := least(
      booking.deposit_amount_php,
      total_value
    );
    balance_value := greatest(total_value-paid_value,0);

    update plp_runtime.plp_bookings
    set accommodation_id=room.id,
        accommodation_name=room.name,
        check_in=check_in_date,
        check_out=check_out_date,
        guest_count=guest_count_value,
        nights=nights_value,
        rate_per_night_php=rate_value,
        total_amount_php=total_value,
        deposit_amount_php=paid_value,
        balance_amount_php=balance_value,
        special_requests=special_requests_value,
        payment_status=case
          when balance_value=0 then 'PAID'
          when paid_value>0 then 'PARTIALLY_PAID'
          else payment_status
        end,
        updated_at=now_utc
    where id=booking.id;

    select * into booking_readback
    from plp_runtime.plp_bookings b
    where b.id=booking.id;

    if booking_readback.id is null
       or booking_readback.check_in<>check_in_date
       or booking_readback.check_out<>check_out_date
       or booking_readback.accommodation_id<>room.id then
      raise exception 'reservation update provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := booking_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.reservation.update',
      'requestId',request_id,
      'resourceType','reservation',
      'resourceId',booking_readback.id,
      'bookingReference',booking_readback.booking_reference,
      'accommodationId',booking_readback.accommodation_id,
      'accommodationName',booking_readback.accommodation_name,
      'checkIn',booking_readback.check_in,
      'checkOut',booking_readback.check_out,
      'guestCount',booking_readback.guest_count,
      'status',booking_readback.status,
      'paymentStatus',booking_readback.payment_status,
      'totalAmountPhp',booking_readback.total_amount_php,
      'balanceAmountPhp',booking_readback.balance_amount_php,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  elsif action_name in (
    'reservation.check_in',
    'reservation.check_out',
    'reservation.cancel'
  ) then
    resource_type := 'reservation';
    if p_resource_id is null then
      raise exception 'reservation resource id is required' using errcode='22023';
    end if;

    select * into booking
    from plp_runtime.plp_bookings b
    where b.id=p_resource_id
    for update;

    if booking.id is null then
      raise exception 'PLP reservation not found' using errcode='P0002';
    end if;

    if action_name='reservation.check_in' then
      if upper(coalesce(booking.status,'')) not in
        ('CONFIRMED','PENDING_PAYMENT') then
        raise exception 'reservation is not eligible for check-in' using errcode='55000';
      end if;
      if booking.check_in>ctx.business_date
         or booking.check_out<=ctx.business_date then
        raise exception 'reservation is not due for check-in today' using errcode='55000';
      end if;

      select * into room
      from plp_runtime.plp_accommodations a
      where a.id=booking.accommodation_id
        and a.is_active=true
      for update;

      if room.id is null then
        raise exception 'reservation room is unavailable' using errcode='55000';
      end if;
      operational_state :=
        lower(coalesce(room.metadata->>'operational_state','ready'));
      if operational_state in ('cleaning','maintenance','out_of_service') then
        raise exception 'room must be ready before check-in' using errcode='55000';
      end if;

      update plp_runtime.plp_bookings
      set status='CHECKED_IN',
          updated_at=now_utc
      where id=booking.id;

    elsif action_name='reservation.check_out' then
      if upper(coalesce(booking.status,'')) not in
        ('CHECKED_IN','IN_HOUSE') then
        raise exception 'reservation is not eligible for check-out' using errcode='55000';
      end if;

      if booking.balance_amount_php>0
         and not (
           can_override
           and coalesce((payload->>'allowOutstanding')::boolean,false)
         ) then
        raise exception 'outstanding balance must be resolved before check-out'
          using errcode='55000';
      end if;

      update plp_runtime.plp_bookings
      set status='CHECKED_OUT',
          updated_at=now_utc
      where id=booking.id;

      if booking.accommodation_id is not null then
        update plp_runtime.plp_accommodations
        set metadata=jsonb_set(
              coalesce(metadata,'{}'::jsonb),
              '{operational_state}',
              '"cleaning"'::jsonb,
              true
            ) || jsonb_build_object(
              'operational_updated_at',now_utc,
              'operational_updated_by',ctx.user_id
            ),
            updated_at=now_utc
        where id=booking.accommodation_id;
      end if;

    else
      if upper(coalesce(booking.status,'')) in
        ('CHECKED_IN','IN_HOUSE','CHECKED_OUT','CANCELLED','CANCELED') then
        raise exception 'reservation cannot be cancelled in its current state'
          using errcode='55000';
      end if;

      update plp_runtime.plp_bookings
      set status='CANCELLED',
          cancelled_at=now_utc,
          updated_at=now_utc
      where id=booking.id;
    end if;

    select * into booking_readback
    from plp_runtime.plp_bookings b
    where b.id=booking.id;

    target_status := case action_name
      when 'reservation.check_in' then 'CHECKED_IN'
      when 'reservation.check_out' then 'CHECKED_OUT'
      else 'CANCELLED'
    end;

    if upper(coalesce(booking_readback.status,''))<>target_status then
      raise exception 'reservation lifecycle provider readback verification failed'
        using errcode='55000';
    end if;

    result_resource_id := booking_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.'||action_name,
      'requestId',request_id,
      'resourceType','reservation',
      'resourceId',booking_readback.id,
      'bookingReference',booking_readback.booking_reference,
      'status',booking_readback.status,
      'balanceAmountPhp',booking_readback.balance_amount_php,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  elsif action_name='guest.update' then
    resource_type := 'guest';
    if p_resource_id is null then
      raise exception 'guest resource id is required' using errcode='22023';
    end if;

    select * into guest
    from plp_runtime.plp_guests g
    where g.id=p_resource_id
      and exists (
        select 1
        from plp_runtime.plp_bookings b
        where b.guest_id=g.id
      )
    for update;

    if guest.id is null then
      raise exception 'PLP guest not found' using errcode='P0002';
    end if;

    guest_full_name_value := case
      when payload ? 'fullName' then trim(coalesce(payload->>'fullName',''))
      else guest.full_name
    end;
    guest_email_value := case
      when payload ? 'email' then lower(trim(coalesce(payload->>'email','')))
      else guest.email
    end;
    guest_phone_value := case
      when payload ? 'phone' then nullif(trim(coalesce(payload->>'phone','')),'')
      else guest.phone
    end;

    if length(full_name) not between 2 and 160 then
      raise exception 'guest full name is required' using errcode='22023';
    end if;
    if guest_email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      raise exception 'valid guest email is required' using errcode='22023';
    end if;
    if exists (
      select 1
      from plp_runtime.plp_guests g
      where g.normalized_email=lower(guest_email_value)
        and g.id<>guest.id
    ) then
      raise exception 'guest email already belongs to another guest' using errcode='23505';
    end if;

    update plp_runtime.plp_guests
    set full_name=guest_full_name_value,
        email=guest_email_value,
        normalized_email=lower(guest_email_value),
        phone=guest_phone_value,
        metadata=
          case when payload ? 'vip'
            then jsonb_set(
              coalesce(metadata,'{}'::jsonb),
              '{vip}',
              to_jsonb(coalesce((payload->>'vip')::boolean,false)),
              true
            )
            else coalesce(metadata,'{}'::jsonb)
          end,
        updated_at=now_utc
    where id=guest.id;

    if payload ? 'preferences' then
      update plp_runtime.plp_guests
      set metadata=jsonb_set(
            coalesce(metadata,'{}'::jsonb),
            '{preferences}',
            to_jsonb(coalesce(nullif(trim(coalesce(payload->>'preferences','')),''),'')),
            true
          ),
          updated_at=now_utc
      where id=guest.id;
    end if;

    select * into guest_readback
    from plp_runtime.plp_guests g
    where g.id=guest.id;

    if guest_readback.id is null
       or guest_readback.full_name<>guest_full_name_value
       or guest_readback.normalized_email<>lower(guest_email_value) then
      raise exception 'guest provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := guest_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.guest.update',
      'requestId',request_id,
      'resourceType','guest',
      'resourceId',guest_readback.id,
      'fullName',guest_readback.full_name,
      'vip',coalesce((guest_readback.metadata->>'vip')::boolean,false),
      'preferences',nullif(trim(coalesce(guest_readback.metadata->>'preferences','')),''),
      'contactUpdated',true,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  elsif action_name='room.update' then
    resource_type := 'room';
    if p_resource_id is null then
      raise exception 'room resource id is required' using errcode='22023';
    end if;

    select * into room
    from plp_runtime.plp_accommodations a
    where a.id=p_resource_id
    for update;

    if room.id is null then
      raise exception 'PLP room not found' using errcode='P0002';
    end if;

    operational_state := case
      when payload ? 'operationalState'
        then lower(trim(coalesce(payload->>'operationalState','')))
      else lower(coalesce(room.metadata->>'operational_state','ready'))
    end;

    if operational_state not in
      ('ready','cleaning','maintenance','out_of_service') then
      raise exception 'unsupported room operational state' using errcode='22023';
    end if;

    if operational_state<>'ready'
       and exists (
         select 1
         from plp_runtime.plp_bookings b
         where b.accommodation_id=room.id
           and b.check_in<=ctx.business_date
           and b.check_out>ctx.business_date
           and upper(coalesce(b.status,'')) not in
             ('CANCELLED','CANCELED','CHECKED_OUT')
       ) then
      raise exception 'occupied room cannot be moved out of ready state'
        using errcode='55000';
    end if;

    if (
      payload ? 'nightlyRatePhp'
      or payload ? 'capacity'
      or payload ? 'bedrooms'
      or payload ? 'isActive'
    ) and not can_override then
      raise exception 'only owner or admin can change room commercial settings'
        using errcode='42501';
    end if;

    rate_value := case
      when payload ? 'nightlyRatePhp'
        then (payload->>'nightlyRatePhp')::numeric
      else room.nightly_rate_php
    end;
    guest_count_value := case
      when payload ? 'capacity' then (payload->>'capacity')::integer
      else room.capacity
    end;

    if rate_value<0 or guest_count_value<1
       or (
         payload ? 'bedrooms'
         and (payload->>'bedrooms')::integer<0
       ) then
      raise exception 'invalid room commercial settings' using errcode='22023';
    end if;

    if exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id
        and b.check_out>=ctx.business_date
        and b.guest_count>guest_count_value
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    ) then
      raise exception 'room capacity cannot be reduced below an active reservation'
        using errcode='55000';
    end if;

    if payload ? 'isActive'
       and coalesce((payload->>'isActive')::boolean,true)=false
       and exists (
         select 1
         from plp_runtime.plp_bookings b
         where b.accommodation_id=room.id
           and b.check_out>=ctx.business_date
           and upper(coalesce(b.status,'')) not in
             ('CANCELLED','CANCELED','CHECKED_OUT')
       ) then
      raise exception 'room with active or future reservations cannot be disabled'
        using errcode='55000';
    end if;

    update plp_runtime.plp_accommodations
    set nightly_rate_php=rate_value,
        capacity=guest_count_value,
        bedrooms=case
          when payload ? 'bedrooms' then (payload->>'bedrooms')::integer
          else bedrooms
        end,
        is_active=case
          when payload ? 'isActive' then (payload->>'isActive')::boolean
          else is_active
        end,
        metadata=jsonb_set(
          coalesce(metadata,'{}'::jsonb),
          '{operational_state}',
          to_jsonb(operational_state),
          true
        ) || jsonb_build_object(
          'operational_updated_at',now_utc,
          'operational_updated_by',ctx.user_id
        ),
        updated_at=now_utc
    where id=room.id;

    select * into room_readback
    from plp_runtime.plp_accommodations a
    where a.id=room.id;

    if room_readback.id is null
       or lower(coalesce(room_readback.metadata->>'operational_state','ready'))
          <>operational_state then
      raise exception 'room provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := room_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.room.update',
      'requestId',request_id,
      'resourceType','room',
      'resourceId',room_readback.id,
      'name',room_readback.name,
      'operationalState',operational_state,
      'nightlyRatePhp',room_readback.nightly_rate_php,
      'capacity',room_readback.capacity,
      'bedrooms',room_readback.bedrooms,
      'isActive',room_readback.is_active,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  elsif action_name='payment.record' then
    resource_type := 'payment';
    if p_resource_id is null then
      raise exception 'reservation resource id is required for payment' using errcode='22023';
    end if;

    select * into booking
    from plp_runtime.plp_bookings b
    where b.id=p_resource_id
    for update;

    if booking.id is null then
      raise exception 'PLP reservation not found' using errcode='P0002';
    end if;
    if upper(coalesce(booking.status,'')) in ('CANCELLED','CANCELED') then
      raise exception 'payment cannot be recorded against cancelled reservation'
        using errcode='55000';
    end if;

    payment_amount := coalesce(nullif(payload->>'amountPhp','')::numeric,0);
    payment_method := lower(trim(coalesce(payload->>'method','')));
    payment_reference := nullif(trim(coalesce(payload->>'reference','')),'');

    if payment_amount<=0 or payment_amount>booking.balance_amount_php then
      raise exception 'payment amount must be positive and not exceed balance'
        using errcode='22023';
    end if;
    if payment_method not in
      ('cash','bank_transfer','card_terminal','maya_manual','other') then
      raise exception 'unsupported manual payment method' using errcode='22023';
    end if;
    if payment_reference is not null and length(payment_reference)>160 then
      raise exception 'payment reference too long' using errcode='22023';
    end if;

    insert into plp_runtime.plp_payments(
      booking_id,
      provider,
      provider_reference_id,
      amount_php,
      currency,
      status,
      verification_status,
      raw_response,
      paid_at
    ) values (
      booking.id,
      'manual_'||payment_method,
      payment_reference,
      payment_amount,
      'PHP',
      'PAID',
      'VERIFIED',
      jsonb_build_object(
        'recordedByUserId',ctx.user_id,
        'recordedByRole',ctx.access_role,
        'method',payment_method
      ),
      now_utc
    )
    returning * into payment;

    paid_value := least(
      booking.total_amount_php,
      booking.deposit_amount_php+payment_amount
    );
    balance_value := greatest(booking.total_amount_php-paid_value,0);

    update plp_runtime.plp_bookings
    set deposit_amount_php=paid_value,
        balance_amount_php=balance_value,
        payment_status=case
          when balance_value=0 then 'PAID'
          else 'PARTIALLY_PAID'
        end,
        updated_at=now_utc
    where id=booking.id;

    select * into booking_readback
    from plp_runtime.plp_bookings b
    where b.id=booking.id;

    if booking_readback.balance_amount_php<>balance_value
       or not exists (
         select 1
         from plp_runtime.plp_payments p
         where p.id=payment.id
           and p.status='PAID'
           and p.verification_status='VERIFIED'
       ) then
      raise exception 'payment provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := payment.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.payment.record',
      'requestId',request_id,
      'resourceType','payment',
      'resourceId',payment.id,
      'bookingId',booking.id,
      'bookingReference',booking.booking_reference,
      'amountPhp',payment.amount_php,
      'method',payment_method,
      'paymentStatus',booking_readback.payment_status,
      'balanceAmountPhp',booking_readback.balance_amount_php,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );

  else
    resource_type := 'task';
    if p_resource_id is null then
      raise exception 'task resource id is required' using errcode='22023';
    end if;

    select * into task
    from plp_runtime.plp_staff_tasks t
    where t.id=p_resource_id
    for update;

    if task.id is null then
      raise exception 'PLP task not found' using errcode='P0002';
    end if;

    target_status := case
      when payload ? 'status'
        then lower(trim(coalesce(payload->>'status','')))
      else task.status
    end;
    target_priority := case
      when payload ? 'priority'
        then lower(trim(coalesce(payload->>'priority','')))
      else task.priority
    end;
    target_note := case
      when payload ? 'note'
        then nullif(trim(coalesce(payload->>'note','')),'')
      else task.note
    end;

    if target_status not in ('open','in_progress','done','cancelled') then
      raise exception 'unsupported task status' using errcode='22023';
    end if;
    if target_priority not in ('high','medium','normal') then
      raise exception 'unsupported task priority' using errcode='22023';
    end if;

    current_state := lower(task.status);
    if target_status<>current_state and not (
      (current_state='open' and target_status in ('in_progress','done','cancelled'))
      or
      (current_state='in_progress' and target_status in ('done','cancelled'))
    ) then
      raise exception 'invalid task state transition' using errcode='55000';
    end if;

    update plp_runtime.plp_staff_tasks
    set status=target_status,
        priority=target_priority,
        note=target_note,
        actor=ctx.actor_label,
        completed_at=case
          when target_status='done' then coalesce(completed_at,now_utc)
          when target_status in ('open','in_progress') then null
          else completed_at
        end,
        updated_at=now_utc
    where id=task.id;

    select * into task_readback
    from plp_runtime.plp_staff_tasks t
    where t.id=task.id;

    if task_readback.status<>target_status
       or task_readback.priority<>target_priority then
      raise exception 'task provider readback verification failed' using errcode='55000';
    end if;

    result_resource_id := task_readback.id;
    result := jsonb_build_object(
      'verified',true,
      'authority','PLP_RESORT_ACTION_V1',
      'provider','supabase',
      'capability','plp.task.update',
      'requestId',request_id,
      'resourceType','task',
      'resourceId',task_readback.id,
      'bookingReference',task_readback.booking_reference,
      'title',task_readback.title,
      'status',task_readback.status,
      'priority',task_readback.priority,
      'updatedAt',task_readback.updated_at,
      'providerReadbackVerified',true,
      'idempotentReplay',false
    );
  end if;

  insert into private.plp_resort_action_receipts(
    request_id,
    organization_id,
    user_id,
    action,
    resource_type,
    resource_id,
    request_sha256,
    provider_readback
  ) values (
    request_id,
    ctx.organization_id,
    ctx.user_id,
    action_name,
    resource_type,
    result_resource_id,
    request_sha,
    result
  );

  return result;
end;
$$;

revoke all on function public.plp_resort_action_v1(text,text,uuid,jsonb)
  from public,anon;
grant execute on function public.plp_resort_action_v1(text,text,uuid,jsonb)
  to authenticated,service_role;


-- Extend the existing safe invalidation topic allowlist for room/payment writes.
alter table public.enterprise_realtime_signals
  drop constraint if exists enterprise_realtime_signals_topic_check;
alter table public.enterprise_realtime_signals
  add constraint enterprise_realtime_signals_topic_check
  check (
    topic in (
      'bookings',
      'guests',
      'staff_tasks',
      'rooms',
      'payments',
      'hospitality',
      'business_activity',
      'source_health',
      'pandora_activity'
    )
  );

do $realtime_rooms$
begin
  if to_regclass('plp_runtime.plp_accommodations') is not null then
    execute 'drop trigger if exists plp_realtime_rooms_signal
      on plp_runtime.plp_accommodations';
    execute 'create trigger plp_realtime_rooms_signal
      after insert or update or delete on plp_runtime.plp_accommodations
      for each row execute function private.emit_plp_runtime_realtime_signal(''rooms'')';
  end if;
end;
$realtime_rooms$;

do $realtime_payments$
begin
  if to_regclass('plp_runtime.plp_payments') is not null then
    execute 'drop trigger if exists plp_realtime_payments_signal
      on plp_runtime.plp_payments';
    execute 'create trigger plp_realtime_payments_signal
      after insert or update or delete on plp_runtime.plp_payments
      for each row execute function private.emit_plp_runtime_realtime_signal(''payments'')';
  end if;
end;
$realtime_payments$;

-- Existing enterprise/realtime triggers on PLP runtime tables remain the
-- convergence mechanism. The command center now also reflects explicit
-- room operational states so "available" never includes Cleaning,
-- Maintenance or Out of service rooms.

create or replace function public.plp_resort_command_center_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  business_date date;
  rooms jsonb := '[]'::jsonb;
  stays jsonb := '[]'::jsonb;
  experience_signals jsonb := '[]'::jsonb;
  rooms_total integer := 0;
  rooms_occupied integer := 0;
  rooms_unavailable integer := 0;
  rooms_arriving integer := 0;
  rooms_departing integer := 0;
  open_tasks integer := 0;
  priority_tasks integer := 0;
  open_conflicts integer := 0;
  booked_value_30d numeric := 0;
  outstanding_balance numeric := 0;
  paid_value_30d numeric := 0;
  universal_rooms integer := 0;
  universal_reservations integer := 0;
  universal_stays integer := 0;
  universal_housekeeping integer := 0;
  universal_guest_profiles integer := 0;
  universal_folios integer := 0;
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

  if not exists (
    select 1 from public.memberships m
    where m.organization_id=prop.organization_id
      and m.user_id=uid
      and m.status::text='active'
  ) then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  business_date :=
    (clock_timestamp() at time zone
      coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select count(*)::integer into rooms_total
  from plp_runtime.plp_accommodations a
  where a.is_active=true;

  select count(*)::integer into rooms_occupied
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in<=business_date
        and b.check_out>business_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    );

  select count(*)::integer into rooms_unavailable
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and lower(coalesce(a.metadata->>'operational_state','ready')) in
      ('cleaning','maintenance','out_of_service')
    and not exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in<=business_date
        and b.check_out>business_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    );

  select count(*)::integer into rooms_arriving
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in=business_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED','CHECKED_OUT')
    );

  select count(*)::integer into rooms_departing
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_out=business_date
        and upper(coalesce(b.status,'')) not in
          ('CANCELLED','CANCELED')
    );

  select coalesce(jsonb_agg(q.payload order by q.name),'[]'::jsonb)
  into rooms
  from (
    select a.name,
      jsonb_build_object(
        'id',a.id,
        'name',a.name,
        'capacity',a.capacity,
        'bedrooms',a.bedrooms,
        'nightlyRatePhp',a.nightly_rate_php,
        'operationalState',
          lower(coalesce(a.metadata->>'operational_state','ready')),
        'state',
          case
            when lower(coalesce(a.metadata->>'operational_state','ready')) in
              ('cleaning','maintenance','out_of_service')
              then lower(a.metadata->>'operational_state')
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_out=business_date
                and upper(coalesce(b.status,'')) not in
                  ('CANCELLED','CANCELED')
            ) then 'departure'
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in=business_date
                and upper(coalesce(b.status,'')) not in
                  ('CANCELLED','CANCELED','CHECKED_OUT')
            ) then 'arrival'
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in<=business_date
                and b.check_out>business_date
                and upper(coalesce(b.status,'')) not in
                  ('CANCELLED','CANCELED','CHECKED_OUT')
            ) then 'occupied'
            else 'available'
          end
      ) as payload
    from plp_runtime.plp_accommodations a
    where a.is_active=true
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.check_in,q.full_name),
    '[]'::jsonb
  )
  into stays
  from (
    select b.check_in,g.full_name,
      jsonb_build_object(
        'id',b.id,
        'bookingReference',b.booking_reference,
        'guestId',g.id,
        'fullName',g.full_name,
        'accommodationId',b.accommodation_id,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'guestCount',b.guest_count,
        'nights',b.nights,
        'ratePerNightPhp',b.rate_per_night_php,
        'status',b.status,
        'paymentStatus',b.payment_status,
        'totalAmountPhp',b.total_amount_php,
        'balanceAmountPhp',b.balance_amount_php,
        'hasSpecialRequest',
          nullif(trim(coalesce(b.special_requests,'')),'') is not null,
        'specialRequest',
          nullif(trim(coalesce(b.special_requests,'')),'')
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out>=business_date
      and b.check_in<=business_date+30
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
    order by b.check_in,g.full_name
    limit 24
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.check_in,q.full_name),
    '[]'::jsonb
  )
  into experience_signals
  from (
    select b.check_in,g.full_name,
      jsonb_build_object(
        'guestId',g.id,
        'bookingId',b.id,
        'bookingReference',b.booking_reference,
        'fullName',g.full_name,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'request',nullif(trim(coalesce(b.special_requests,'')),'')
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out>=business_date
      and b.check_in<=business_date+30
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
      and nullif(trim(coalesce(b.special_requests,'')),'') is not null
    order by b.check_in,g.full_name
    limit 12
  ) q;

  select
    count(*)::integer,
    count(*) filter (
      where lower(coalesce(t.priority,'')) in ('critical','high')
    )::integer
  into open_tasks,priority_tasks
  from plp_runtime.plp_staff_tasks t
  where lower(coalesce(t.status,'')) not in
    ('done','completed','complete','cancelled','canceled','closed');

  select count(*)::integer into open_conflicts
  from plp_runtime.plp_ota_conflicts c
  where lower(coalesce(c.status,'')) not in
      ('resolved','closed','cancelled','canceled')
    and lower(coalesce(c.resolution_status,'')) not in
      ('resolved','closed');

  select
    coalesce(sum(b.total_amount_php),0),
    coalesce(sum(b.balance_amount_php),0)
  into booked_value_30d,outstanding_balance
  from plp_runtime.plp_bookings b
  where b.check_in between business_date and business_date+30
    and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED');

  select coalesce(sum(p.amount_php),0)
  into paid_value_30d
  from plp_runtime.plp_payments p
  where lower(coalesce(p.status,'')) in
      ('paid','succeeded','complete','completed')
    and p.paid_at>=business_date::timestamp
    and p.paid_at<(business_date+30)::timestamp;

  select count(*)::integer into universal_rooms
  from public.enterprise_hospitality_rooms r
  where r.organization_id=prop.organization_id;
  select count(*)::integer into universal_reservations
  from public.enterprise_hospitality_reservations r
  where r.organization_id=prop.organization_id;
  select count(*)::integer into universal_stays
  from public.enterprise_hospitality_stays s
  where s.organization_id=prop.organization_id;
  select count(*)::integer into universal_housekeeping
  from public.enterprise_hospitality_housekeeping_jobs h
  where h.organization_id=prop.organization_id;
  select count(*)::integer into universal_guest_profiles
  from public.enterprise_hospitality_guest_profiles g
  where g.organization_id=prop.organization_id;
  select count(*)::integer into universal_folios
  from public.enterprise_hospitality_folios f
  where f.organization_id=prop.organization_id;

  return jsonb_build_object(
    'schemaVersion','plp.resort.command-center.v2',
    'generatedAt',clock_timestamp(),
    'businessDate',business_date,
    'rooms',rooms,
    'stays',stays,
    'experienceSignals',experience_signals,
    'roomPulse',jsonb_build_object(
      'total',rooms_total,
      'occupied',rooms_occupied,
      'unavailable',rooms_unavailable,
      'available',
        greatest(rooms_total-rooms_occupied-rooms_unavailable,0),
      'arriving',rooms_arriving,
      'departing',rooms_departing
    ),
    'operations',jsonb_build_object(
      'openWork',open_tasks,
      'priorityWork',priority_tasks,
      'channelExceptions',open_conflicts
    ),
    'finance',jsonb_build_object(
      'bookedValue30dPhp',booked_value_30d,
      'outstandingBalancePhp',outstanding_balance,
      'paidValue30dPhp',paid_value_30d
    ),
    'universalHospitality',jsonb_build_object(
      'rooms',universal_rooms,
      'reservations',universal_reservations,
      'stays',universal_stays,
      'housekeepingJobs',universal_housekeeping,
      'guestProfiles',universal_guest_profiles,
      'folios',universal_folios
    ),
    'truth',jsonb_build_object(
      'projectionOnly',true,
      'contactDetailsExcluded',true,
      'source','existing PLP runtime + Universal hospitality records'
    )
  );
end;
$$;

revoke all on function public.plp_resort_command_center_v1()
  from public,anon;
grant execute on function public.plp_resort_command_center_v1()
  to authenticated,service_role;
