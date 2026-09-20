import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import { MODEL } from "./model.ts";

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: {"content-type":"application/json", "cache-control":"no-store"},
});
Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({code:"METHOD"},405);
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer \S+$/.test(authorization)) return reply({code:"AUTH"},401);
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service, {auth:{persistSession:false,autoRefreshToken:false}});
  try {
    const {data: identity, error} = await admin.auth.getUser(authorization.slice(7));
    if (error || !identity.user || identity.user.is_anonymous) return reply({code:"AUTH"},401);
    // This model's provider license currently admits research/evaluation only.
    // Customer expansion requires separate model/license approval.
    const {data: membership, error: membershipError} = await admin.from("memberships")
      .select("organization_id").eq("user_id",identity.user.id)
      .eq("status","active").in("role",["owner","admin"]).limit(1);
    if (membershipError || !membership?.length) return reply({code:"SCOPE"},403);
    const {data: marker,error: markerError} = await admin.storage.from(MODEL.bucket)
      .download(MODEL.sha256 + "/distribution.json");
    if (markerError || !marker || marker.size > 16384) return reply({code:"PENDING"},503);
    const receipt = JSON.parse(await marker.text());
    if (receipt.sha256 !== MODEL.sha256 || receipt.bytes !== MODEL.bytes ||
        receipt.distributionVerified !== true) return reply({code:"PENDING"},503);
    const {data,error: grantError} = await admin.storage.from(MODEL.bucket)
      .createSignedUrl(MODEL.object,3600);
    if (grantError || !data?.signedUrl) return reply({code:"PENDING"},503);
    return reply({model:{
      version:MODEL.version,sha256:MODEL.sha256,bytes:MODEL.bytes,
      minSdk:MODEL.minSdk,minRamBytes:MODEL.minRamBytes,reserveBytes:MODEL.reserveBytes,
      downloadUrl:data.signedUrl,
    }});
  } catch (_) { return reply({code:"PENDING"},503); }
});
