-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

insert into private.projectos_event_contracts
(organization_id,product_key,event_name,purpose,privacy_tier,allowed_properties,retention_days,active,created_at,updated_at)
values
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','page_viewed','First-party acquisition and navigation signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','route_group','screen','channel','device_type','browser','os','funnel_step','entrypoint','source_path','campaign','source','medium','actor_type']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','opportunity_viewed','Verified opportunity consideration signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','feature_key','funnel_step','entrypoint','channel','content_type','content_id','listing_type','actor_type','campaign','source','medium','outcome']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','account_registered','Account activation signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','funnel_step','entrypoint','channel','success','actor_type','campaign','source','medium']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','profile_completed','Profile activation signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','funnel_step','entrypoint','channel','success','actor_type','verification_tier']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','marketplace_interest_submitted','Marketplace lead and protected-introduction intent','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','entrypoint','channel','outcome','success','content_type','content_id','listing_type','actor_type','campaign','source','medium']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','data_room_requested','Protected data-room intent signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','entrypoint','channel','outcome','success','content_type','content_id','listing_type','actor_type']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','questionnaire_engaged','Stakeholder or prospect product-direction engagement','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','entrypoint','channel','outcome','success','actor_type','funnel_step']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','questionnaire_submitted','Completed product-direction or application signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','entrypoint','channel','outcome','success','actor_type','funnel_step','duration_ms']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','marketing_consent_changed','Auditable direct-marketing consent state change','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','channel','outcome','status','actor_type','consent_status']::text[],730,true,now(),now()),
('2270b266-59da-4c39-bfd9-9f8d08352af0','fxpass','retargeting_event_sent','Meta retargeting delivery health signal','pseudonymous_product',array['environment','app_version','event_schema_version','source_repo','privacy_tier','channel','outcome','success','error_code','actor_type','meta_event_name']::text[],730,true,now(),now())
on conflict (organization_id,product_key,event_name) do update set
 purpose=excluded.purpose,
 privacy_tier=excluded.privacy_tier,
 allowed_properties=excluded.allowed_properties,
 retention_days=excluded.retention_days,
 active=true,
 updated_at=now();
