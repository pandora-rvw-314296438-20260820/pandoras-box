update public.connector_installations
set display_name = 'Meta Business — pandoras-box',
    updated_at = timezone('utc'::text, now())
where provider = 'meta'
  and id = '01c5d527-031b-4d58-9b83-0cca87e9e77d'::uuid;
