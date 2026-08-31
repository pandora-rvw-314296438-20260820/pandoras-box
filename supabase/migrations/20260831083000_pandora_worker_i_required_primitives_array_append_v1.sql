-- Worker I inference repair: append scalar primitive names as one-element text arrays.
-- This preserves the existing inference vocabulary and only repairs PostgreSQL array concatenation.
create or replace function private.pandora_worker_i_required_primitives_20260831(p_project_spec_id uuid)
returns text[] language plpgsql stable security definer set search_path='' as $$
declare v_product jsonb;v_integrations jsonb;v_business text;v_text text;v_names text[]:='{}'::text[];v_result text[];
begin
 select product_scope,integration_scope,coalesce(business_summary,'') into v_product,v_integrations,v_business
 from public.pandora_project_specs where id=p_project_spec_id;
 if not found then raise exception 'project spec not found' using errcode='22023'; end if;
 if jsonb_array_length(case when jsonb_typeof(v_product->'roles')='array' then v_product->'roles' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-auth','pandora-rbac'];end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'payment')='array' then v_integrations->'payment' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-commerce','pandora-billing'];end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'messaging')='array' then v_integrations->'messaging' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-notifications'];end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'analytics')='array' then v_integrations->'analytics' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-analytics'];end if;
 select lower(concat_ws(' ',v_business,coalesce(string_agg(value,' '),''))) into v_text from(
   select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'features')='array' then v_product->'features' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'workflows')='array' then v_product->'workflows' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'screens')='array' then v_product->'screens' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'userStories')='array' then v_product->'userStories' else '[]'::jsonb end)
 ) q;
 if v_text~'\m(auth(entication)?|sign[ -]?in|log[ -]?in|password reset|magic link|account access)\M' then v_names:=v_names||array['pandora-auth'];end if;
 if v_text~'\m(role|permission|access control|rbac)\M' then v_names:=v_names||array['pandora-auth','pandora-rbac'];end if;
 if v_text~'\m(admin|back office|operations console)\M' then v_names:=v_names||array['pandora-admin'];end if;
 if v_text~'\m(audit|activity log|change log)\M' then v_names:=v_names||array['pandora-audit'];end if;
 if v_text~'\m(notification|push message|in-app message|email notification|sms notification)\M' then v_names:=v_names||array['pandora-notifications'];end if;
 if v_text~'\m(analytics|product metric|business metric|event tracking)\M' then v_names:=v_names||array['pandora-analytics'];end if;
 if v_text~'\m(booking|reservation|availability|capacity)\M' then v_names:=v_names||array['pandora-booking'];end if;
 if v_text~'\m(commerce|cart|checkout|catalog|inventory|order|storefront|shop)\M' then v_names:=v_names||array['pandora-commerce'];end if;
 if v_text~'\m(payment|billing|refund|invoice|subscription charge)\M' then v_names:=v_names||array['pandora-billing'];end if;
 if v_text~'\m(crm|lead pipeline|sales pipeline|customer interaction)\M' then v_names:=v_names||array['pandora-crm'];end if;
 if v_text~'\m(form submission|intake form|survey form|application form)\M' then v_names:=v_names||array['pandora-forms'];end if;
 if v_text~'\m(file upload|attachment|object storage|signed file|image upload)\M' then v_names:=v_names||array['pandora-files'];end if;
 if v_text~'\m(search|filterable search)\M' then v_names:=v_names||array['pandora-search'];end if;
 if v_text~'\m(cms|content management|article|faq|page editor)\M' then v_names:=v_names||array['pandora-content'];end if;
 if v_text~'\m(schedule|calendar|recurrence|time slot)\M' then v_names:=v_names||array['pandora-scheduling'];end if;
 if v_text~'\m(customer profile|user profile|preferences|consent)\M' then v_names:=v_names||array['pandora-customer-profile'];end if;
 if v_text~'\m(settings|timezone|currency|locale|branding settings)\M' then v_names:=v_names||array['pandora-settings'];end if;
 if v_text~'\m(feature flag|feature toggle|runtime flag)\M' then v_names:=v_names||array['pandora-feature-flags'];end if;
 select coalesce(array_agg(distinct x order by x),'{}'::text[]) into v_result from unnest(v_names) x;
 return v_result;
end;$$;

