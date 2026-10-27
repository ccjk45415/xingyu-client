import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {CheckinSite,createCheckinHub,openCookie,sealCookie,nextCheckin} from '../src/checkin-core.mjs';
const SECRET='a'.repeat(64),COOKIE='session=synthetic-local-only; XSRF-TOKEN=abc%3D';
const user={id:17,nickname:'fixture',is_banned:false,is_muted:false,is_signed:false};
test('website fetch preserves the Worker global receiver',async()=>{
  async function receiverSensitiveFetch(){assert.equal(this,globalThis);return Response.json({code:0,data:user});}
  assert.equal((await new CheckinSite(COOKIE,receiverSensitiveFetch).account(17)).id,17);
});
function fixture(){
  let now=Date.parse('2026-10-24T01:00:00Z'),signed=false,fail=false,invalid=false,posts=0,alarm=null;
  const db=new DatabaseSync(':memory:'),sql={exec(q,...args){const result=db.prepare(q).all(...args);return {toArray:()=>result};}};
  const fetcher=async(url,options)=>{
    assert.ok(['https://cangku.moe/api/v1/auth/me','https://cangku.moe/api/v1/user/signin'].includes(url));
    assert.equal(options.redirect,'manual');assert.match(options.headers.Cookie,/session=/);
    if(invalid)return new Response(null,{status:401});
    if(fail)return new Response('network',{status:503});
    if(options.method==='POST'){posts++;signed=true;assert.equal(options.headers['X-XSRF-TOKEN'],'abc=');}
    return Response.json({code:0,data:options.method==='POST'?{point:2,exp:1,continuous_signin:3}:{...user,is_signed:signed}});
  };
  const ctx={storage:{sql,setAlarm:async n=>{alarm=n;},deleteAlarm:async()=>{alarm=null;},transactionSync(fn){db.exec('BEGIN');try{const value=fn();db.exec('COMMIT');return value;}catch(error){db.exec('ROLLBACK');throw error;}}}};
  const Hub=createCheckinHub(class {},{clock:()=>now,fetcher}),env={CHECKIN_ENCRYPTION_KEY:SECRET},hub=new Hub(ctx,env);
  const request=async(path,data,token)=>hub.fetch(new Request('https://test.invalid/checkin/v1/'+path,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},...(data?{body:JSON.stringify(data)}:{})}));
  const enroll=async()=>{const result=await request('session',{site_cookie:COOKIE,expected_user_id:17});assert.equal(result.status,200);return (await result.json()).token;};
  return {db,ctx,hub,Hub,env,fetcher,request,enroll,set now(v){now=v;},get now(){return now;},get alarm(){return alarm;},get posts(){return posts;},set fail(v){fail=v;},set invalid(v){invalid=v;},set signed(v){signed=v;}};
}
test('vault binds ciphertext to UID and key, never stores plaintext',async()=>{
  const encrypted=await sealCookie(COOKIE,17,SECRET);assert.ok(!encrypted.includes('synthetic'));
  assert.equal(await openCookie(encrypted,17,SECRET),COOKIE);
  await assert.rejects(openCookie(encrypted,18,SECRET));await assert.rejects(openCookie(encrypted,17,'b'.repeat(64)));
});
test('enrollment alone never enables or performs a check-in; consent required; unrelated bearer rejected',async()=>{
  const f=fixture(),token=await f.enroll();
  assert.equal((await (await f.request('status',null,token)).json()).enabled,false);assert.equal(f.posts,0);assert.equal(f.alarm,null);
  assert.equal((await f.request('enable',{site_cookie:COOKIE,consent:false},token)).status,400);
  assert.equal((await f.request('enable',{site_cookie:COOKIE,consent:true},'b'.repeat(64))).status,401);
  assert.equal((await f.request('session',{site_cookie:COOKIE,expected_user_id:18})).status,401);
});
test('scheduled check-in survives cold reconstruction, is idempotent and disable deletes credentials',async()=>{
  const f=fixture(),token=await f.enroll();
  assert.equal((await f.request('enable',{site_cookie:COOKIE,consent:true},token)).status,200);
  assert.equal(f.alarm,f.now+60000);assert.equal(f.posts,0);
  const cold=new f.Hub(f.ctx,f.env);f.now+=61000;await Promise.all([cold.alarm(),cold.alarm()]);
  assert.equal(f.posts,1);let status=await (await f.request('status',null,token)).json();assert.equal(status.history[0].status,'signed');assert.equal(status.history.length,1);
  assert.ok(!JSON.stringify(f.db.prepare('SELECT * FROM checkin_users').all()).includes('synthetic'));
  await f.request('disable',{},token);assert.equal(f.db.prepare('SELECT cipher FROM checkin_users').get().cipher,null);assert.equal(f.alarm,null);
  await cold.alarm();assert.equal(f.posts,1);
});
test('network failures never claim success, retry bounded to 12/reset-day; expiry removes vault',async()=>{
  const f=fixture(),token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);f.fail=true;
  for(let i=0;i<12;i++){f.now=f.alarm+1;await f.hub.alarm();}
  const row=f.db.prepare('SELECT * FROM checkin_users').get();assert.equal(row.attempts,12);assert.equal(JSON.parse(row.history).every(r=>r.status==='network'),true);assert.equal(f.posts,0);
  f.now+=8*86400000;await f.hub.alarm();assert.equal(f.db.prepare('SELECT cipher FROM checkin_users').get().cipher,null);assert.equal(f.alarm,null);assert.equal((await f.request('status',null,token)).status,401);
});
test('invalid website login clears vault rather than retrying credentials forever',async()=>{
  const f=fixture(),token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);f.invalid=true;f.now=f.alarm+1;await f.hub.alarm();
  assert.equal(f.db.prepare('SELECT cipher FROM checkin_users').get().cipher,null);assert.equal((await (await f.request('status',null,token)).json()).history[0].status,'login_required');
});
test('disable queued during an in-flight run cannot resurrect a deleted vault',async()=>{
  const f=fixture(),token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);f.now+=61000;
  await Promise.all([f.hub.alarm(),f.request('disable',{},token)]);assert.equal(f.db.prepare('SELECT cipher FROM checkin_users').get().cipher,null);assert.equal(f.alarm,null);
});
test('a failed signin POST is reconciled and is never assumed to mean already signed',async()=>{
  const site=new CheckinSite(COOKIE,async(url,options)=>options.method==='POST'?new Response(null,{status:500}):Response.json({code:0,data:user}));
  await assert.rejects(site.run(17));
  assert.equal(new Date(nextCheckin(Date.parse('2026-10-24T01:00:00Z'))).toISOString(),'2026-10-25T00:01:00.000Z');
});


test('daily schedule follows 08:00 Beijing reset instead of 10:00 or midnight',()=>{
  for(const [now,expected] of [
    ['2026-10-26T23:59:00Z','2026-10-27T00:01:00.000Z'],
    ['2026-10-27T00:00:00Z','2026-10-27T00:01:00.000Z'],
    ['2026-10-27T00:40:00Z','2026-10-28T00:01:00.000Z'],
    ['2026-10-27T16:01:00Z','2026-10-28T00:01:00.000Z']])assert.equal(new Date(nextCheckin(Date.parse(now))).toISOString(),expected);
});
test('legacy ten-o-clock schedules migrate once, preserving previous time for diagnosis',async()=>{
  const f=fixture(),token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);
  const previous=f.now+4*3600000;f.db.prepare('UPDATE checkin_users SET next=?').run(previous);f.db.prepare("DELETE FROM checkin_meta WHERE key='schedule_v2'").run();
  new f.Hub(f.ctx,f.env);
  let row=f.db.prepare('SELECT next,previous_next FROM checkin_users').get();assert.equal(row.previous_next,previous);assert.ok(row.next<=f.now+180000);
  new f.Hub(f.ctx,f.env);assert.equal(f.db.prepare('SELECT next FROM checkin_users').get().next,row.next);
});
test('early retry recovers before 08:40 and already signed is not attributed to cloud',async()=>{
  const f=fixture();f.now=Date.parse('2026-10-27T00:00:00Z');const token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);
  f.fail=true;f.now=f.alarm+1;await f.hub.alarm();assert.ok(f.alarm-f.now<=60000);
  f.fail=false;f.now=f.alarm+1;await f.hub.alarm();assert.equal(f.posts,1);assert.ok(f.now<Date.parse('2026-10-27T00:40:00Z'));
  const events=await (await f.request('events',null,token)).json();assert.equal(events.events.length,1);assert.equal(events.events[0].client,'cloud');
  f.now=Date.parse('2026-10-28T00:01:01Z');f.signed=true;await f.hub.alarm();
  const status=await (await f.request('status',null,token)).json();assert.equal(status.history[0].status,'signed');assert.equal(status.history[0].performed,false);assert.equal((await (await f.request('events',null,token)).json()).events.length,1);
});
test('events are uid-scoped, deduplicated per reset day and reject fake cloud sources',async()=>{
  const f=fixture(),token=await f.enroll();const event={time:new Date(f.now).toISOString(),client:'android',method:'manual'};
  assert.equal((await f.request('events',{events:[event]},token)).status,200);
  assert.equal((await f.request('events',{events:[{...event,client:'windows',method:'background'}]},token)).status,200);
  let events=(await (await f.request('events',null,token)).json()).events;assert.equal(events.length,1);assert.equal(events[0].client,'android');
  assert.equal((await f.request('events',{events:[{...event,client:'cloud',method:'cloud'}]},token)).status,400);
  assert.equal((await f.request('events',{events:[{...event,time:new Date(f.now+3600000).toISOString()}]},token)).status,400);
  assert.equal((await f.request('events',null,'b'.repeat(64))).status,401);
});
test('admin inspection requires management credential and returns no encrypted session or grant',async()=>{
  const f=fixture();f.env.ANNOUNCEMENTS_ADMIN_KEY='c'.repeat(64);const token=await f.enroll();
  assert.equal((await f.request('admin/status?uid=17',null,token)).status,401);
  const response=await f.request('admin/status?uid=17',null,'c'.repeat(64));assert.equal(response.status,200);
  const value=await response.json();assert.equal(value.uid,17);assert.equal(value.found,true);assert.ok(!JSON.stringify(value).includes('cipher'));assert.ok(!JSON.stringify(value).includes(token));
});
test('temporary HTTP 419 is retried without deleting cloud authorization',async()=>{
  const f=fixture(),token=await f.enroll();await f.request('enable',{site_cookie:COOKIE,consent:true},token);
  const fetcher=async()=>new Response(null,{status:419});const hub=new (createCheckinHub(class {},{clock:()=>f.now,fetcher}))(f.ctx,f.env);
  f.now=f.alarm+1;await hub.alarm();assert.notEqual(f.db.prepare('SELECT cipher FROM checkin_users').get().cipher,null);assert.ok(f.alarm-f.now<=60000);
});


test('success reads synchronize using a cloud grant without requiring chat enrollment',async()=>{
  const f=fixture(),token=await f.enroll();const event={time:new Date(f.now).toISOString(),client:'windows',method:'background'};
  await f.request('events',{events:[event]},token);let list=(await (await f.request('events',null,token)).json()).events;
  assert.equal(list[0].read,false);await f.request('events/read',{keys:[list[0].key]},token);
  list=(await (await f.request('events',null,token)).json()).events;assert.equal(list[0].read,true);
  assert.equal((await f.request('events/read',{keys:['dm:7']},token)).status,400);
});
