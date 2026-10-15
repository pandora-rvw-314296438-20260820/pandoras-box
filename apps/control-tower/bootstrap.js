if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  void (async () => {
    const assetVersion = 'control-tower-esm-v1-20261015-1';
    const versioned = (asset) => `${asset}?v=${assetVersion}`;

    // Load the single canonical owner application and its ES-module screens.
    await import(versioned('/control-tower/owner-app.js'));
    // Optional read-only telemetry never blocks the owner workspace.
    void import(versioned('/control-tower/owner-operations-theatre.mjs'))
      .then(() => window.PandoraOperationsTheatreMount?.update())
      .catch(() => console.warn('Operations execution feed unavailable'));
  })();
}
