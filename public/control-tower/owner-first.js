if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  void (async () => {
    const assetVersion = 'owner-first-header-hotfix-20260806-1';
    const versioned = (asset) => `${asset}?v=${assetVersion}`;

    await import(versioned('/control-tower/owner-data.js'));
    await import(versioned('/control-tower/owner-runtime.js'));
    await import(versioned('/control-tower/owner-screens-core.js'));
    await import(versioned('/control-tower/owner-screens-events.js'));
    await import(versioned('/control-tower/owner-screens-more.js'));
    await import(versioned('/control-tower/owner-screens.js'));
    await import(versioned('/control-tower/owner-dialogs.js'));
    await import(versioned('/control-tower/owner-app.js'));
  })();
}
