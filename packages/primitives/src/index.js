'use strict';
const contracts=require('./contracts');
const semver=require('./semver');
const lifecycle=require('./lifecycle');
const materialization=require('./materialization');
const controlPlaneLineage=require('./control-plane-lineage');
const {validateConfiguration}=require('./configuration');
const {TrustedPrimitiveRegistry,digest,primitiveKey,stableStringify}=require('./registry');
const {composePrimitives,deriveGeneratedSourceLineage}=require('./composition');
const {inferPrimitiveRequirements,resolvePrimitiveRequirements,resolveProjectSpecPrimitives}=require('./selection');
const {INITIAL_PRIMITIVES}=require('./catalog');
function createDefaultPrimitiveRegistry(options={}){return new TrustedPrimitiveRegistry(INITIAL_PRIMITIVES,options);}
module.exports={...contracts,...semver,...lifecycle,...materialization,...controlPlaneLineage,INITIAL_PRIMITIVES,TrustedPrimitiveRegistry,composePrimitives,createDefaultPrimitiveRegistry,deriveGeneratedSourceLineage,digest,primitiveKey,stableStringify,validateConfiguration,inferPrimitiveRequirements,resolvePrimitiveRequirements,resolveProjectSpecPrimitives};
