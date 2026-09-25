-- Owner operational-attention index v1.
--
-- Proven live plan before this migration:
-- sequential scan over public.projectos_evidence, ~805 ms for the owner
-- operational-attention filter. Keep the index partial because invalidated
-- evidence is not part of the hot path.

create index if not exists projectos_evidence_open_attention_idx
on public.projectos_evidence (
  organization_id,
  evidence_type,
  status,
  id
)
where invalidated_at is null;
