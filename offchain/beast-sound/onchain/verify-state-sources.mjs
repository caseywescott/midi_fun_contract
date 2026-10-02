// Read-only readiness check. This does not deploy contracts or change live pointers.
// node onchain/verify-state-sources.mjs <rpc> <116-bit NFT address> <token_id>
import { poseidonHashMany } from '@scure/starknet';
import { selector } from '../src/chain.js';
import { decodeTokenId } from '../src/index.js';
const [rpc,collection,id]=process.argv.slice(2);
if(!rpc||!collection||!id) throw new Error('usage: <rpc> <116-bit NFT address> <token_id>');
const token=BigInt(id), beast=decodeTokenId(token);
if(token>>116n || beast.id>75) throw new Error('unsupported token format/defeat source');
const hex=n=>'0x'+BigInt(n).toString(16);
const post=async(method,params)=>{
  const response=await fetch(rpc,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(15000)});
  const data=await response.json(); if(data.error) throw new Error(JSON.stringify(data.error)); return data.result;
};
const block=Number(await post('starknet_blockNumber',[]));
const blockId={block_number:block};
const call=(address,name,calldata=[])=>post('starknet_call',{request:{contract_address:address,entry_point_selector:selector(name),calldata:calldata.map(hex)},block_id:blockId});
const t=[token&((1n<<128n)-1n),token>>128n];
const started=performance.now();
const [owner,source,kills,rank,count]=await Promise.all([call(collection,'owner_of',t),call(collection,'get_death_mountain_address'),call(collection,'get_adventurers_killed',t),call(collection,'get_beast_rank',t),call(collection,'get_species_count',[beast.id])]);
if(BigInt(owner[0])===0n||BigInt(source[0])===0n) {
  console.log(JSON.stringify({ready:false,checked_at:new Date().toISOString(),block,collection,token_id:hex(token),owner:owner[0],death_mountain:source[0],reason:'minted token or configured defeat source unavailable',read_ms:Math.round(performance.now()-started)},null,2));
  process.exit(2);
}
const entityHash=poseidonHashMany([BigInt(beast.id),BigInt(beast.prefix),BigInt(beast.suffix)]);
const [collects,nftClass,sourceClass]=await Promise.all([call(source[0],'get_collectable_count',[source[0],entityHash]),post('starknet_getClassHashAt',{block_id:blockId,contract_address:collection}),post('starknet_getClassHashAt',{block_id:blockId,contract_address:source[0]})]);
const total=BigInt(collects[0]);
console.log(JSON.stringify({ready:true,checked_at:new Date().toISOString(),block,collection,token_id:hex(token),nft_class_hash:nftClass,death_mountain:source[0],source_class_hash:sourceClass,namespace:source[0],owner:owner[0],live:{adventurers_killed:BigInt(kills[0]).toString(),scars:(total>0n?total-1n:0n).toString(),summit_held_seconds:0,rank:Number(BigInt(rank[0])),species_count:Number(BigInt(count[0]))},read_ms:Math.round(performance.now()-started),note:'Class hashes and getter calls verified; verify target source code and self-address namespace against pinned documentation before deployment.'},null,2));
