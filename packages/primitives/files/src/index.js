'use strict';
const crypto=require('node:crypto');
const DEFAULT_TYPES=Object.freeze(['image/jpeg','image/png','image/webp','application/pdf','text/plain']);
class PandoraFilesService {
  constructor({storage,repository,authorization=null,maxBytes=10*1024*1024,allowedContentTypes=DEFAULT_TYPES,maxSignedTtlSeconds=900}){
    if(!storage||typeof storage.putVerified!=='function'||typeof storage.signPrivateUrl!=='function'||typeof storage.remove!=='function')throw new TypeError('files storage contract is required');
    if(!repository||typeof repository.createMetadata!=='function'||typeof repository.getMetadata!=='function'||typeof repository.markDeleted!=='function')throw new TypeError('files repository contract is required');
    if(authorization&&typeof authorization.assertAllowed!=='function')throw new TypeError('files authorization.assertAllowed is required');
    if(!Number.isInteger(maxBytes)||maxBytes<1||maxBytes>100*1024*1024)throw new TypeError('maxBytes is invalid');
    if(!Array.isArray(allowedContentTypes)||allowedContentTypes.length===0||allowedContentTypes.length>64)throw new TypeError('allowedContentTypes is invalid');
    this.storage=storage;this.repository=repository;this.authorization=authorization;this.maxBytes=maxBytes;this.allowed=new Set(allowedContentTypes);this.maxSignedTtlSeconds=Math.min(3600,Math.max(60,maxSignedTtlSeconds));
  }
  async upload({scopeId,identity,fileName,declaredContentType,sizeBytes,bytes,imageTransform=null}){
    const scope=required(scopeId,'scopeId');const userId=required(identity&&identity.userId,'identity.userId');const name=safeName(fileName);const declared=contentType(declaredContentType);
    if(!Number.isInteger(sizeBytes)||sizeBytes<1||sizeBytes>this.maxBytes)throw Object.assign(new Error('file size outside allowed bounds'),{code:'FILE_SIZE_REJECTED'});
    if(!this.allowed.has(declared))throw Object.assign(new Error('declared content type is not allowed'),{code:'FILE_TYPE_REJECTED'});
    const objectKey=`${scope}/${userId}/${crypto.randomBytes(18).toString('hex')}-${name}`;
    const transform=validateImageTransform(imageTransform);
    const stored=await this.storage.putVerified({scopeId:scope,objectKey,bytes,sizeBytes,declaredContentType:declared,allowedContentTypes:[...this.allowed],maxBytes:this.maxBytes,imageTransform:transform});
    if(!stored||typeof stored.detectedContentType!=='string'||typeof stored.sha256!=='string'||typeof stored.byteSize!=='number')throw new Error('storage verification receipt is invalid');
    const detected=contentType(stored.detectedContentType);
    if(detected!==declared||!this.allowed.has(detected))throw Object.assign(new Error('detected content type does not match allowed declaration'),{code:'CONTENT_TYPE_MISMATCH'});
    if(stored.byteSize!==sizeBytes||stored.byteSize>this.maxBytes)throw new Error('storage byte-size verification mismatch');
    if(!/^[a-f0-9]{64}$/.test(stored.sha256))throw new Error('storage sha256 receipt is invalid');
    return this.repository.createMetadata({scopeId:scope,ownerUserId:userId,objectKey,originalName:name,detectedContentType:detected,byteSize:stored.byteSize,sha256:stored.sha256,imageTransform:transform});
  }
  async signAccess({scopeId,identity,fileId,ttlSeconds=300}){
    const scope=required(scopeId,'scopeId');const userId=required(identity&&identity.userId,'identity.userId');const file=await this.repository.getMetadata({scopeId:scope,fileId:required(fileId,'fileId')});
    if(!file||file.deletedAt)throw new Error('file unavailable');
    if(file.scopeId!==scope)throw new Error('cross-scope file rejected');
    if(file.ownerUserId!==userId){if(!this.authorization)throw Object.assign(new Error('file access denied'),{code:'PERMISSION_DENIED'});await this.authorization.assertAllowed({userId,tenantId:scope,permission:'files.read'});}
    const ttl=boundedTtl(ttlSeconds,this.maxSignedTtlSeconds);
    return this.storage.signPrivateUrl({objectKey:file.objectKey,ttlSeconds:ttl,disposition:'attachment',fileName:file.originalName});
  }
  async remove({scopeId,identity,fileId}){
    const scope=required(scopeId,'scopeId');const userId=required(identity&&identity.userId,'identity.userId');const file=await this.repository.getMetadata({scopeId:scope,fileId:required(fileId,'fileId')});
    if(!file||file.deletedAt)return Object.freeze({removed:false});
    if(file.scopeId!==scope)throw new Error('cross-scope file rejected');
    if(file.ownerUserId!==userId){if(!this.authorization)throw Object.assign(new Error('file delete denied'),{code:'PERMISSION_DENIED'});await this.authorization.assertAllowed({userId,tenantId:scope,permission:'files.manage'});}
    await this.storage.remove({objectKey:file.objectKey});await this.repository.markDeleted({scopeId:scope,fileId:file.id,actorUserId:userId});return Object.freeze({removed:true,fileId:file.id});
  }
}
function validateImageTransform(value){if(value==null)return null;if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError('imageTransform must be an object');const allowed=new Set(['width','height','fit','format','quality']);for(const key of Object.keys(value))if(!allowed.has(key))throw new TypeError(`imageTransform.${key} is not allowed`);const out={};for(const k of ['width','height'])if(value[k]!=null){if(!Number.isInteger(value[k])||value[k]<1||value[k]>4096)throw new TypeError(`imageTransform.${k} must be 1-4096`);out[k]=value[k];}if(value.fit!=null){if(!['cover','contain','inside'].includes(value.fit))throw new TypeError('imageTransform.fit is invalid');out.fit=value.fit;}if(value.format!=null){if(!['jpeg','png','webp'].includes(value.format))throw new TypeError('imageTransform.format is invalid');out.format=value.format;}if(value.quality!=null){if(!Number.isInteger(value.quality)||value.quality<40||value.quality>100)throw new TypeError('imageTransform.quality must be 40-100');out.quality=value.quality;}return Object.freeze(out);}
function boundedTtl(value,max){if(!Number.isInteger(value)||value<30||value>max)throw new TypeError(`ttlSeconds must be 30-${max}`);return value;}
function safeName(value){const name=required(value,'fileName').replace(/[^A-Za-z0-9._-]+/g,'-').replace(/^-+|-+$/g,'');if(!name||name.length>180||name==='.'||name==='..')throw new TypeError('fileName is invalid');return name;}
function contentType(value){if(typeof value!=='string'||!/^[-\w.+]+\/[-\w.+]+$/.test(value))throw new TypeError('content type is invalid');return value.toLowerCase();}
function required(v,f){if(typeof v!=='string'||!v.trim())throw new TypeError(`${f} is required`);return v.trim();}
module.exports={DEFAULT_TYPES,PandoraFilesService,boundedTtl,contentType,safeName,validateImageTransform};
