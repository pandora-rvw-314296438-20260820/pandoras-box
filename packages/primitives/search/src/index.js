'use strict';
class PandoraSearchService {
  constructor({provider,authorization=null,publicRead=false,permission='data.read'}){
    if(!provider||typeof provider.search!=='function')throw new TypeError('search provider.search is required');
    if(provider.scopeAware!==true)throw new Error('search provider must guarantee scope-aware queries');
    if(!publicRead&&(!authorization||typeof authorization.assertAllowed!=='function'))throw new TypeError('private search requires authorization.assertAllowed');
    this.provider=provider;this.authorization=authorization;this.publicRead=publicRead===true;this.permission=required(permission,'permission');
  }
  async search({scopeId,identity=null,query='',filters={},sort=null,cursor=null,limit=20}){
    const scope=required(scopeId,'scopeId');
    if(!this.publicRead){const userId=required(identity&&identity.userId,'identity.userId');await this.authorization.assertAllowed({userId,tenantId:scope,permission:this.permission});}
    const input=Object.freeze({scopeId:scope,query:boundedQuery(query),filters:normalizeFilters(filters),sort:normalizeSort(sort),cursor:normalizeCursor(cursor),limit:boundedLimit(limit)});
    const out=await this.provider.search(input);
    if(!out||out.scopeId!==scope||!Array.isArray(out.items))throw new Error('search provider returned invalid or cross-scope result');
    if(out.items.length>input.limit)throw new Error('search provider exceeded requested result bound');
    return Object.freeze({scopeId:scope,items:Object.freeze([...out.items]),nextCursor:normalizeCursor(out.nextCursor)});
  }
}
function boundedQuery(value){if(typeof value!=='string')throw new TypeError('query must be text');const v=value.trim();if(v.length>500)throw new TypeError('query must be <= 500 characters');return v;}
function normalizeFilters(value){if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError('filters must be an object');const entries=Object.entries(value);if(entries.length>16)throw new TypeError('filters are too broad');const out={};for(const [key,v] of entries){if(!/^[a-z][a-z0-9_.-]{0,63}$/.test(key))throw new TypeError(`invalid filter key: ${key}`);if(v==null||['string','number','boolean'].includes(typeof v)){if(typeof v==='string'&&v.length>300)throw new TypeError(`filter ${key} is too long`);out[key]=v;}else if(Array.isArray(v)&&v.length<=20&&v.every(x=>['string','number','boolean'].includes(typeof x))){out[key]=Object.freeze([...v]);}else throw new TypeError(`filter ${key} is not a bounded scalar/list`);}return Object.freeze(out);}
function normalizeSort(value){if(value==null)return null;if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError('sort must be an object');const field=required(value.field,'sort.field');if(!/^[a-z][a-z0-9_.-]{0,63}$/.test(field))throw new TypeError('sort.field is invalid');if(!['asc','desc'].includes(value.direction))throw new TypeError('sort.direction must be asc or desc');if(Object.keys(value).some(k=>!['field','direction'].includes(k)))throw new TypeError('unknown sort field');return Object.freeze({field,direction:value.direction});}
function normalizeCursor(value){if(value==null)return null;if(typeof value!=='string'||value.length<1||value.length>512)throw new TypeError('cursor is invalid');return value;}
function boundedLimit(value){if(!Number.isInteger(value)||value<1||value>200)throw new TypeError('limit must be 1-200');return value;}
function required(value,field){if(typeof value!=='string'||!value.trim())throw new TypeError(`${field} is required`);return value.trim();}
module.exports={PandoraSearchService,boundedLimit,boundedQuery,normalizeFilters,normalizeSort};
