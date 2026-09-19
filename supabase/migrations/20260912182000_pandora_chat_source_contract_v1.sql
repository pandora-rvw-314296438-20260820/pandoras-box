-- Pandora chat is a first-class Pandora intake source.
-- Keep the source allowlist explicit; only add the governed Pandora chat origin.

alter table public.pandora_intake_requests
  drop constraint if exists pandora_intake_requests_source_check;

alter table public.pandora_intake_requests
  add constraint pandora_intake_requests_source_check
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
