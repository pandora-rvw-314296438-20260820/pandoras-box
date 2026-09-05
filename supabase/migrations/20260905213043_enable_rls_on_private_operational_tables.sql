-- Enable RLS on private operational tables after grant review.
-- Replay-safe because several historical table-creation migrations are ledger receipts.
do $migration$
declare
  v_table text;
begin
  foreach v_table in array array[
    'vercel_public_git_bridge_targets',
    'canonical_supabase_release_receipts',
    'canonical_vercel_rehearsal_receipts',
    'canonical_release_review_receipts',
    'canonical_release_owner_authorizations',
    'pandora_project_experience_drift_observations',
    'pandora_github_webhook_deliveries',
    'pandora_scheduled_model_worker_jobs'
  ]
  loop
    if to_regclass(format('private.%I',v_table)) is not null then
      execute format('alter table private.%I enable row level security',v_table);
    end if;
  end loop;
end
$migration$;
