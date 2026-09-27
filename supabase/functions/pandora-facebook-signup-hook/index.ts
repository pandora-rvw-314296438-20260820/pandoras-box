import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { handleFacebookSignupHook } from "./policy.mjs";

// The Supabase gateway must use verify_jwt=false for Auth's signed HTTP hook.
// The handler checks Standard Webhooks HMAC before it trusts any provider field.
Deno.serve((request: Request) =>
  handleFacebookSignupHook(request, Deno.env.get("BEFORE_USER_CREATED_HOOK_SECRET"))
);
