'use strict';

const {
  createPandoraLifecycleTelemetry,
  pandoraLifecycleTelemetryEnabled,
  pandoraProductionTelemetryApproved,
} = require('./pandora-lifecycle.js');
const { createPostHogCaptureTransport } = require('./pandora-posthog-transport.js');

function runtimeEnvironment(env = process.env) {
  const explicit = env.PANDORA_RUNTIME_ENV;
  if (explicit) return explicit;
  if (env.VERCEL_ENV === 'production') return 'production';
  if (env.VERCEL_ENV === 'preview') return 'preview';
  if (env.VERCEL_ENV === 'development') return 'development';
  if (env.NODE_ENV === 'test') return 'test';
  if (env.NODE_ENV === 'development') return 'development';
  return 'unknown';
}

function createPandoraPostHogTelemetryFromEnv({ env = process.env, fetchImpl = globalThis.fetch, logger = console } = {}) {
  const environment = runtimeEnvironment(env);
  const enabled = pandoraLifecycleTelemetryEnabled(env);
  const productionApproved = pandoraProductionTelemetryApproved(env);
  if (!enabled) return createPandoraLifecycleTelemetry({ enabled: false, environment, logger });

  const projectToken = env.PANDORA_POSTHOG_PROJECT_TOKEN;
  const pseudonymizationKey = env.PANDORA_POSTHOG_PSEUDONYMIZATION_KEY;
  if (typeof projectToken !== 'string' || projectToken.length === 0) throw new Error('enabled Pandora PostHog telemetry requires project token');
  if (typeof pseudonymizationKey !== 'string' || pseudonymizationKey.length < 32) throw new Error('enabled Pandora PostHog telemetry requires pseudonymization key');

  const transport = createPostHogCaptureTransport({
    projectToken,
    host: env.PANDORA_POSTHOG_HOST || 'https://us.i.posthog.com',
    fetchImpl,
    allowProduction: productionApproved,
  });

  return createPandoraLifecycleTelemetry({
    enabled: true,
    environment,
    capture: transport.capture,
    pseudonymizationKey,
    productionApproved,
    logger,
  });
}

async function capturePandoraLifecycleFromEnv(input, options) {
  const telemetry = createPandoraPostHogTelemetryFromEnv(options);
  return telemetry.captureLifecycle(input);
}

module.exports = {
  runtimeEnvironment,
  createPandoraPostHogTelemetryFromEnv,
  capturePandoraLifecycleFromEnv,
};
