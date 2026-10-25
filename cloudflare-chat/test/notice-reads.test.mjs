import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createDmHub} from '../src/dm-core.mjs';

function fixture(){
  const db=new DatabaseSync(':memory:');let now=Date.UTC(2026,9,25),alarm;
  const sql={exec(q,...args){const rows=db.prepare(q).all(...args);return {toArray:()=>rows};}};
  const ctx={storage:{sql,transactionSync(fn){db.exec('BEGIN');try{const result=fn();db.exec('COMMIT');return result;}catch(e){db.exec('ROLLBACK');throw e;}},getAlarm:async()=>alarm,setAlarm:async v=>{alarm=v;}}};
  const Hub=createDmHub(class {},{clock:()=>now,verify:async(_,id)=>({id,nickname:'test-'+id,avatar:''})});
  const hub=new Hub(ctx,{});
  async function request(path,token,data){const r=await hub.fetch(new Request('https://test.invalid/dm/v1/'+path,{method:data?'POST':'GET',headers:{...(token?{Authorization:'Bearer '+token}:{}),...(data?{'Content-Type':'application/json'}:{})},...(data?{body:JSON.stringify(data)}:{})}));return {status:r.status,body:await r.json()};}
  async function session(id){const r=await request('session',null,{site_cookie:'synthetic-only',expected_user_id:id});assert.equal(r.status,200);return r.body.token;}
  return {db,ctx,Hub,hub,request,session,advance(ms){now+=ms;}};
}

test('confirmations synchronize across sessions, survive reconstruction and remain UID scoped',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(1),other=await f.session(2);
  assert.deepEqual((await f.request('notice-reads',b)).body.keys,[]);
  assert.equal((await f.request('notice-reads',a,{keys:['chat:1:17','dm:42','reply:uuid-123']})).status,200);
  assert.deepEqual(new Set((await f.request('notice-reads',b)).body.keys),new Set(['chat:1:17','dm:42','reply:uuid-123']));
  assert.deepEqual((await f.request('notice-reads',other)).body.keys,[]);
  const cold=new f.Hub(f.ctx,{});const response=await cold.fetch(new Request('https://test.invalid/dm/v1/notice-reads',{headers:{Authorization:'Bearer '+b}}));assert.equal((await response.json()).keys.length,3);
  assert.ok(!JSON.stringify(f.db.prepare('SELECT * FROM notice_reads').all()).includes(a));
});
test('read API rejects identity spoof, arbitrary fields, malformed/oversize batches and expired sessions',async()=>{
  const f=fixture(),a=await f.session(1);
  for(const data of [{keys:['chat:3:1']},{keys:['dm:0']},{keys:['reply:x'],uid:2},{keys:['reply:'+('x'.repeat(101))]},{keys:[]},{keys:Array(61).fill('dm:1')}])assert.equal((await f.request('notice-reads',a,data)).status,400);
  assert.equal((await f.request('notice-reads','a'.repeat(64))).status,401);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM notice_reads').get().n,0);
  f.advance(8*86400000);assert.equal((await f.request('notice-reads',a)).status,401);
});
test('read storage is bounded and expired rows are pruned without touching message history',async()=>{
  const f=fixture(),a=await f.session(1);
  for(let i=1;i<=600;i+=60){assert.equal((await f.request('notice-reads',a,{keys:Array.from({length:60},(_,n)=>'dm:'+(i+n))})).status,200);}
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM notice_reads').get().n,512);
  f.advance(15*86400000);await f.hub.alarm();assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM notice_reads').get().n,0);
});
