'use strict';
const FAKE_SECRET='PANDORA_FAKE_SECRET_CANARY_NOT_A_REAL_CREDENTIAL';
const FIXTURES=Object.freeze({
 badRls:Object.freeze({path:'migrations/bad_rls.sql',content:'ALTER TABLE public.items DISABLE ROW LEVEL SECURITY;'}),
 allowAllRls:Object.freeze({path:'migrations/allow_all.sql',content:'CREATE POLICY leak ON public.items FOR SELECT TO authenticated USING (true);'}),
 privilegeEscalation:Object.freeze({path:'migrations/escalate.sql',content:'GRANT INSERT, UPDATE, DELETE ON public.accounts TO authenticated;'}),
 secretBoundary:Object.freeze({path:'src/config.js',content:`const service_role = '${FAKE_SECRET}';`}),
 paymentSpoof:Object.freeze({path:'src/payments.js',content:'function markPaidFromClient(clientSuccess) { return clientSuccess ? "paid" : "pending"; }'}),
 crossTenant:Object.freeze({path:'migrations/cross_tenant.sql',content:'CREATE POLICY bad ON public.orders USING (tenant_id = tenant_id);'}),
 replay:Object.freeze({path:'src/webhook.js',content:'async function webhook(event) { return provider.apply(event); }'}),
 unsafeMigration:Object.freeze({path:'migrations/unsafe.sql',content:'DROP TABLE public.orders;'})
});
module.exports={FAKE_SECRET,FIXTURES};
