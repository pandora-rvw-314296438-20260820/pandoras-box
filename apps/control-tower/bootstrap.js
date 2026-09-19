if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  void (async () => {
    const assetVersion = 'pandora-provider-policy-v1-20260919-1';
    const versioned = (asset) => `${asset}?v=${assetVersion}`;

    // The legacy advanced Control Tower depended on retired ProjectOS code.
    // Keep the active web shell on the Pandora-native owner experience only.
    await import(versioned('/control-tower/owner-first.js'));
  })();
}
