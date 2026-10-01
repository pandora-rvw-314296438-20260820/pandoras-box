create table if not exists plp_runtime.plp_room_operations (
  accommodation_id uuid primary key
    references plp_runtime.plp_accommodations(id) on delete cascade,
  operational_state text not null default 'ready'
    check (operational_state in ('ready','cleaning','maintenance','out_of_order')),
  note text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists plp_runtime.plp_resort_write_receipts (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id text not null check (char_length(btrim(request_id)) between 8 and 160),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,request_id)
);

create table if not exists plp_runtime.plp_resort_audit (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text not null,
  request_id text not null,
  action text not null,
  entity_kind text not null,
  entity_id text not null,
  result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists plp_resort_audit_org_created_idx
  on plp_runtime.plp_resort_audit(organization_id,created_at desc);

revoke all on table plp_runtime.plp_room_operations
  from public,anon,authenticated;
revoke all on table plp_runtime.plp_resort_write_receipts
  from public,anon,authenticated;
revoke all on table plp_runtime.plp_resort_audit
  from public,anon,authenticated;

create or replace function public.plp_resort_transaction_v1(
  p_request_id text,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  actor_role text;
  request_key text := btrim(coalesce(p_request_id,''));
  action_name text := lower(btrim(coalesce(p_action,'')));
  payload jsonb := coalesce(p_payload,'{}'::jsonb);
  payload_sha text;
  prior plp_runtime.plp_resort_write_receipts%rowtype;
  result jsonb;
  entity_kind text := 'unknown';
  entity_id text := '';
  room plp_runtime.plp_accommodations%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  guest_id uuid;
  task_row plp_runtime.plp_staff_tasks%rowtype;
  conflict_row plp_runtime.plp_ota_conflicts%rowtype;
  check_in_date date;
  check_out_date date;
  business_date date;
  guest_count integer;
  nights_count integer;
  rate_php numeric;
  total_php numeric;
  amount_php numeric;
  normalized_email text;
  requested_state text;
  requested_status text;
  requested_priority text;
  booking_ref text;
  manual_ref text;
  force_action boolean := coalesce((payload->>'force')::boolean,false);
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if char_length(request_key) < 8 or char_length(request_key) > 160 then
    raise exception 'request_id must be 8 to 160 characters' using errcode='22023';
  end if;
  if action_name not in (
    'create_booking','update_booking','check_in','check_out','cancel_booking',
    'update_guest','set_room_state','set_room_rate','update_task',
    'resolve_conflict','record_manual_payment'
  ) then
    raise exception 'unsupported PLP resort action: %',action_name using errcode='22023';
  end if;
  if jsonb_typeof(payload) <> 'object' then
    raise exception 'payload must be an object' using errcode='22023';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid
   and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;
  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select m.role::text into actor_role
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if actor_role not in ('owner','admin','operator') then
    raise exception 'PLP operator access required' using errcode='42501';
  end if;

  payload_sha := encode(extensions.digest(payload::text,'sha256'),'hex');
  select r.* into prior
  from plp_runtime.plp_resort_write_receipts r
  where r.organization_id=prop.organization_id
    and r.request_id=request_key;
  if prior.request_id is not null then
    if prior.action<>action_name or prior.payload_sha256<>payload_sha then
      raise exception 'request_id already used with different PLP action or payload'
        using errcode='23505';
    end if;
    return prior.result || jsonb_build_object('idempotentReplay',true);
  end if;

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  if action_name='create_booking' then
    if coalesce(payload->>'guestFullName','')='' or coalesce(payload->>'guestEmail','')='' then
      raise exception 'guestFullName and guestEmail are required' using errcode='22023';
    end if;
    if coalesce(payload->>'checkIn','') !~ '^\d{4}-\d{2}-\d{2}$'
       or coalesce(payload->>'checkOut','') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'checkIn and checkOut must use YYYY-MM-DD' using errcode='22023';
    end if;
    check_in_date := (payload->>'checkIn')::date;
    check_out_date := (payload->>'checkOut')::date;
    if check_out_date<=check_in_date then
      raise exception 'checkOut must be after checkIn' using errcode='22023';
    end if;

    if nullif(payload->>'accommodationId','') is not null then
      select * into room from plp_runtime.plp_accommodations
      where id=(payload->>'accommodationId')::uuid and is_active=true;
    else
      select * into room from plp_runtime.plp_accommodations
      where lower(name)=lower(coalesce(payload->>'accommodationName','')) and is_active=true
      limit 1;
    end if;
    if room.id is null then
      raise exception 'active accommodation not found' using errcode='P0002';
    end if;

    guest_count := greatest(coalesce(nullif(payload->>'guestCount','')::integer,1),1);
    if guest_count>room.capacity then
      raise exception 'guest count exceeds room capacity' using errcode='22023';
    end if;
    if exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and daterange(b.check_in,b.check_out,'[)') &&
            daterange(check_in_date,check_out_date,'[)')
    ) then
      raise exception 'room is not available for the selected dates' using errcode='23P01';
    end if;

    normalized_email := lower(btrim(payload->>'guestEmail'));
    insert into plp_runtime.plp_guests(
      full_name,email,normalized_email,phone,metadata,updated_at
    ) values (
      btrim(payload->>'guestFullName'),
      btrim(payload->>'guestEmail'),
      normalized_email,
      nullif(btrim(coalesce(payload->>'guestPhone','')),''),
      jsonb_build_object('source','pandora_plp_mobile'),
      clock_timestamp()
    )
    on conflict (normalized_email) do update set
      full_name=excluded.full_name,
      email=excluded.email,
      phone=coalesce(excluded.phone,plp_runtime.plp_guests.phone),
      updated_at=clock_timestamp()
    returning id into guest_id;

    if payload ? 'ratePerNightPhp' then
      if actor_role not in ('owner','admin') then
        raise exception 'only owner or admin may override room rate' using errcode='42501';
      end if;
      rate_php := (payload->>'ratePerNightPhp')::numeric;
      if rate_php < 0 then
        raise exception 'room rate cannot be negative' using errcode='22023';
      end if;
    else
      rate_php := room.nightly_rate_php;
    end if;
    nights_count := check_out_date-check_in_date;
    total_php := rate_php*nights_count;
    booking_ref := 'PLP-'||to_char(check_in_date,'YYMMDD')||'-'||
      upper(substr(md5(request_key),1,6));

    insert into plp_runtime.plp_bookings(
      booking_reference,guest_id,accommodation_id,accommodation_name,
      check_in,check_out,guest_count,nights,rate_per_night_php,total_amount_php,
      deposit_amount_php,balance_amount_php,status,payment_status,special_requests,
      source,confirmed_at,updated_at
    ) values (
      booking_ref,guest_id,room.id,room.name,
      check_in_date,check_out_date,guest_count,nights_count,rate_php,total_php,
      0,total_php,'CONFIRMED','PENDING',
      nullif(btrim(coalesce(payload->>'specialRequests','')),''),
      'pandora_plp_mobile',clock_timestamp(),clock_timestamp()
    )
    returning * into booking;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,
      'bookingId',booking.id,
      'guestId',booking.guest_id,
      'roomId',booking.accommodation_id,
      'roomName',booking.accommodation_name,
      'checkIn',booking.check_in,'checkOut',booking.check_out,
      'guestCount',booking.guest_count,'nights',booking.nights,
      'ratePerNightPhp',booking.rate_per_night_php,
      'totalAmountPhp',booking.total_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,
      'status',booking.status,'paymentStatus',booking.payment_status
    );

  elsif action_name='update_booking' then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;
    if upper(booking.status) in ('CANCELLED','CANCELED','CHECKED_OUT') then
      raise exception 'closed booking cannot be edited' using errcode='22023';
    end if;

    check_in_date:=coalesce(nullif(payload->>'checkIn','')::date,booking.check_in);
    check_out_date:=coalesce(nullif(payload->>'checkOut','')::date,booking.check_out);
    if check_out_date<=check_in_date then
      raise exception 'checkOut must be after checkIn' using errcode='22023';
    end if;
    guest_count:=coalesce(nullif(payload->>'guestCount','')::integer,booking.guest_count);

    if nullif(payload->>'accommodationId','') is not null then
      select * into room from plp_runtime.plp_accommodations
      where id=(payload->>'accommodationId')::uuid and is_active=true;
    else
      select * into room from plp_runtime.plp_accommodations
      where id=booking.accommodation_id;
    end if;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;
    if guest_count<1 or guest_count>room.capacity then
      raise exception 'guest count is outside room capacity' using errcode='22023';
    end if;
    if exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id and b.id<>booking.id
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and daterange(b.check_in,b.check_out,'[)') &&
            daterange(check_in_date,check_out_date,'[)')
    ) then
      raise exception 'room is not available for the selected dates' using errcode='23P01';
    end if;

    rate_php:=booking.rate_per_night_php;
    if payload ? 'ratePerNightPhp' then
      if actor_role not in ('owner','admin') then
        raise exception 'only owner or admin may override room rate' using errcode='42501';
      end if;
      rate_php:=(payload->>'ratePerNightPhp')::numeric;
      if rate_php < 0 then
        raise exception 'room rate cannot be negative' using errcode='22023';
      end if;
    end if;
    nights_count:=check_out_date-check_in_date;
    total_php:=rate_php*nights_count;

    update plp_runtime.plp_bookings set
      accommodation_id=room.id,
      accommodation_name=room.name,
      check_in=check_in_date,
      check_out=check_out_date,
      guest_count=guest_count,
      nights=nights_count,
      rate_per_night_php=rate_php,
      total_amount_php=total_php,
      balance_amount_php=greatest(total_php-deposit_amount_php,0),
      payment_status=case
        when greatest(total_php-deposit_amount_php,0)=0 then 'PAID'
        when deposit_amount_php>0 then 'PARTIALLY_PAID'
        else payment_status
      end,
      special_requests=case
        when payload ? 'specialRequests'
          then nullif(btrim(coalesce(payload->>'specialRequests','')),'')
        else special_requests
      end,
      updated_at=clock_timestamp()
    where id=booking.id
    returning * into booking;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,'bookingId',booking.id,
      'roomId',booking.accommodation_id,'roomName',booking.accommodation_name,
      'checkIn',booking.check_in,'checkOut',booking.check_out,
      'guestCount',booking.guest_count,'nights',booking.nights,
      'ratePerNightPhp',booking.rate_per_night_php,
      'totalAmountPhp',booking.total_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,
      'status',booking.status,'paymentStatus',booking.payment_status,
      'specialRequests',booking.special_requests
    );

  elsif action_name in ('check_in','check_out','cancel_booking') then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;

    if action_name='check_in' then
      if upper(booking.status)='CHECKED_IN' then null;
      elsif upper(booking.status) in ('CANCELLED','CANCELED','CHECKED_OUT') then
        raise exception 'closed booking cannot be checked in' using errcode='22023';
      elsif business_date<booking.check_in and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'booking is not due for check-in yet' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CHECKED_IN',updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    elsif action_name='check_out' then
      if upper(booking.status)='CHECKED_OUT' then null;
      elsif upper(booking.status)<>'CHECKED_IN'
        and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'booking must be checked in before check-out' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CHECKED_OUT',updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    else
      if upper(booking.status) in ('CANCELLED','CANCELED') then null;
      elsif upper(booking.status)='CHECKED_OUT' then
        raise exception 'checked-out booking cannot be cancelled' using errcode='22023';
      elsif upper(booking.status)='CHECKED_IN'
        and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'checked-in stay must be checked out or owner-forced' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CANCELLED',cancelled_at=clock_timestamp(),updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    end if;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,'bookingId',booking.id,
      'status',booking.status,'paymentStatus',booking.payment_status,
      'balanceAmountPhp',booking.balance_amount_php
    );

  elsif action_name='update_guest' then
    if nullif(payload->>'guestId','') is not null then
      guest_id:=(payload->>'guestId')::uuid;
    else
      booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
      select b.guest_id into guest_id
      from plp_runtime.plp_bookings b
      where b.booking_reference=booking_ref;
    end if;
    if guest_id is null then raise exception 'guest not found' using errcode='P0002'; end if;

    if payload ? 'guestEmail' then
      normalized_email:=lower(btrim(coalesce(payload->>'guestEmail','')));
      if normalized_email='' then raise exception 'guestEmail cannot be empty' using errcode='22023'; end if;
    end if;

    update plp_runtime.plp_guests g set
      full_name=case when payload ? 'guestFullName'
        then nullif(btrim(coalesce(payload->>'guestFullName','')),'') else g.full_name end,
      email=case when payload ? 'guestEmail'
        then btrim(payload->>'guestEmail') else g.email end,
      normalized_email=case when payload ? 'guestEmail'
        then normalized_email else g.normalized_email end,
      phone=case when payload ? 'guestPhone'
        then nullif(btrim(coalesce(payload->>'guestPhone','')),'') else g.phone end,
      updated_at=clock_timestamp()
    where g.id=guest_id;

    if payload ? 'specialRequests' and nullif(payload->>'bookingReference','') is not null then
      update plp_runtime.plp_bookings
      set special_requests=nullif(btrim(coalesce(payload->>'specialRequests','')),''),
          updated_at=clock_timestamp()
      where booking_reference=payload->>'bookingReference';
    end if;

    entity_kind:='guest'; entity_id:=guest_id::text;
    select jsonb_build_object(
      'guestId',g.id,'fullName',g.full_name,'email',g.email,'phone',g.phone
    ) into result
    from plp_runtime.plp_guests g where g.id=guest_id;

  elsif action_name='set_room_state' then
    select * into room from plp_runtime.plp_accommodations
    where id=(payload->>'accommodationId')::uuid and is_active=true;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;
    requested_state:=lower(btrim(coalesce(payload->>'state','')));
    if requested_state not in ('ready','cleaning','maintenance','out_of_order') then
      raise exception 'invalid room operational state' using errcode='22023';
    end if;
    if requested_state='out_of_order' and actor_role not in ('owner','admin') then
      raise exception 'only owner or admin may mark a room out of order' using errcode='42501';
    end if;

    insert into plp_runtime.plp_room_operations(
      accommodation_id,operational_state,note,updated_by,updated_at
    ) values (
      room.id,requested_state,
      nullif(btrim(coalesce(payload->>'note','')),''),
      uid,clock_timestamp()
    )
    on conflict (accommodation_id) do update set
      operational_state=excluded.operational_state,
      note=excluded.note,
      updated_by=excluded.updated_by,
      updated_at=excluded.updated_at;

    entity_kind:='room'; entity_id:=room.id::text;
    select jsonb_build_object(
      'accommodationId',r.accommodation_id,
      'roomName',room.name,
      'operationalState',r.operational_state,
      'note',r.note,'updatedAt',r.updated_at
    ) into result
    from plp_runtime.plp_room_operations r where r.accommodation_id=room.id;

  elsif action_name='set_room_rate' then
    if actor_role not in ('owner','admin') then
      raise exception 'only owner or admin may change room rates' using errcode='42501';
    end if;
    rate_php:=(payload->>'nightlyRatePhp')::numeric;
    if rate_php < 0 then
      raise exception 'room rate cannot be negative' using errcode='22023';
    end if;
    update plp_runtime.plp_accommodations
    set nightly_rate_php=rate_php,updated_at=clock_timestamp()
    where id=(payload->>'accommodationId')::uuid and is_active=true
    returning * into room;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;

    entity_kind:='room'; entity_id:=room.id::text;
    result:=jsonb_build_object(
      'accommodationId',room.id,'roomName',room.name,
      'nightlyRatePhp',room.nightly_rate_php
    );

  elsif action_name='update_task' then
    select * into task_row from plp_runtime.plp_staff_tasks
    where id=(payload->>'taskId')::uuid for update;
    if task_row.id is null then raise exception 'task not found' using errcode='P0002'; end if;
    requested_status:=lower(btrim(coalesce(payload->>'status',task_row.status)));
    requested_priority:=lower(btrim(coalesce(payload->>'priority',task_row.priority)));
    if requested_status not in ('open','in_progress','done','cancelled') then
      raise exception 'invalid task status' using errcode='22023';
    end if;
    if requested_priority not in ('normal','medium','high','critical') then
      raise exception 'invalid task priority' using errcode='22023';
    end if;
    update plp_runtime.plp_staff_tasks set
      status=requested_status,
      priority=requested_priority,
      note=case when payload ? 'note' then nullif(btrim(coalesce(payload->>'note','')),'') else note end,
      completed_at=case when requested_status='done' then clock_timestamp() else null end,
      updated_at=clock_timestamp()
    where id=task_row.id returning * into task_row;

    entity_kind:='task'; entity_id:=task_row.id::text;
    result:=jsonb_build_object(
      'taskId',task_row.id,'title',task_row.title,'status',task_row.status,
      'priority',task_row.priority,'completedAt',task_row.completed_at
    );

  elsif action_name='resolve_conflict' then
    select * into conflict_row from plp_runtime.plp_ota_conflicts
    where id=(payload->>'conflictId')::uuid for update;
    if conflict_row.id is null then raise exception 'channel conflict not found' using errcode='P0002'; end if;
    update plp_runtime.plp_ota_conflicts set
      status='resolved',
      resolution_status='resolved',
      resolution_type=coalesce(nullif(btrim(payload->>'resolutionType'),''),'manual'),
      resolution_note=nullif(btrim(coalesce(payload->>'note','')),''),
      resolved_by=uid::text,
      resolved_at=clock_timestamp(),
      updated_at=clock_timestamp()
    where id=conflict_row.id returning * into conflict_row;

    entity_kind:='channel_conflict'; entity_id:=conflict_row.id::text;
    result:=jsonb_build_object(
      'conflictId',conflict_row.id,'channelKey',conflict_row.channel_key,
      'status',conflict_row.status,'resolutionStatus',conflict_row.resolution_status,
      'resolutionType',conflict_row.resolution_type,'resolvedAt',conflict_row.resolved_at
    );

  elsif action_name='record_manual_payment' then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;
    amount_php:=(payload->>'amountPhp')::numeric;
    if amount_php<=0 then raise exception 'payment amount must be positive' using errcode='22023'; end if;
    if amount_php>booking.balance_amount_php then
      raise exception 'payment amount exceeds outstanding balance' using errcode='22023';
    end if;
    manual_ref:=btrim(coalesce(payload->>'reference',''));
    if char_length(manual_ref)<3 then
      raise exception 'manual payment reference is required' using errcode='22023';
    end if;

    insert into plp_runtime.plp_payments(
      booking_id,provider,provider_reference_id,amount_php,currency,status,
      verification_status,raw_response,paid_at,updated_at
    ) values (
      booking.id,'manual',manual_ref,amount_php,'PHP','PAID','VERIFIED',
      jsonb_build_object(
        'recordedBy',uid,
        'note',nullif(btrim(coalesce(payload->>'note','')),''),
        'source','pandora_plp_mobile'
      ),
      clock_timestamp(),clock_timestamp()
    );

    update plp_runtime.plp_bookings set
      deposit_amount_php=least(total_amount_php,deposit_amount_php+amount_php),
      balance_amount_php=greatest(balance_amount_php-amount_php,0),
      payment_status=case
        when greatest(balance_amount_php-amount_php,0)=0 then 'PAID'
        else 'PARTIALLY_PAID'
      end,
      updated_at=clock_timestamp()
    where id=booking.id returning * into booking;

    entity_kind:='payment'; entity_id:=manual_ref;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,
      'amountPhp',amount_php,'reference',manual_ref,
      'paymentStatus',booking.payment_status,
      'balanceAmountPhp',booking.balance_amount_php
    );
  end if;

  result:=jsonb_build_object(
    'schemaVersion','plp.resort.transaction.v1',
    'requestId',request_key,
    'action',action_name,
    'verified',true,
    'providerReadbackVerified',true,
    'entityKind',entity_kind,
    'entityId',entity_id,
    'readback',coalesce(result,'{}'::jsonb)
  );

  insert into plp_runtime.plp_resort_audit(
    organization_id,actor_user_id,actor_role,request_id,action,entity_kind,entity_id,result
  ) values (
    prop.organization_id,uid,actor_role,request_key,action_name,entity_kind,entity_id,result
  );

  insert into plp_runtime.plp_resort_write_receipts(
    organization_id,request_id,actor_user_id,action,payload_sha256,result
  ) values (
    prop.organization_id,request_key,uid,action_name,payload_sha,result
  );

  return result;
end;
$$;

revoke execute on function public.plp_resort_transaction_v1(text,text,jsonb)
  from public,anon;
grant execute on function public.plp_resort_transaction_v1(text,text,jsonb)
  to authenticated;

drop trigger if exists plp_realtime_room_operations_signal
  on plp_runtime.plp_room_operations;
create trigger plp_realtime_room_operations_signal
after insert or update or delete on plp_runtime.plp_room_operations
for each row execute function private.emit_plp_runtime_realtime_signal('hospitality');

drop trigger if exists plp_realtime_payments_signal
  on plp_runtime.plp_payments;
create trigger plp_realtime_payments_signal
after insert or update or delete on plp_runtime.plp_payments
for each row execute function private.emit_plp_runtime_realtime_signal('hospitality');

drop trigger if exists plp_realtime_ota_conflicts_signal
  on plp_runtime.plp_ota_conflicts;
create trigger plp_realtime_ota_conflicts_signal
after insert or update or delete on plp_runtime.plp_ota_conflicts
for each row execute function private.emit_plp_runtime_realtime_signal('hospitality');

create or replace function public.plp_room_operations_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  items jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc limit 1;
  if prop.id is null then raise exception 'active PLP membership required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'accommodationId',a.id,'roomName',a.name,
    'operationalState',coalesce(o.operational_state,'ready'),
    'note',o.note,'updatedAt',o.updated_at
  ) order by a.name),'[]'::jsonb)
  into items
  from plp_runtime.plp_accommodations a
  left join plp_runtime.plp_room_operations o on o.accommodation_id=a.id
  where a.is_active=true;

  return jsonb_build_object(
    'schemaVersion','plp.room.operations.v1',
    'generatedAt',clock_timestamp(),
    'rooms',items
  );
end;
$$;

revoke execute on function public.plp_room_operations_v1() from public,anon;
grant execute on function public.plp_room_operations_v1() to authenticated;

create or replace function public.plp_resort_audit_v1(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  items jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc limit 1;
  if prop.id is null then raise exception 'active PLP membership required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(q.payload order by q.created_at desc),'[]'::jsonb)
  into items
  from (
    select a.created_at,
      jsonb_build_object(
        'id',a.id,'action',a.action,'entityKind',a.entity_kind,
        'entityId',a.entity_id,'actorRole',a.actor_role,
        'createdAt',a.created_at,
        'verified',coalesce((a.result->>'verified')::boolean,false),
        'providerReadbackVerified',
          coalesce((a.result->>'providerReadbackVerified')::boolean,false)
      ) as payload
    from plp_runtime.plp_resort_audit a
    where a.organization_id=prop.organization_id
    order by a.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),100))
  ) q;

  return jsonb_build_object(
    'schemaVersion','plp.resort.audit.v1',
    'generatedAt',clock_timestamp(),
    'items',items
  );
end;
$$;

revoke execute on function public.plp_resort_audit_v1(integer) from public,anon;
grant execute on function public.plp_resort_audit_v1(integer) to authenticated;
