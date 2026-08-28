-- pandora-primitive: pandora-rbac@1.0.0
-- target: customer-app-runtime-only
DO $$
BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL
     OR to_regclass('public.projectos_execution_plans') IS NOT NULL
     OR to_regclass('public.pandora_projects') IS NOT NULL THEN
    RAISE EXCEPTION 'pandora-rbac customer primitive refused on Pandora Control Plane-like schema';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.primitive_rbac_roles (
  tenant_id uuid NOT NULL,
  role_key text NOT NULL CHECK (role_key ~ '^[a-z][a-z0-9_-]{1,63}$'),
  permissions text[] NOT NULL DEFAULT '{}',
  is_system boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, role_key),
  CHECK (cardinality(permissions) <= 128)
);

CREATE TABLE IF NOT EXISTS public.primitive_rbac_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, role_key),
  CONSTRAINT primitive_rbac_membership_role_fk
    FOREIGN KEY (tenant_id, role_key)
    REFERENCES public.primitive_rbac_roles(tenant_id, role_key)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS primitive_rbac_memberships_user_tenant_idx
  ON public.primitive_rbac_memberships(user_id, tenant_id);

ALTER TABLE public.primitive_rbac_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_rbac_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_rbac_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_rbac_memberships FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.primitive_rbac_roles FROM anon, authenticated;
REVOKE ALL ON public.primitive_rbac_memberships FROM anon, authenticated;
GRANT SELECT ON public.primitive_rbac_roles TO authenticated;
GRANT SELECT ON public.primitive_rbac_memberships TO authenticated;

DROP POLICY IF EXISTS primitive_rbac_roles_member_read ON public.primitive_rbac_roles;
CREATE POLICY primitive_rbac_roles_member_read ON public.primitive_rbac_roles
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.primitive_rbac_memberships m
  WHERE m.tenant_id = primitive_rbac_roles.tenant_id
    AND m.user_id = (SELECT auth.uid())
));

DROP POLICY IF EXISTS primitive_rbac_memberships_read_self ON public.primitive_rbac_memberships;
CREATE POLICY primitive_rbac_memberships_read_self ON public.primitive_rbac_memberships
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.primitive_has_permission(p_tenant_id uuid, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM public.primitive_rbac_memberships m
    JOIN public.primitive_rbac_roles r
      ON r.tenant_id = m.tenant_id AND r.role_key = m.role_key
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = (SELECT auth.uid())
      AND p_permission = ANY(r.permissions)
  ), false)
$$;
REVOKE ALL ON FUNCTION public.primitive_has_permission(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.primitive_has_permission(uuid,text) TO authenticated;
