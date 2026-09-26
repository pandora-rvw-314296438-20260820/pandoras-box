import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {createClient} from "jsr:@supabase/supabase-js@2.57.2";
import {NativeInferenceStore} from "../../../packages/pandora-operations-inference/native-store.mjs";
import {OperationsInferenceService} from "../../../packages/pandora-operations-inference/service.mjs";
import {GeminiNativeProvider} from "../../../packages/pandora-operations-inference/gemini-native.mjs";
import {createInferenceHandler} from "../../../packages/pandora-operations-inference/http-handler.mjs";

const canonical = "https://jcyqixttuebxqqfkjonq.supabase.co";
const url = Deno.env.get("SUPABASE_URL") ?? "";
if (url !== canonical) throw new Error("INFERENCE_PROJECT_CONFIGURATION_DENIED");
const boundedFetch: typeof fetch = (input, init = {}) => fetch(input, {
  ...init, redirect: "error", signal: AbortSignal.any([
    ...(init.signal ? [init.signal] : []), AbortSignal.timeout(15000),
  ]),
});
const admin = createClient(canonical, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
  auth: {persistSession: false, autoRefreshToken: false}, global: {fetch: boundedFetch},
});
const publicClient = createClient(canonical, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
  auth: {persistSession: false, autoRefreshToken: false}, global: {fetch: boundedFetch},
});
const store = new NativeInferenceStore(admin);
// This is a model provider, not a replacement ChatGPT worker fleet. Policy still
// needs genuine provider approval, observed health, a cost ceiling and live lease.
const service = new OperationsInferenceService({store, providers: {
  gemini_rpc: new GeminiNativeProvider(admin),
}});
Deno.serve(createInferenceHandler({
  store,
  // Do not impersonate the existing Vercel Memory principal or copy its credential.
  // A separately authenticated native Memory binding is required to enable a
  // requireMemoryContext policy. Missing configuration fails closed in the service.
  serviceForActor: () => ({service, memory: null}),
  authenticateOwner: async (jwt: string) => {
    const {data, error} = await publicClient.auth.getUser(jwt);
    if (error || !data.user || data.user.is_anonymous) return null;
    return {userId: data.user.id, active: true};
  },
  allowedOrigins: (Deno.env.get("PANDORA_OPERATIONS_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean),
}));
