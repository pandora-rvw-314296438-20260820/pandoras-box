-- Historical production-only recovery migration 20260826044908.
-- Canonical source intentionally uses a no-op: the original body created temporary recovery transport and is not replayable.
-- Durable cleanup is represented by 20260826051417 and 20260828091417.
select 1;
