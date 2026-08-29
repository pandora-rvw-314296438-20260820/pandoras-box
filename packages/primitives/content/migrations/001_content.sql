-- pandora-primitive: pandora-content@1.0.0
-- target: customer-app-runtime-only
DO $$ BEGIN IF to_regclass('public.project_specs') IS NOT NULL OR to_regclass('public.projectos_execution_plans') IS NOT NULL OR to_regclass('public.pandora_projects') IS NOT NULL THEN RAISE EXCEPTION 'pandora-content customer primitive refused on Pandora Control Plane-like schema'; END IF; END $$;
CREATE TABLE IF NOT EXISTS public.primitive_content(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),scope_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN('page','article','faq')),slug text NOT NULL CHECK(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug)<=120),title text NOT NULL CHECK(char_length(title)<=200),body text NOT NULL CHECK(char_length(body)<=100000),status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','published','archived')),version integer NOT NULL DEFAULT 1 CHECK(version>0),author_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,published_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(scope_id,kind,slug),UNIQUE(id,scope_id));
ALTER TABLE public.primitive_content ENABLE ROW LEVEL SECURITY;ALTER TABLE public.primitive_content FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_content FROM anon,authenticated;GRANT SELECT ON public.primitive_content TO anon,authenticated;
CREATE POLICY primitive_content_public_read ON public.primitive_content FOR SELECT TO anon,authenticated USING(status='published');
CREATE POLICY primitive_content_staff_read ON public.primitive_content FOR SELECT TO authenticated USING(public.primitive_has_permission(scope_id,'data.read'));
-- Draft creation, edits, publication and archival are service-side after backend authorization.
