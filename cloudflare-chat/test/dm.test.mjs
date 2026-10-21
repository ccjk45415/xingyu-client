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

test('profile sync verifies the current website account without rotating or extending tokens; spoofing and quotas fail closed',async()=>{
  const f=fixture(),token=await f.session(1),second=await f.session(1),before=f.db.prepare('SELECT * FROM dm_sessions ORDER BY token').all();
  const sync=(body,secret=token)=>f.request('profile/sync',{token:secret,method:'POST',body});
  f.profiles.set(1,{nickname:'新名字 ✦',avatar:'https://img.example/new.png'});f.advance(1000);
  const result=await sync({site_cookie:'site-session-1-secret'});assert.equal(result.status,200);assert.equal(result.body.user.nickname,'新名字 ✦');
  assert.deepEqual(f.db.prepare('SELECT * FROM dm_sessions ORDER BY token').all(),before);
  assert.equal((await f.request('me',{token:second})).body.user.avatar,'https://img.example/new.png');
  assert.equal((await sync({site_cookie:'site-session-2-secret'})).status,403);
  for(const extra of [{nickname:'冒用'},{expected_user_id:2},{user:{id:2}}])assert.equal((await sync({site_cookie:'site-session-1-secret',...extra})).status,400);
  assert.equal((await sync({site_cookie:'site-session-1-secret'},'f'.repeat(64))).status,401);
  for(let i=0;i<18;i++)assert.equal((await sync({site_cookie:'site-session-1-secret'})).status,200);
  assert.equal((await sync({site_cookie:'site-session-1-secret'})).status,429);
  const state=JSON.stringify(f.db.prepare('SELECT * FROM dm_users').all());assert.ok(!state.includes('site-session'));assert.ok(!state.includes(token));
});

test('website verification uses fixed HTTPS URL, manual redirects and rejects mismatches, OTP and moderation flags',async()=>{
  const good={id:42,nickname:'真实作者',avatar:'https://images.example/a.png',is_banned:false,is_muted:false};let observed;
  const v=await verifySiteIdentity('secure-session=synthetic',42,async(url,opts)=>{observed={url,opts};return Response.json({code:0,data:good});});
  assert.equal(v.id,42);assert.equal(observed.url,'https://cangku.moe/api/v1/auth/me');assert.equal(observed.opts.redirect,'manual');assert.equal(observed.opts.method,'GET');assert.equal(observed.opts.headers.Cookie,'secure-session=synthetic');assert.ok(observed.opts.signal);
  for(const patch of [{id:43},{should_verify_otp:true},{is_banned:true},{is_muted:true},{is_banned:undefined},{nickname:''}])await assert.rejects(()=>verifySiteIdentity('secure-session=synthetic',42,async()=>Response.json({code:0,data:{...good,...patch}})));
  await assert.rejects(()=>verifySiteIdentity('secure-session=synthetic',42,async()=>new Response(null,{status:302,headers:{Location:'https://attacker.invalid/'}})));
  await assert.rejects(()=>verifySiteIdentity('secret\r\nInjected: value',42,async()=>{throw Error('must not fetch');}));
  await assert.rejects(()=>verifySiteIdentity('secure-session=synthetic',42,async()=>Response.json({code:1,data:good})));
  await assert.rejects(()=>verifySiteIdentity('secure-session=synthetic',42,async()=>new Response('x'.repeat(262145))));
});

test('verified enrollment returns expiring token; no website cookie, raw token or other profile fields persist',async()=>{
  const f=fixture(),token=await f.session(1);assert.match(token,/^[a-f0-9]{64}$/);
  const me=await f.request('me',{token});assert.deepEqual(me.body,{user:{id:1,nickname:'作者 1',avatar:'https://img.example/1.png'}});
  const tables=f.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all();
  const saved=JSON.stringify(tables.map(t=>f.db.prepare('SELECT * FROM '+t.name).all()));assert.ok(!saved.includes('site-session'));assert.ok(!saved.includes(token));assert.ok(!saved.includes('password'));assert.equal(f.calls.length,1);
  assert.equal((await f.request('session',{method:'POST',ip:'192.0.2.9',body:{site_cookie:'site-session-1-secret',expected_user_id:2}})).status,403);
  assert.equal((await f.request('peer?id=2',{token})).body.available,false);
  assert.equal((await f.send(token,2)).status,404);assert.equal((await f.send(token,1)).status,400);
  assert.equal((await f.request('me')).status,401);
  assert.equal((await f.request('logout',{token,method:'POST'})).status,200);assert.equal((await f.request('me',{token})).status,401);
  const another=await f.session(1);f.advance(7*DAY);assert.equal((await f.request('me',{token:another})).status,401);
});

test('third-party isolation, sender spoof rejection, nonce payload binding, and both-party block enforcement',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(2),c=await f.session(3);
  const nonce='synthetic_nonce_0000001',sent=await f.send(a,2,'私密内容',nonce);assert.equal(sent.status,200);assert.equal(sent.body.message.sender_id,1);assert.equal(sent.body.message.recipient_id,2);
  const duplicate=await f.send(a,2,'私密内容',nonce);assert.equal(duplicate.status,200);assert.equal(duplicate.body.message.id,sent.body.message.id);
  assert.equal((await f.send(a,3,'私密内容',nonce)).status,409);assert.equal((await f.send(a,2,'已改写',nonce)).status,409);
  const spoof=await f.request('messages',{token:c,method:'POST',body:{peer_id:2,sender_id:1,text:'冒名',client_id:'synthetic_nonce_0000002'}});assert.equal(spoof.status,400);
  assert.deepEqual((await f.request('messages?peer=1',{token:c})).body.messages,[]);assert.deepEqual((await f.request('messages?peer=2',{token:c})).body.messages,[]);
  assert.deepEqual((await f.request('conversations',{token:c})).body.conversations,[]);
  assert.equal((await f.request('conversations',{token:b})).body.conversations[0].last_message.text,'私密内容');
  assert.equal((await f.request('block',{token:b,method:'POST',body:{peer_id:1,blocked:true}})).status,200);f.advance(4000);
  assert.equal((await f.send(a,2,'被拒收')).status,403);assert.equal((await f.send(b,1,'反向也拒收')).status,403);
  assert.equal((await f.request('blocks',{token:b})).body.users[0].id,1);
  await f.request('block',{token:b,method:'POST',body:{peer_id:1,blocked:false}});assert.equal((await f.send(a,2,'解除后')).status,200);
});

test('read cursor requires received and fetched message; cannot read another pair or outgoing message',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(2),c=await f.session(3),sent=await f.send(a,2),id=sent.body.message.id;
  const read=(token,peer,last)=>f.request('read',{token,method:'POST',body:{peer_id:peer,last_id:last}});
  assert.equal((await read(b,1,id)).status,403);assert.equal((await read(a,2,id)).status,403);assert.equal((await read(c,1,id)).status,403);
  assert.equal((await f.request('conversations',{token:b})).body.conversations[0].unread,1);
  const history=await f.request('messages?peer=1',{token:b});assert.equal(history.body.messages[0].id,id);
  assert.equal((await read(b,1,id)).status,200);assert.equal((await read(b,1,id)).status,200);
  assert.equal((await f.request('conversations',{token:b})).body.conversations[0].unread,0);
  assert.equal((await read(b,3,id)).status,403);assert.equal((await read(b,1,id+1)).status,403);
});

test('backward history and forward polling preserve every message in ascending order with seven-day visibility',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(2);const ids=[];
  for(let i=0;i<35;i++){f.advance(61000);const r=await f.send(a,2,'消息 '+i);assert.equal(r.status,200);ids.push(r.body.message.id);}
  const last=await f.request('messages?peer=1',{token:b});assert.deepEqual(last.body.messages.map(m=>m.id),ids.slice(5));assert.equal(last.body.has_older,true);
  const older=await f.request('messages?peer=1&before='+ids[5],{token:b});assert.deepEqual(older.body.messages.map(m=>m.id),ids.slice(0,5));assert.equal(older.body.has_older,false);
  const first=await f.request('messages?peer=1&after=0',{token:b});assert.deepEqual(first.body.messages.map(m=>m.id),ids.slice(0,30));assert.equal(first.body.has_more,true);
  const next=await f.request('messages?peer=1&after='+first.body.cursor,{token:b});assert.deepEqual(next.body.messages.map(m=>m.id),ids.slice(30));assert.equal(next.body.has_more,false);
  assert.equal((await f.request('messages?peer=1&before=100&after=0',{token:b})).status,400);
  f.advance(7*DAY+1);const fresh=await f.session(2);
  assert.deepEqual((await f.request('messages?peer=1',{token:fresh})).body.messages,[]);
  assert.deepEqual((await f.request('conversations',{token:fresh})).body.conversations,[]);
  await f.hub.alarm();assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM dm_messages').get().n,0);
});

test('message length, global/day/minute/gap limits and account moderation cannot be bypassed by clients',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(2);assert.equal((await f.send(a,2,'😀'.repeat(501))).status,400);assert.equal((await f.send(a,2,'😀'.repeat(500))).status,200);
  assert.equal((await f.send(a,2,'紧接着')).status,429);f.advance(3000);assert.equal((await f.send(a,2,'第二条')).status,200);
  for(let i=2;i<15;i++){f.advance(3000);assert.equal((await f.send(a,2,'分钟消息 '+i)).status,200);}f.advance(3000);assert.equal((await f.send(a,2,'超过分钟')).status,429);
  f.advance(61000);const day=Math.floor(f.now()/DAY)*DAY;f.db.prepare('INSERT INTO dm_counts(key,n,day) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET n=excluded.n').run('m:'+day,2000,day);
  assert.equal((await f.send(a,2,'超过全局')).status,429);f.db.prepare('DELETE FROM dm_counts WHERE key=?').run('m:'+day);
  for(let i=15;i<100;i++){f.advance(61000);assert.equal((await f.send(a,2,'每日消息 '+i)).status,200);}f.advance(61000);assert.equal((await f.send(a,2,'超过每日')).status,429);
  f.db.prepare('UPDATE dm_users SET banned=1 WHERE id=1').run();assert.equal((await f.request('me',{token:a})).status,403);assert.equal((await f.send(a,2,'封禁后')).status,403);
  assert.equal((await f.request('session',{method:'POST',body:{site_cookie:'site-session-1-secret',expected_user_id:1}})).status,403);
  f.db.prepare('UPDATE dm_users SET banned=0,muted=? WHERE id=1').run(f.now()+100000);assert.equal((await f.send(a,2,'禁言后')).status,403);
  assert.equal((await f.request('peer?id=1',{token:b})).status,200);
});

test('verification/IP and verified-account daily quotas, first-contact cap and bounded read budget',async()=>{
  const f=fixture(),a=await f.session(1);
  for(let i=2;i<=12;i++)await f.session(i);
  for(let i=2;i<=11;i++){f.advance(61000);assert.equal((await f.send(a,i,'首次联系 '+i)).status,200);}f.advance(61000);assert.equal((await f.send(a,12,'第十一位')).status,429);
  for(let i=0;i<20;i++)assert.equal((await f.request('session',{method:'POST',ip:'198.51.100.4',body:{site_cookie:'site-session-30-secret',expected_user_id:31}})).status,403);
  const calls=f.calls.length;assert.equal((await f.request('session',{method:'POST',ip:'198.51.100.4',body:{site_cookie:'site-session-30-secret',expected_user_id:30}})).status,429);assert.equal(f.calls.length,calls);
  for(let i=0;i<19;i++)assert.equal((await f.request('session',{method:'POST',ip:'198.51.100.'+(20+i),body:{site_cookie:'site-session-40-secret',expected_user_id:40}})).status,200);
  assert.equal((await f.request('session',{method:'POST',ip:'198.51.100.99',body:{site_cookie:'site-session-40-secret',expected_user_id:40}})).status,200);
  assert.equal((await f.request('session',{method:'POST',ip:'198.51.100.100',body:{site_cookie:'site-session-40-secret',expected_user_id:40}})).status,429);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM dm_sessions WHERE uid=40').get().n,3);
  f.advance(61000);for(let i=0;i<60;i++)assert.equal((await f.request('me',{token:a})).status,200);assert.equal((await f.request('me',{token:a})).status,429);
});

test('conversation pagination never discloses unrelated pairs, enrollment expiry and cleanup are bounded',async()=>{
  const f=fixture(),a=await f.session(1);const day=Math.floor(f.now()/DAY)*DAY;
  // Seed verified identities and messages to exercise pagination beyond the 10 new contacts/day cap.
  for(let i=2;i<=35;i++){f.db.prepare('INSERT INTO dm_users(id,nickname,avatar,enrolled_until) VALUES(?,?,?,?)').run(i,'用户 '+i,'',f.now()+7*DAY);const r=f.db.prepare('INSERT INTO dm_messages(sender,recipient,text,client_id,created) VALUES(?,?,?,?,?) RETURNING id').get(i,1,'消息 '+i,'seed_nonce_'+String(i).padStart(8,'0'),f.now());f.db.prepare('INSERT INTO dm_pairs(a,b,last_id) VALUES(?,?,?)').run(1,i,r.id);}
  const page=await f.request('conversations',{token:a});assert.equal(page.body.conversations.length,30);assert.equal(page.body.has_more,true);
  const before=page.body.conversations.at(-1).last_message.id,next=await f.request('conversations?before='+before,{token:a});assert.equal(next.body.conversations.length,4);assert.equal(next.body.has_more,false);
  const ids=[...page.body.conversations,...next.body.conversations].map(c=>c.peer.id);assert.equal(new Set(ids).size,34);
  f.db.prepare('UPDATE dm_users SET enrolled_until=? WHERE id=2').run(f.now());assert.equal((await f.request('peer?id=2',{token:a})).body.available,false);assert.equal((await f.send(a,2,'未续期')).status,404);
  const oversized=await f.hub.fetch(new Request('https://test.invalid/dm/v1/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({site_cookie:'x'.repeat(9000),expected_user_id:1})}));assert.equal(oversized.status,413);
});
