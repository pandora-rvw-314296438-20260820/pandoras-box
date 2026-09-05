-- Enable RLS on private operational tables after grant review.
-- Direct grants are restricted to postgres/service_role; no anon/authenticated grants exist.
alter table private.vercel_public_git_bridge_targets enable row level security;
alter table private.canonical_supabase_release_receipts enable row level security;
alter table private.canonical_vercel_rehearsal_receipts enable row level security;
alter table private.canonical_release_review_receipts enable row level security;
alter table private.canonical_release_owner_authorizations enable row level security;
alter table private.pandora_project_experience_drift_observations enable row level security;
alter table private.pandora_github_webhook_deliveries enable row level security;
alter table private.pandora_scheduled_model_worker_jobs enable row level security;
