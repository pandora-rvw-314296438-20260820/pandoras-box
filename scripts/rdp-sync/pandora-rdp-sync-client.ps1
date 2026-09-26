param(
  [ValidateSet('probe','start','publish-head')][string]$Action = 'probe',
  [string]$Repo = '',
  [string]$Branch = '',
  [string]$BaseSha = ''
)

$ErrorActionPreference = 'Stop'

throw 'PANDORA_RDP_TRANSPORT_RETIRED: the former Windows/AWS RDP execution node is no longer an authorized Pandora source or build path. Use canonical GitHub/Supabase execution instead.'
