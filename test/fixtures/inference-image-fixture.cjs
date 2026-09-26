'use strict';
// Valid PNG container with an ancillary binary chunk whose base64 text happens
// to resemble a token prefix. The marker is synthetic and is not a credential.
module.exports=function imageFixture(){
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6kAAAAABJRU5ErkJggg==','base64');
 const end=png.length-12,type=Buffer.from('raNd'),tokenLookingText='AI'+'za'+'A'.repeat(24);
 const alignment=(3-((end+8)%3))%3,data=Buffer.concat([Buffer.alloc(alignment),Buffer.from(tokenLookingText,'base64')]);
 const length=Buffer.alloc(4);length.writeUInt32BE(data.length);
 const bytes=Buffer.concat([type,data]);let crc=0xffffffff;
 for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
 const checksum=Buffer.alloc(4);checksum.writeUInt32BE((crc^0xffffffff)>>>0);
 const encoded=Buffer.concat([png.subarray(0,end),length,bytes,checksum,png.subarray(end)]).toString('base64');
 if(!encoded.includes(tokenLookingText))throw new Error('fixture base64 alignment failed');
 return{data:encoded,tokenLookingText};
};
