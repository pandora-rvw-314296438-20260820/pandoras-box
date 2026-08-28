-- pandora-primitive: pandora-auth@1.0.0
-- target: customer-app-runtime-only
DO $$
BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL
     OR to_regclass('public.projectos_execution_plans') IS NOT NULL
     OR to_regclass('public.pandora_projects') IS NOT NULL THEN
    RAISE EXCEPTION 'pandora-auth customer primitive refused on Pandora Control Plane-like schema';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.primitive_auth_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text CHECK (display_name IS NULL OR char_length(display_name) <= 160),
  locale text CHECK (locale IS NULL OR char_length(locale) <= 32),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.primitive_auth_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_auth_profiles FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_auth_profiles FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.primitive_auth_profiles TO authenticated;

DROP POLICY IF EXISTS primitive_auth_profiles_select_own ON public.primitive_auth_profiles;
CREATE POLICY primitive_auth_profiles_select_own ON public.primitive_auth_profiles
FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS primitive_auth_profiles_insert_own ON public.primitive_auth_profiles;
CREATE POLICY primitive_auth_profiles_insert_own ON public.primitive_auth_profiles
FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS primitive_auth_profiles_update_own ON public.primitive_auth_profiles;
CREATE POLICY primitive_auth_profiles_update_own ON public.primitive_auth_profiles
FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
REVOKE DELETE ON public.primitive_auth_profiles FROM anon, authenticated;
