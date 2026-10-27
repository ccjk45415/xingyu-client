import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';

test('real Worker fetch receiver: enroll, enable, status, disable',async()=>{
  const eventModule=await readFile(new URL('../src/checkin-events.mjs',import.meta.url),'utf8');
  const core=await readFile(new URL('../src/checkin-core.mjs',import.meta.url),'utf8');
  const mf=new Miniflare(convertV4MiniflareOptions({workers:[{
    name:'checkin',compatibilityDate:'2026-10-20',modules:[
      {type:'ESModule',path:'worker.js',contents:`import {DurableObject} from 'cloudflare:workers';import {createCheckinHub} from './checkin-core.mjs';export const CheckinHub=createCheckinHub(DurableObject);export default {fetch(req,env){return env.CHECKIN.get(env.CHECKIN.idFromName('test')).fetch(req)}}`},
      {type:'ESModule',path:'checkin-core.mjs',contents:core},{type:'ESModule',path:'checkin-events.mjs',contents:eventModule}],
    bindings:{CHECKIN_ENCRYPTION_KEY:'a'.repeat(64)},
    durableObjects:{CHECKIN:{className:'CheckinHub',useSQLite:true}},
    outboundService:'website-fixture'
  },{
    name:'website-fixture',compatibilityDate:'2026-10-20',modules:true,
    script:`export default {async fetch(req){const u=new URL(req.url);if(u.origin!=='https://cangku.moe'||u.pathname!=='/api/v1/auth/me')return new Response(null,{status:404});if(req.headers.get('Cookie')!=='session=synthetic-runtime-test')return new Response(null,{status:401});return Response.json({code:0,data:{id:17,is_banned:false,is_muted:false,is_signed:false}})}}`
  }]}));
  try{
    async function request(path,data,token){return mf.dispatchFetch('https://test.invalid/checkin/v1/'+path,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},...(data?{body:JSON.stringify(data)}:{})});}
    const cookie='session=synthetic-runtime-test';
    const enrolled=await request('session',{site_cookie:cookie,expected_user_id:17});
    assert.equal(enrolled.status,200,await enrolled.clone().text());
    const {token}=await enrolled.json();
    const enabled=await request('enable',{site_cookie:cookie,consent:true},token);
    assert.equal(enabled.status,200,await enabled.clone().text());assert.equal((await enabled.json()).enabled,true);
    assert.equal((await (await request('status',null,token)).json()).enabled,true);
    assert.equal((await (await request('disable',{},token)).json()).enabled,false);
    assert.equal((await request('session',{site_cookie:'invalid=synthetic',expected_user_id:17})).status,401);
  }finally{await mf.dispose();}
});
