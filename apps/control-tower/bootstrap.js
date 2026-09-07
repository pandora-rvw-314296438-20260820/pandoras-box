if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  void (async () => {
    const advanced = new URLSearchParams(window.location.search).get('advanced') === '1';
    const assetVersion = 'web-project-workspace-v1-20260907-1';
    const versioned = (asset) => `${asset}?v=${assetVersion}`;

    if (advanced) {
      document.body.classList.add('advanced-control-mode');
      await import(versioned('/control-tower/app.js'));
      await import(versioned('/control-tower/simple-language.js'));
      await import(versioned('/control-tower/pandoras-box-branding.js'));
    } else {
      await import(versioned('/control-tower/owner-first.js'));
    }
  })();
}
