"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createLibraryIndexExecutor = createLibraryIndexExecutor;
const rest_client_1 = require("../supabase/rest-client.js");

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA_RE=/^[0-9a-f]{64}$/i;
function text(value){ return typeof value==="string" ? value.trim() : ""; }
function rows(value){ return Array.isArray(value) ? value.filter((x)=>x&&typeof x==="object"&&!Array.isArray(x)) : []; }
function safeLimit(value){ const n=Number(value); return Number.isInteger(n)&&n>=1&&n<=100 ? n : 50; }
function uuid(value){ const v=text(value).toLowerCase(); return UUID_RE.test(v)?v:""; }

function createLibraryIndexExecutor(options){
  const organizationId=uuid(options.organizationId);
  const supabaseUrl=new URL(options.supabaseUrl);
  const publishableKey=text(options.publishableKey);
  const fetchFn=options.fetchFn ?? fetch;
  if(!organizationId || (supabaseUrl.protocol!=="https:"&&supabaseUrl.hostname!=="localhost") || !publishableKey) throw new Error("Library index executor is not configured");

  return async function executeLibraryIndex(input){
    const accessToken=text(input?.actor?.identity?.accessToken);
    if(!accessToken) throw Object.assign(new Error("Please sign in again."),{status:401,code:"LIBRARY_SESSION_INVALID"});
    const limit=safeLimit(input?.limit);
    const client=new rest_client_1.SupabaseRestClient({
      supabaseUrl:supabaseUrl.toString(), apiKey:publishableKey, accessToken, fetchFn,
      timeoutMs:10000, maxResponseBytes:1024*1024,
    });
    const org=encodeURIComponent(organizationId);
    let projects, artifacts, artifactVersions, releases;
    try{
      [projects,artifacts,artifactVersions,releases]=await Promise.all([
        client.requestJson(`/rest/v1/projectos_projects?select=id,name,repository&organization_id=eq.${org}&order=updated_at.desc&limit=200`),
        client.requestJson(`/rest/v1/pandora_artifacts?select=id,project_id,logical_key,artifact_kind,created_at&organization_id=eq.${org}&order=created_at.desc&limit=200`),
        client.requestJson(`/rest/v1/pandora_artifact_versions?select=id,project_id,artifact_id,version,content_sha256,byte_size,media_type,created_at&organization_id=eq.${org}&order=created_at.desc&limit=${limit}`),
        client.requestJson(`/rest/v1/pandora_project_versions?select=id,project_id,sequence_no,kind,source_sha256,source_commit,artifact_digest_sha256,lifecycle_status,created_at&organization_id=eq.${org}&order=created_at.desc&limit=${limit}`),
      ]);
    }catch{
      throw Object.assign(new Error("Pandora could not load the bounded Library index."),{status:503,code:"LIBRARY_UNAVAILABLE"});
    }

    const projectMap=new Map(rows(projects).map((p)=>[uuid(p.id),{name:text(p.name)||"Project",repository:text(p.repository)}]));
    const artifactMap=new Map(rows(artifacts).map((a)=>[uuid(a.id),a]));
    const safeArtifacts=rows(artifactVersions).map((v)=>{
      const artifact=artifactMap.get(uuid(v.artifact_id))||{};
      const project=projectMap.get(uuid(v.project_id))||{name:"Project",repository:""};
      return {
        id:uuid(v.id), projectId:uuid(v.project_id), projectName:project.name, repository:project.repository,
        logicalKey:text(artifact.logical_key)||"artifact", artifactKind:text(artifact.artifact_kind)||"other",
        version:Number.isInteger(Number(v.version))?Number(v.version):null,
        byteSize:Number.isSafeInteger(Number(v.byte_size))&&Number(v.byte_size)>=0?Number(v.byte_size):null,
        mediaType:text(v.media_type)||"application/octet-stream",
        sha256:SHA_RE.test(text(v.content_sha256))?text(v.content_sha256).toLowerCase():null,
        createdAt:text(v.created_at)||null,
      };
    }).filter((x)=>x.id&&x.projectId);

    const safeReleases=rows(releases).map((v)=>{
      const project=projectMap.get(uuid(v.project_id))||{name:"Project",repository:""};
      return {
        id:uuid(v.id), projectId:uuid(v.project_id), projectName:project.name, repository:project.repository,
        sequenceNo:Number.isSafeInteger(Number(v.sequence_no))?Number(v.sequence_no):null,
        kind:text(v.kind)||"preview", lifecycleStatus:text(v.lifecycle_status)||"unknown",
        sourceSha256:SHA_RE.test(text(v.source_sha256))?text(v.source_sha256).toLowerCase():null,
        sourceCommit:/^[0-9a-f]{40}$/i.test(text(v.source_commit))?text(v.source_commit).toLowerCase():null,
        artifactDigest:SHA_RE.test(text(v.artifact_digest_sha256))?text(v.artifact_digest_sha256).toLowerCase():null,
        createdAt:text(v.created_at)||null,
      };
    }).filter((x)=>x.id&&x.projectId);

    return {ok:true,kind:"pandora.library-index.v1",generatedAt:new Date().toISOString(),artifacts:safeArtifacts,releases:safeReleases};
  };
}
