part of 'provider_ecosystem_screen.dart';

const _outcomes = <_ProviderOutcome>[
  _ProviderOutcome('Deliver this order.', 'Logistics → Grab / Lalamove'),
  _ProviderOutcome(
    'Get more customers.',
    'Marketing → Meta Ads / Google Ads + Voluum',
  ),
  _ProviderOutcome(
    'Connect this branch.',
    'Telecom → PLDT / Smart / Globe / DITO',
  ),
  _ProviderOutcome(
    'Verify this company.',
    'Government → SEC / authorized sources',
  ),
  _ProviderOutcome('Take payment.', 'Money → Maya / bank / gateway'),
  _ProviderOutcome(
    'Issue or personalize a card.',
    'Identity → Ubivelox Philippines',
  ),
  _ProviderOutcome(
    'Run this workload.',
    'Compute → AWS / Google Cloud / Azure / local device',
  ),
];

const _capabilityFamilies = <_CapabilityFamily>[
  _CapabilityFamily(
    name: 'Compute',
    icon: Icons.cloud_queue_rounded,
    providers: <String>[
      'AWS',
      'Google Cloud',
      'Microsoft Azure',
      'local device compute',
    ],
  ),
  _CapabilityFamily(
    name: 'Data',
    icon: Icons.storage_rounded,
    providers: <String>[
      'Supabase',
      'PostgreSQL',
      'AWS S3',
      'Google Cloud Storage',
    ],
  ),
  _CapabilityFamily(
    name: 'Telecom',
    icon: Icons.cell_tower_rounded,
    providers: <String>[
      'PLDT Enterprise',
      'Smart',
      'Globe Telecom',
      'DITO',
    ],
  ),
  _CapabilityFamily(
    name: 'Communications',
    icon: Icons.forum_outlined,
    providers: <String>[
      'Vonage',
      'Twilio',
      'carrier A2P/SMS providers',
    ],
  ),
  _CapabilityFamily(
    name: 'Marketing',
    icon: Icons.campaign_outlined,
    providers: <String>[
      'Meta/Facebook Ads',
      'Google Ads',
      'Voluum',
    ],
  ),
  _CapabilityFamily(
    name: 'Commerce',
    icon: Icons.storefront_outlined,
    providers: <String>[
      'Shopify',
      'WooCommerce',
      'Shopee',
      'Lazada',
      'GrabFood',
      'foodpanda',
      'POS systems',
    ],
  ),
  _CapabilityFamily(
    name: 'Money',
    icon: Icons.account_balance_wallet_outlined,
    providers: <String>[
      'Maya',
      'banks',
      'payment gateways',
      'wallets',
      'card networks',
      'Xero',
      'QuickBooks',
      'ERP/accounting providers',
    ],
  ),
  _CapabilityFamily(
    name: 'Logistics',
    icon: Icons.local_shipping_outlined,
    providers: <String>[
      'Grab',
      'Lalamove',
      'future courier/mobility providers',
    ],
  ),
  _CapabilityFamily(
    name: 'Identity',
    icon: Icons.badge_outlined,
    providers: <String>[
      'Ubivelox Philippines',
      'enterprise identity providers',
      'approved KYC services',
      'PhilSys/eVerify where authorized',
    ],
  ),
  _CapabilityFamily(
    name: 'Government',
    icon: Icons.account_balance_outlined,
    providers: <String>[
      'DICT/eGov',
      'PSA/OpenSTAT',
      'PSGC',
      'SEC Philippines',
      'other legitimately accessible government agencies',
    ],
  ),
  _CapabilityFamily(
    name: 'Location',
    icon: Icons.location_on_outlined,
    providers: <String>[
      'Google Maps',
      'Google Places',
      'Google Routes',
      'future mapping providers',
    ],
  ),
  _CapabilityFamily(
    name: 'Documents',
    icon: Icons.description_outlined,
    providers: <String>[
      'Adobe/document services',
      'DocuSign',
      'future e-signature/document providers',
    ],
  ),
  _CapabilityFamily(
    name: 'Security',
    icon: Icons.shield_outlined,
    providers: <String>[
      'identity/security providers',
      'endpoint security',
      'fraud/security services',
    ],
  ),
  _CapabilityFamily(
    name: 'Devices',
    icon: Icons.devices_other_outlined,
    providers: <String>[
      'Android',
      'Apple/iPhone',
      'enterprise phones',
      'kiosks and edge hardware',
      'cameras',
      'access control',
      'hotel locks',
      'sensors',
      'printers',
      'POS terminals',
      'building systems',
    ],
  ),
  _CapabilityFamily(
    name: 'Intelligence',
    icon: Icons.auto_awesome_outlined,
    providers: <String>[
      'cloud AI/model providers',
      'local/on-device AI',
    ],
  ),
];
