export default async function health(_request: unknown, response: any) {
  response.setHeader('Cache-Control', 'no-store');
  try {
    // Literal module specifier is intentional: Vercel's Node file tracer must
    // see the canonical runtime dependency at build time.
    const runtime = await import('../.agents/runtime/pandora-skill-runtime.mjs');
    if (!runtime.skillsEnabled()) {
      return response.status(503).json({
        status: 'degraded',
        service: 'pandora-runtime',
        skills: { ready: false, reason: 'disabled', grantsMutation: false },
        timestamp: new Date().toISOString(),
      });
    }

    const registry = runtime.loadRegistry();
    const generated = [...registry.skills.values()].filter(
      (skill: any) => skill.generatedCapabilitySkill === true,
    );
    const routed = runtime.route('verify engineering deployment provider outcome', {
      registry,
      limit: 5,
    });
    const generatedProbe = runtime.loadSkill('discover-engineering-capabilities', { registry });
    const ready = registry.ids.length === 195
      && generated.length === 144
      && routed.selected.length > 0
      && routed.grantsMutation === false
      && generatedProbe.governanceEmbedded === true;

    return response.status(ready ? 200 : 503).json({
      status: ready ? 'healthy' : 'degraded',
      service: 'pandora-runtime',
      skills: {
        ready,
        total: registry.ids.length,
        staticCore: registry.ids.length - generated.length,
        generatedCapabilitySkills: generated.length,
        capabilityPacks: 48,
        capabilityClasses: 377,
        routeSelectedCount: routed.selected.length,
        generatedLoadVerified: generatedProbe.governanceEmbedded === true,
        mutationAuthority: routed.mutationAuthority,
        grantsMutation: routed.grantsMutation,
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const detail = error instanceof Error
      ? { name: error.name, code: (error as any).code ?? null, message: error.message.slice(0, 240) }
      : { name: 'UnknownError', code: null, message: 'non-error runtime failure' };
    console.error('pandora_skill_runtime_health_failure', detail);
    return response.status(503).json({
      status: 'degraded',
      service: 'pandora-runtime',
      skills: { ready: false, reason: 'skill_runtime_unavailable', grantsMutation: false },
      timestamp: new Date().toISOString(),
    });
  }
}
