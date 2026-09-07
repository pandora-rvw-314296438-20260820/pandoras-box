if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  void (async () => {
    const assetVersion = 'web-publish-truth-v2-20260907-1';
    const versioned = (asset) => `${asset}?v=${assetVersion}`;

    await import(versioned('/control-tower/owner-data.js'));
    await import(versioned('/control-tower/owner-runtime.js'));
    await import(versioned('/control-tower/owner-screens-core.js'));
    await import(versioned('/control-tower/owner-screens-activity.js'));
    await import(versioned('/control-tower/owner-screens-more.js'));
    await import(versioned('/control-tower/owner-screens-experience.js'));
    await import(versioned('/control-tower/owner-project-workspace.js'));
    await import(versioned('/control-tower/owner-professional.js'));
    await import(versioned('/control-tower/owner-screens.js'));
    await import(versioned('/control-tower/owner-dialogs.js'));
    await import(versioned('/control-tower/owner-app.js'));
  })();
}
