import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createAiHub,input,draft,sourceUrl,AI_POLICY} from '../src/ai-core.mjs';
const material=(id=crypto.randomUUID())=>({request_id:id,type:'auto',sources:[{url:'https://store.steampowered.com/app/620/',text:'Portal 2 is a puzzle game by Valve.',cover:''}],material:''});
const completion={type:'game',title:'Portal 2',summary:'Valve 的解谜游戏。',metadata:[{label:'开发商',value:'Valve'}],sections:[],tags:['解谜'],source_indices:[0]};
function fixture(infer=async()=>({response:JSON.stringify(completion)})){
  const db=new DatabaseSync(':memory:');const storage={sql:{exec(q,...p){const s=db.prepare(q);return {toArray:()=>s.all(...p)};}},transactionSync(fn){db.exec('BEGIN');try{const v=fn();db.exec('COMMIT');return v;}catch(e){db.exec('ROLLBACK');throw e;}},async getAlarm(){return null;},async setAlarm(){}};
  // Execute statements on exec, matching Durable Object SqlStorage's eager semantics.
  storage.sql.exec=(q,...p)=>{const s=db.prepare(q),a=s.all(...p);return {toArray:()=>a};};
  const env={DM:{idFromName:n=>n,get:()=>({fetch:async req=>{const b=await req.json();const uid=b.token_hash.startsWith('bad')?0:identities.get(b.token_hash);return uid?Response.json({user:{id:uid}}):Response.json({error:'expired'},{status:401});}})}};
  let now=Date.UTC(2026,9,21,12);const Hub=createAiHub(class {},{infer,clock:()=>now});const hub=new Hub({storage},env);
  return {hub,db,advance:(ms=86400000)=>{now+=ms;},post:(body,token='a'.repeat(64),path='/ai/v1/draft')=>hub.fetch(new Request('https://service.invalid'+path,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(body)}))};
}
const identities=new Map();
async function secret(uid,letter){const token=letter.repeat(64);const {digest}=await import('../src/ai-core.mjs');identities.set(await digest(token),uid);return token;}
test('AI strictly admits resource fields and public references; rejects chat/model/tool injection keys',()=>{
  assert.equal(input(material()).sources.length,1);
  for(const field of ['messages','system','model','endpoint','tools','max_tokens','uid']) assert.throws(()=>input({...material(),[field]:'override'}));
  for(const url of ['http://example.com','https://127.0.0.1/a','https://[::1]/','https://foo.local/a','https://user:pw@example.com/'])assert.throws(()=>sourceUrl(url));
  assert.throws(()=>input({...material(),material:'中'.repeat(5000)}));
  assert.throws(()=>input({...material(),sources:[]}));
});
test('structured drafts require type, bounded body and valid source indices; short introductions remain short',()=>{
  assert.equal(draft(completion,material()).summary,'Valve 的解谜游戏。');
  assert.throws(()=>draft({...completion,summary:'字'.repeat(2501)},material()));
  assert.throws(()=>draft({...completion,source_indices:[5]},material()));
  assert.throws(()=>draft({...completion,type:'chat'},material()));
  assert.throws(()=>draft('not json',material()));
});
test('atomic reservation, duplicate replay, changed nonce rejection, shared UID quota and UTC reset',async()=>{
  const ta=await secret(1,'a'),tb=await secret(1,'b');let calls=0;const f=fixture(async args=>{calls++;assert.equal(args.max_tokens,3000);assert.equal(args.messages.length,2);assert.equal(args.tools,undefined);return {choices:[{message:{content:JSON.stringify(completion)}}]};});
  const b=material();assert.equal((await f.post(b,ta)).status,200);assert.equal((await f.post(b,tb)).status,200);assert.equal(calls,1);
  assert.equal((await f.post({...b,material:'modified'},ta)).status,409);
  assert.equal((await f.post(material(),ta)).status,200);assert.equal((await f.post(material(),ta)).status,200);assert.equal((await f.post(material(),tb)).status,429);assert.equal(calls,3);
  f.advance();assert.equal((await f.post(material(),ta)).status,200);assert.equal(calls,4);f.db.close();
});
test('one concurrent inference per UID and failures/cancellation consume the reserved admission',async()=>{
  await secret(2,'c');let finish;const f=fixture(()=>new Promise(r=>finish=r));const pending=f.post(material(),'c'.repeat(64));
  for(let i=0;i<50&&!finish;i++)await new Promise(r=>setTimeout(r,1));assert.ok(finish);
  assert.equal((await f.post(material(),'c'.repeat(64))).status,409);finish({response:JSON.stringify(completion)});assert.equal((await pending).status,200);f.db.close();
  const failed=fixture(async()=>{throw Error('private provider details must never leak');});const b=material();const response=await failed.post(b);assert.equal(response.status,503);assert.equal((await response.text()).includes('private provider details'),false);assert.equal((await failed.post(b)).status,409);assert.equal(failed.db.prepare('SELECT n FROM ai_counts WHERE uid=1').get().n,1);failed.db.close();
});
test('global free budget halts all identities, invalid sessions never reserve and stale results expire',async()=>{
  const f=fixture();assert.equal((await f.post(material(),'f'.repeat(64))).status,401);
  for(let n=1;n<=8;n++){const token=await secret(100+n,n.toString(16));for(let i=0;i<2;i++)assert.equal((await f.post(material(),token)).status,200);}
  assert.equal((await f.post(material(),'a'.repeat(64))).status,429);assert.equal(f.db.prepare('SELECT n FROM ai_counts WHERE uid=0').get().n,AI_POLICY.global_day);f.db.close();
});

test('cached drafts are UID scoped and expire without re-running inference',async()=>{
  const ta=await secret(7,'a'),tb=await secret(8,'b');let calls=0;const f=fixture(async()=>{calls++;return {response:JSON.stringify(completion)};});const b=material();
  assert.equal((await f.post(b,ta)).status,200);assert.equal((await f.post(b,tb)).status,200);assert.equal(calls,2);
  f.advance(3600001);assert.equal((await f.post(b,ta)).status,409);assert.equal(calls,2);await f.hub.alarm();assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ai_runs WHERE result != \'\'').get().n,0);f.db.close();
});

test('v2 reserves all translation chunks atomically, charges UID once and replay never calls the model again',async()=>{
 const token=await secret(30,'a');let calls=0;
 const f=fixture(async args=>{calls++;const {segments}=JSON.parse(args.messages[1].content);assert.equal(args.tools,undefined);return {response:{translations:segments.map(v=>({id:v.id,text:v.text}))}};});
 const b={request_id:crypto.randomUUID(),type:'game',sources:[{url:'https://example.com/work',title:'A title',cover:'',blocks:[{kind:'p',text:'a'.repeat(1500)},{kind:'image',url:'https://cdn.example.com/panel.png',alt:'unchanged'}]}],material:''};
 const response=await f.post(b,token,'/ai/v2/draft');assert.equal(response.status,200);const result=await response.json();assert.equal(result.remaining,2);assert.equal(result.shared_remaining,16-calls);assert.equal(result.draft.blocks[0].text.length,1500);assert.equal(result.draft.blocks[1].url,'https://cdn.example.com/panel.png');const before=calls;assert.equal((await f.post(b,token,'/ai/v2/draft')).status,200);assert.equal(calls,before);f.db.close();
});
test('v2 insufficient shared budget refuses before any partial model work or personal charge',async()=>{
 const token=await secret(31,'b');let calls=0;const f=fixture(async()=>{calls++;return {};});f.db.prepare('INSERT INTO ai_counts(day,uid,n) VALUES(?,0,15)').run(Math.floor(Date.UTC(2026,9,21,12)/86400000));
 const b={request_id:crypto.randomUUID(),type:'auto',sources:[{url:'https://example.com/work',title:'',cover:'',blocks:[{kind:'p',text:'a'.repeat(1800)}]}],material:''};assert.equal((await f.post(b,token,'/ai/v2/draft')).status,429);assert.equal(calls,0);assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ai_counts WHERE uid=31').get().n,0);f.db.close();
});

test('old v1 failures receive only one upgrade retry, shared spending is never refunded',async()=>{
 const token=await secret(35,'c');let old=true;const f=fixture(async args=>{if(old)throw Error('legacy formatting failure');const {segments}=JSON.parse(args.messages[1].content);return {response:{translations:segments}};});
 for(let i=0;i<3;i++)assert.equal((await f.post(material(),token)).status,503);old=false;
 const request=()=>({request_id:crypto.randomUUID(),type:'auto',sources:[{url:'https://example.com/work',title:'',cover:'',blocks:[{kind:'p',text:'A neutral introduction.'}]}],material:''});
 const translated=await f.post(request(),token,'/ai/v2/draft');assert.equal(translated.status,200);const data=await translated.json();assert.equal(data.remaining,0);assert.equal(data.shared_remaining,12);assert.equal((await f.post(request(),token,'/ai/v2/draft')).status,429);assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ai_translation_credits WHERE uid=35').get().n,1);assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ai_runs WHERE protocol=2').get().n,1);f.db.close();
});
