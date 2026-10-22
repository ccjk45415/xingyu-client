import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createDmHub,verifySiteIdentity,DM_LIMITS} from '../src/dm-core.mjs';

const DAY=86400000,START=Date.UTC(2026,9,20,9);
function fixture(){
  const db=new DatabaseSync(':memory:');let now=START,alarm=null;const calls=[],profiles=new Map();
  const sql={exec(q,...args){const rows=db.prepare(q).all(...args);return {toArray:()=>rows};}};
  const ctx={storage:{sql,transactionSync(fn){db.exec('BEGIN');try{const value=fn();db.exec('COMMIT');return value;}catch(e){db.exec('ROLLBACK');throw e;}},async getAlarm(){return alarm;},async setAlarm(t){alarm=t;}}};
  const verify=(cookie,expected)=>verifySiteIdentity(cookie,expected,async(url,opts)=>{calls.push({url,opts});const id=Number(/^site-session-(\d+)-secret$/.exec(cookie)?.[1]);return Response.json({code:0,data:{id,nickname:'作者 '+id,avatar:'https://img.example/'+id+'.png',is_banned:false,is_muted:false,...profiles.get(id)}});});
  const Hub=createDmHub(class {},{verify,clock:()=>now}),hub=new Hub(ctx,{});
  async function request(path,{token,method='GET',body,ip='192.0.2.1'}={}){const response=await hub.fetch(new Request('https://test.invalid/dm/v1/'+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),'CF-Connecting-IP':ip,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})}));return {status:response.status,body:await response.json()};}
  async function session(id,ip='192.0.2.'+id){const r=await request('session',{method:'POST',ip,body:{site_cookie:'site-session-'+id+'-secret',expected_user_id:id}});assert.equal(r.status,200,JSON.stringify(r.body));return r.body.token;}
  async function send(token,peer,text='内容',nonce=crypto.randomUUID().replaceAll('-','')){return request('messages',{token,method:'POST',body:{peer_id:peer,text,client_id:nonce}});}
  return {db,hub,request,session,send,calls,profiles,advance:ms=>now+=ms,now:()=>now};
}


test('independent follows survive session/history expiry and preserve verified profiles without storing website secrets',async()=>{
 const f=fixture(),a=await f.session(1);await f.session(2);
 const set=(peer,following,token=a)=>f.request('follows',{token,method:'POST',body:{peer_id:peer,following}});
 assert.equal((await set(2,true)).status,200);f.advance(20*DAY);await f.hub.alarm();
 assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM social_follows').get().n,1);
 assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM dm_users').get().n,2);
 assert.equal((await set(2,false)).status,401);
 const fresh=await f.session(1),r=await f.request('follows/ids',{token:fresh});assert.deepEqual(r.body.ids,[2]);
 const state=JSON.stringify(f.db.prepare('SELECT * FROM social_follows').all());assert.ok(!state.includes('site-session'));assert.ok(!state.includes(fresh));
});
test('follow limit and mutation quota reject atomically while idempotent retries still succeed',async()=>{
 const f=fixture(),a=await f.session(1);
 for(let i=2;i<=501;i++)f.db.prepare('INSERT INTO social_follows(owner,peer,created) VALUES(?,?,?)').run(1,i,f.now());
 const set=(peer,following)=>f.request('follows',{token:a,method:'POST',body:{peer_id:peer,following}});
 assert.equal((await set(502,true)).status,429);assert.equal((await set(2,true)).status,200);
 assert.equal((await set(2,false)).status,200);assert.equal((await set(502,true)).status,200);
 const day=Math.floor(f.now()/DAY)*DAY;f.db.prepare('INSERT INTO dm_counts(key,n,day) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET n=excluded.n').run('follow:1:'+day,500,day);
 assert.equal((await set(3,false)).status,429);assert.equal((await set(3,true)).status,200);
 assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM social_follows WHERE owner=1').get().n,500);
});
