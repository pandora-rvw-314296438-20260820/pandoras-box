'use strict';
const {deflateSync}=require('node:zlib');
// Construct a standards-shaped PNG, including valid chunk CRCs, rather than
// labeling arbitrary binary as an image. The marker is synthetic, not a key.
module.exports=function imageFixture(){
 function chunk(name,data){const type=Buffer.from(name),length=Buffer.alloc(4),bytes=Buffer.concat([type,data]);length.writeUInt32BE(data.length);
  let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
  const checksum=Buffer.alloc(4);checksum.writeUInt32BE((crc^0xffffffff)>>>0);return Buffer.concat([length,bytes,checksum]);}
 const header=Buffer.alloc(13);header.writeUInt32BE(1,0);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
 const prefix=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,0,0,0,0])))]);
 const tokenLookingText='AI'+'za'+'A'.repeat(24),alignment=(3-((prefix.length+8)%3))%3;
 const data=Buffer.concat([Buffer.alloc(alignment),Buffer.from(tokenLookingText,'base64')]);
 const encoded=Buffer.concat([prefix,chunk('raNd',data),chunk('IEND',Buffer.alloc(0))]).toString('base64');
 if(!encoded.includes(tokenLookingText))throw new Error('fixture base64 alignment failed');
 return{data:encoded,tokenLookingText};
};
