
begin;

do $block$
declare
  v_def text;
  v_new text;
  v_old_pre text := $$coalesce(nullif(b_adset#>>'{body,lifetime_budget}','')::bigint,0)<>a.max_spend_minor$$;
  v_new_pre text := $$coalesce(nullif(b_adset#>>'{body,daily_budget}','')::bigint,0)<>a.daily_budget_minor$$;
  v_old_confirm text := $$coalesce(nullif(a_adset#>>'{body,lifetime_budget}','')::bigint,0)=a.max_spend_minor$$;
  v_new_confirm text := $$coalesce(nullif(a_adset#>>'{body,daily_budget}','')::bigint,0)=a.daily_budget_minor$$;
begin
  select pg_get_functiondef('public.pandora_meta_activate_paid_pilot_v1(uuid,text)'::regprocedure)
  into v_def;

  if position(v_old_pre in v_def)=0 or position(v_old_confirm in v_def)=0 then
    raise exception 'PANDORA_META_PAID_PILOT_ACTIVATION_PATCH_BASE_MISMATCH';
  end if;

  v_new:=replace(replace(v_def,v_old_pre,v_new_pre),v_old_confirm,v_new_confirm);
  execute v_new;
end
$block$;

do $assert$
declare
  v_def text;
begin
  select pg_get_functiondef('public.pandora_meta_activate_paid_pilot_v1(uuid,text)'::regprocedure)
  into v_def;

  if position($$coalesce(nullif(b_adset#>>'{body,daily_budget}','')::bigint,0)<>a.daily_budget_minor$$ in v_def)=0
     or position($$coalesce(nullif(a_adset#>>'{body,daily_budget}','')::bigint,0)=a.daily_budget_minor$$ in v_def)=0
     or position($$coalesce(nullif(b_adset#>>'{body,lifetime_budget}','')::bigint,0)<>a.max_spend_minor$$ in v_def)>0
     or position($$coalesce(nullif(a_adset#>>'{body,lifetime_budget}','')::bigint,0)=a.max_spend_minor$$ in v_def)>0 then
    raise exception 'PANDORA_META_PAID_PILOT_ACTIVATION_PATCH_ASSERTION_FAILED';
  end if;
end
$assert$;

commit;
;
