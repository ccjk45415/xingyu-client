// LOCAL TEST ENTRY ONLY. Never referenced by production wrangler.jsonc.
import {DurableObject} from 'cloudflare:workers';
import {createDmHub,verifySiteIdentity} from '../src/dm-core.mjs';
const verify=(cookie,expected)=>verifySiteIdentity(cookie,expected,async()=>{
  const id=Number(/^local-fake-site-session-(\d+)$/.exec(cookie)?.[1]);
  return Response.json({code:0,data:{id,nickname:'本地测试 '+id,avatar:'',is_banned:false,is_muted:false}});
});
export class TestDmHub extends createDmHub(DurableObject,{verify}) {}
export default {async fetch(request,env){if(new URL(request.url).pathname==='/health')return Response.json({local_test:true});return env.DM.get(env.DM.idFromName('local-dm-only')).fetch(request);}};
