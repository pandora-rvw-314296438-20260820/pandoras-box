-- Run only after all eight tables have been proved present. These are actual counts.
-- No tenant data, task text, credentials or receipt contents are returned.
select jsonb_build_object(
 'observedAt',clock_timestamp(),
 'bindings',(select count(*) from private.pandora_ops_project_bindings),
 'workspaces',(select count(*) from private.pandora_ops_workspaces),
 'unpausedWorkspaces',(select count(*) from private.pandora_ops_workspaces where not paused),
 'productionEnabledWorkspaces',(select count(*) from private.pandora_ops_workspaces where not no_production),
 'workers',(select count(*) from private.pandora_ops_workers),
 'freshAcknowledgedWorkers',(select count(*) from private.pandora_ops_workers
   where acknowledged and connected and health='ready' and heartbeat_at>clock_timestamp()-interval '60 seconds'
   and heartbeat_at<=clock_timestamp()),
 'tasks',(select count(*) from private.pandora_ops_tasks),
 'activeLeases',(select count(*) from private.pandora_ops_leases where state<>'released'),
 'dispatches',(select count(*) from private.pandora_ops_dispatch_outbox),
 'events',(select count(*) from private.pandora_ops_events)
) as runtime_counts;
