const issuer = "https://token.actions.githubusercontent.com";
const repository = "pandora-rvw-314296438-20260820/pandoras-box";
const ref = "refs/heads/fix/phone-private-model-lifecycle-20260920";
const workflow = repository + "/.github/workflows/plp-pandora-enterprise-android.yml@" + ref;
function decode(value: string): Uint8Array {
  const normalized=value.replace(/-/g,"+").replace(/_/g,"/");
  return Uint8Array.from(atob(normalized.padEnd(Math.ceil(normalized.length/4)*4,"=")),c=>c.charCodeAt(0));
}
export async function verifyPublisherJwt(token: string, fetcher: typeof fetch = fetch) {
  if (token.length>16000) throw Error("AUTH");
  const parts=token.split(".");
  if(parts.length!==3)throw Error("AUTH");
  const header=JSON.parse(new TextDecoder().decode(decode(parts[0])));
  if(header.alg!=="RS256"||typeof header.kid!=="string")throw Error("AUTH");
  const response=await fetcher(issuer+"/.well-known/jwks",{signal:AbortSignal.timeout(10000)});
  if(!response.ok)throw Error("AUTH");
  const keys=await response.json();
  const key=keys.keys?.find((item:JsonWebKey & {kid:string})=>item.kid===header.kid);
  if(!key)throw Error("AUTH");
  const imported=await crypto.subtle.importKey("jwk",key,
    {name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["verify"]);
  const valid=await crypto.subtle.verify("RSASSA-PKCS1-v1_5",imported,
    decode(parts[2]),new TextEncoder().encode(parts[0]+"."+parts[1]));
  if(!valid)throw Error("AUTH");
  const claims=JSON.parse(new TextDecoder().decode(decode(parts[1])));
  const now=Math.floor(Date.now()/1000);
  if(claims.iss!==issuer||claims.aud!=="pandora-model-publisher"||
     claims.repository!==repository||claims.repository_id!=="1345495177"||
     claims.ref!==ref||claims.workflow_ref!==workflow||
     claims.event_name!=="workflow_dispatch"||
     typeof claims.exp!=="number"||claims.exp<=now||claims.exp>now+600||
     typeof claims.iat!=="number"||claims.iat>now+30||claims.iat<now-600||
     !/^[0-9a-f]{40}$/.test(claims.sha)||!/^[0-9]+$/.test(claims.run_id))throw Error("AUTH");
  return claims as {sha:string;run_id:string;run_attempt:string};
}
