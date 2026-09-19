-- Pandora chat is a first-class ProjectOS intake source.
-- Keep the source allowlist explicit; only add the governed Pandora chat origin.

alter table public.projectos_intake_requests
  drop constraint if exists projectos_intake_requests_source_check;

alter table public.projectos_intake_requests
  add constraint projectos_intake_requests_source_check
  check (
    source = any (
      array[
        'operator'::text,
        'chatgpt'::text,
        'github'::text,
        'slack'::text,
        'email'::text,
        'api'::text,
        'system'::text,
        'pandora_chat'::text
      ]
    )
  );
