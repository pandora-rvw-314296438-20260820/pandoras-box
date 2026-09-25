-- Standalone disposable fixture; applied after the authorization fixture roles.
\set ON_ERROR_STOP on
CREATE TABLE public.tax_rule_packs(id uuid PRIMARY KEY,status text);
CREATE TABLE public.tax_rule_sources(id integer PRIMARY KEY,rule_pack_id uuid);
INSERT INTO public.tax_rule_packs VALUES
 ('90000000-0000-4000-8000-000000000001','draft'),
 ('90000000-0000-4000-8000-000000000002','approved');
INSERT INTO public.tax_rule_sources VALUES(2,'90000000-0000-4000-8000-000000000002');
CREATE OR REPLACE FUNCTION public.pandora_tax_guard_rule_support_mutation_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  pack_id uuid := coalesce(new.rule_pack_id,old.rule_pack_id);
  pack_status text;
begin
  select status into pack_status
  from public.tax_rule_packs
  where id=pack_id;

  if pack_status in ('approved','superseded','rejected') then
    raise exception 'pandora_tax_rule_support_immutable' using errcode='42501';
  end if;

  if tg_op='DELETE' then
    return old;
  end if;
  return new;
end;
$function$
;

CREATE TRIGGER tax_rule_sources_immutable_after_review
BEFORE INSERT OR DELETE OR UPDATE ON public.tax_rule_sources
FOR EACH ROW EXECUTE FUNCTION public.pandora_tax_guard_rule_support_mutation_v1();
GRANT SELECT,INSERT,UPDATE,DELETE ON public.tax_rule_sources TO authenticated;
