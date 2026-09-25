import { copyFile, mkdir, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { SignedAresProofs } from './authority.mjs';
import { containedFile, hashFile } from './process.mjs';
import { AresError, SHA256, demand, exact, immutable, integer, rejectSecrets } from './contract.mjs';

const ABIS=new Set(['arm64-v8a','armeabi-v7a','x86','x86_64']);
export function parseApkBadging(text) {
  demand(typeof text==='string' && text.length<=1024*1024,'ARES_APK_BADGING_LIMIT');
  const match=/^package: name='([^']+)' versionCode='([0-9]+)'/m.exec(text);
  demand(match,'ARES_APK_IDENTITY_UNREADABLE');
  const native=/^native-code:\s*(.+)$/m.exec(text);
  const abis=native?[...native[1].matchAll(/'([^']+)'/g)].map(x=>x[1]):[];
  demand(abis.length>0 && abis.every(x=>ABIS.has(x)) && new Set(abis).size===abis.length,'ARES_APK_ABI_UNVERIFIED');
  return {packageName:match[1],versionCode:integer(Number(match[2]),1,0x7fffffff,'ARES_APK_VERSION_INVALID'),abis:abis.sort()};
}
export function parseSigner(text) {
  const matches=[...text.matchAll(/^Signer #[0-9]+ certificate SHA-256 digest:\s*([a-f0-9:]+)\s*$/gmi)];
  demand(matches.length===1,'ARES_APK_SIGNER_UNVERIFIED');
  const value=matches[0][1].replaceAll(':','').toLowerCase();
  demand(SHA256.test(value),'ARES_APK_SIGNER_UNVERIFIED');
  return value;
}
export class AresArtifactVerifier {
  constructor({proofs,resolveArtifact,artifactRoot,cacheRoot,runner}) {
    demand(proofs instanceof SignedAresProofs && typeof resolveArtifact==='function','ARES_ARTIFACT_TRUST_REQUIRED');
    demand(path.isAbsolute(artifactRoot) && path.isAbsolute(cacheRoot) && runner,'ARES_ARTIFACT_PATH_REQUIRED');
    this.proofs=proofs;this.resolveArtifact=resolveArtifact;this.artifactRoot=artifactRoot;this.cacheRoot=cacheRoot;this.runner=runner;
  }
  async materialize(job,{runTool,signal}={}) {
    demand(job.artifactRef,'ARES_ARTIFACT_REQUIRED');
    const asset=await this.resolveArtifact(job.artifactRef,{signal});
    exact(asset,['path','manifestToken']);
    demand(typeof asset.path==='string' && typeof asset.manifestToken==='string','ARES_ARTIFACT_RESPONSE_INVALID');
    const manifest=this.proofs.verifyToken(asset.manifestToken,'PANDORA_ARES_APK_V1');
    exact(manifest,['iss','aud','iat','nbf','exp','jti','organizationId','projectId','artifactRef','sourceSha','apkSha256','packageName','versionCode','signerSha256','abis','verificationRef']);
    demand(manifest.organizationId===job.organizationId && manifest.projectId===job.projectId && manifest.artifactRef===job.artifactRef && manifest.sourceSha===job.sourceSha && manifest.packageName===job.target.packageName,'ARES_ARTIFACT_SCOPE_MISMATCH');
    demand(SHA256.test(manifest.apkSha256) && SHA256.test(manifest.signerSha256),'ARES_APK_DIGEST_REQUIRED');
    integer(manifest.versionCode,1,0x7fffffff,'ARES_APK_VERSION_INVALID');
    demand(Array.isArray(manifest.abis) && manifest.abis.length>0 && manifest.abis.length<=4 && manifest.abis.every(x=>ABIS.has(x)) && new Set(manifest.abis).size===manifest.abis.length,'ARES_APK_ABI_INVALID');
    demand(typeof manifest.verificationRef==='string' && manifest.verificationRef.length>0 && manifest.verificationRef.length<=1000,'ARES_ARTIFACT_VERIFICATION_REQUIRED');
    rejectSecrets(manifest);
    const source=await containedFile(this.artifactRoot,asset.path,{extension:'.apk'});
    demand(await hashFile(source)===manifest.apkSha256,'ARES_APK_SOURCE_DIGEST_MISMATCH');
    await mkdir(this.cacheRoot,{recursive:true,mode:0o700});
    const cacheRoot=await realpath(this.cacheRoot);
    demand((process.platform==='win32'?cacheRoot.toLowerCase()===path.resolve(this.cacheRoot).toLowerCase():cacheRoot===path.resolve(this.cacheRoot)),'ARES_APK_CACHE_PATH_ESCAPE');
    const cached=path.join(cacheRoot,manifest.apkSha256+'.apk');
    if(source!==cached) {
      try {await copyFile(source,cached,constants.COPYFILE_EXCL);}
      catch(error) {if(error.code!=='EEXIST')throw new AresError('ARES_APK_COPY_FAILED');}
    }
    const file=await containedFile(cacheRoot,cached,{extension:'.apk'});
    demand(await hashFile(file)===manifest.apkSha256,'ARES_APK_CACHE_DIGEST_MISMATCH');
    if(signal?.aborted)throw new AresError('ARES_CANCELLED');
    const execute=runTool??((tool,args,options)=>this.runner.run(tool,args,options));
    const badging=await execute('aapt',['dump','badging',file],{timeoutMs:15000,signal});
    demand(badging.code===0,'ARES_APK_BADGING_FAILED');
    const identity=parseApkBadging(badging.stdout.toString('utf8'));
    demand(identity.packageName===manifest.packageName && identity.versionCode===manifest.versionCode && JSON.stringify(identity.abis)===JSON.stringify([...manifest.abis].sort()),'ARES_APK_IDENTITY_MISMATCH');
    const jar=await this.runner.verifiedPath('apksignerJar');
    const signing=await execute('java',['-jar',jar,'verify','--print-certs',file],{timeoutMs:30000,signal});
    demand(signing.code===0,'ARES_APK_SIGNATURE_FAILED');
    demand(parseSigner(signing.stdout.toString('utf8'))===manifest.signerSha256,'ARES_APK_SIGNER_MISMATCH');
    demand(await hashFile(file)===manifest.apkSha256,'ARES_APK_CHANGED_AFTER_VERIFICATION');
    return immutable({file,manifest:structuredClone(manifest),apkSha256:manifest.apkSha256,sourceSha:manifest.sourceSha,packageName:manifest.packageName,versionCode:manifest.versionCode,abis:[...manifest.abis],signerSha256:manifest.signerSha256,verificationRef:manifest.verificationRef});
  }
}
