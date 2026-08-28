'use strict';
const contracts=require('./contracts'); const semver=require('./semver'); const {validateConfiguration}=require('./configuration'); const {TrustedPrimitiveRegistry,digest,primitiveKey,stableStringify}=require('./registry'); const {composePrimitives,deriveGeneratedSourceLineage}=require('./composition'); const {INITIAL_PRIMITIVES}=require('./catalog');
function createDefaultPrimitiveRegistry(){return new TrustedPrimitiveRegistry(INITIAL_PRIMITIVES);}
module.exports={...contracts,...semver,INITIAL_PRIMITIVES,TrustedPrimitiveRegistry,composePrimitives,createDefaultPrimitiveRegistry,deriveGeneratedSourceLineage,digest,primitiveKey,stableStringify,validateConfiguration};
