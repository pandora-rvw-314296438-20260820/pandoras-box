revoke insert, update, delete on table plp_runtime.plp_staff_identities from service_role;
grant select on table plp_runtime.plp_staff_identities to service_role;
comment on table plp_runtime.plp_staff_identities is 'PLP staff role map. Web runtime may read through the governed Vercel OIDC gateway; role assignment and deactivation require governed database administration.';
