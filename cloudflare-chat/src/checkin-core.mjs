import {initCheckinEvents,recordCheckinEvent,checkinEvents,checkinDay,readCheckinEvents} from './checkin-events.mjs';
// Opt-in credential vault. It is deliberately separate from chat authentication.
const enc = new TextEncoder(), DAY = 86400000, LEASE = 7 * DAY;
const json = (data, status=200) => Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const fail = (message,status=400) => { throw Object.assign(new Error(message),{status}); };
const hex = bytes => Array.from(bytes,x=>x.toString(16).padStart(2,'0')).join('');
const random = () => hex(crypto.getRandomValues(new Uint8Array(32)));
const hash = async value => hex(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(value))));
const iso = time => new Date(time).toISOString();
// Run just after the website's daily 08:00 Beijing reset, not at 10:00.
export const nextCheckin = now => { const first=Math.floor(now/DAY)*DAY+60000;return first>now?first:first+DAY; };
const retryDelay=attempt=>[60000,300000,900000,1800000,3600000,7200000][Math.min(attempt,5)];
function cookieOK(value) { if(typeof value!=='string'||!value.trim()||enc.encode(value).length>7000||/[\x00-\x1f\x7f]/.test(value))fail('登录会话无效',401); return value; }
async function bytes(stream,max) {
  const reader=stream?.getReader(); if(!reader)fail('响应为空',502);
  const chunks=[];let size=0;
  for(;;){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>max){await reader.cancel();fail('响应过大',413);}chunks.push(part.value);}
  const result=new Uint8Array(size);let at=0;for(const chunk of chunks){result.set(chunk,at);at+=chunk.length;}return result;
}
async function body(req) {
  if(!req.headers.get('Content-Type')?.startsWith('application/json'))fail('需要JSON');
  try { const result=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(await bytes(req.body,8192))); if(!result||typeof result!=='object'||Array.isArray(result))fail('请求无效'); return result; }
  catch(error){if(error.status)throw error;fail('请求无效');}
}
function exact(value,keys){if(Object.keys(value).length!==keys.length||keys.some(key=>!(key in value)))fail('请求字段无效');}
async function encryptionKey(secret) {
  if(typeof secret!=='string'||!/^[a-f0-9]{64}$/.test(secret))fail('云端签到尚未配置',503);
  return crypto.subtle.importKey('raw',Uint8Array.from(secret.match(/../g),x=>parseInt(x,16)),'AES-GCM',false,['encrypt','decrypt']);
}
export async function sealCookie(cookie,uid,secret) {
  const key=await encryptionKey(secret),iv=crypto.getRandomValues(new Uint8Array(12));
  const cipher=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode('xingyu-checkin-v1:'+uid)},key,enc.encode(cookieOK(cookie))));
  return JSON.stringify({iv:Array.from(iv),cipher:Array.from(cipher)});
}
export async function openCookie(raw,uid,secret) {
  const value=JSON.parse(raw), key=await encryptionKey(secret);
  return cookieOK(new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:new Uint8Array(value.iv),additionalData:enc.encode('xingyu-checkin-v1:'+uid)},key,new Uint8Array(value.cipher))));
}

/** Fixed, verified HTTPS origin only; redirects and unbounded response bodies are rejected. */
export class CheckinSite {
  constructor(cookie,fetcher=fetch){cookieOK(cookie);this.fetcher=fetcher.bind(globalThis);this.jar=new Map(cookie.split(';').map(part=>{const at=part.indexOf('=');return [part.slice(0,at).trim(),part.slice(at+1).trim()];}).filter(([name])=>name));}
  cookie(){return [...this.jar].map(([name,value])=>`${name}=${value}`).join('; ');}
  async request(path,post=false){
    this.phase=path==='auth/me'?'account':'signin';
    const headers={Cookie:this.cookie(),Accept:'application/json',Origin:'https://cangku.moe',Referer:'https://cangku.moe/','X-Requested-With':'XMLHttpRequest','User-Agent':'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/125.0.0.0 Mobile Safari/537.36'};
    if(this.jar.has('XSRF-TOKEN')){try{headers['X-XSRF-TOKEN']=decodeURIComponent(this.jar.get('XSRF-TOKEN'));}catch{fail('登录会话无效',401);}}
    if(post)headers['Content-Type']='application/json';
    const response=await this.fetcher('https://cangku.moe/api/v1/'+path,{method:post?'POST':'GET',redirect:'manual',signal:AbortSignal.timeout(15000),headers,...(post?{body:'{}'}:{})});
    this.httpStatus=response.status;
    if(response.status===401){await response.body?.cancel();fail('请重新授权签到',401);}
    if(response.status!==200){await response.body?.cancel();fail('签到网站暂不可用',502);}
    const cookies=response.headers.getSetCookie?.() || (response.headers.get('Set-Cookie')||'').split(/,(?=\s*[^;,=\s]+=)/);
    for(const raw of cookies){
      const parts=raw.split(';'),at=parts[0].indexOf('=');if(at<1)continue;
      const name=parts[0].slice(0,at).trim(),value=parts[0].slice(at+1).trim();
      const domain=parts.find(p=>/^\s*domain=/i.test(p))?.split('=')[1]?.trim().toLowerCase();
      if(domain&&!['cangku.moe','.cangku.moe'].includes(domain))continue;
      if(parts.some(p=>/^\s*max-age=0\s*$/i.test(p))||parts.some(p=>/^\s*expires=/i.test(p)&&Date.parse(p.slice(p.indexOf('=')+1))<Date.now()))this.jar.delete(name);
      else this.jar.set(name,value);
    }
    let result;try{result=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(await bytes(response.body,262144)));}catch(error){if(error.status)throw error;fail('签到响应无效',502);}
    if(result.code!==0)fail('签到尚未确认',502);
    return result.data;
  }
  async account(uid){
    const user=await this.request('auth/me');
    if(!user||user.id!==uid||user.is_banned!==false||user.is_muted!==false||user.should_verify_otp||![true,false,0,1].includes(user.is_signed))fail('身份不匹配或登录失效',401);
    return user;
  }
  async run(uid){
    let user=await this.account(uid), reward={},performed=false;
    if(user.is_signed!==true&&user.is_signed!==1){
      try{reward=await this.request('user/signin',true)||{};performed=true;}catch{/* Re-query rather than treating an error as already signed. */}
      user=await this.account(uid);
    }
    if(user.is_signed!==true&&user.is_signed!==1)fail('签到尚未确认',502);
    return {status:'signed',performed,...Object.fromEntries(['continuous_signin','exp','point'].filter(key=>Number.isFinite(reward[key])).map(key=>[key,reward[key]]))};
  }
}

export function createCheckinHub(Base,{clock=()=>Date.now(),fetcher=fetch}={}){return class extends Base{
  constructor(ctx,env){
    super(ctx,env);this.ctx=ctx;this.env=env;this.sql=ctx.storage.sql;this.locks=new Map();
    this.sql.exec('CREATE TABLE IF NOT EXISTS checkin_users(uid INTEGER PRIMARY KEY,cipher TEXT,expires INTEGER NOT NULL DEFAULT 0,next INTEGER NOT NULL DEFAULT 0,attempt_day INTEGER NOT NULL DEFAULT 0,attempts INTEGER NOT NULL DEFAULT 0,history TEXT NOT NULL DEFAULT \'[]\')');
    this.sql.exec('CREATE TABLE IF NOT EXISTS checkin_grants(token TEXT PRIMARY KEY,uid INTEGER NOT NULL,expires INTEGER NOT NULL)');
    this.sql.exec('CREATE INDEX IF NOT EXISTS checkin_grants_uid ON checkin_grants(uid)');
    this.sql.exec('CREATE TABLE IF NOT EXISTS checkin_limits(key TEXT PRIMARY KEY,day INTEGER NOT NULL,n INTEGER NOT NULL)');
    initCheckinEvents(this.sql);
    this.sql.exec('CREATE TABLE IF NOT EXISTS checkin_meta(key TEXT PRIMARY KEY,value INTEGER NOT NULL)');
    if(!this.rows('PRAGMA table_info(checkin_users)').some(c=>c.name==='previous_next'))this.sql.exec('ALTER TABLE checkin_users ADD COLUMN previous_next INTEGER NOT NULL DEFAULT 0');
    if(!this.first("SELECT value FROM checkin_meta WHERE key='schedule_v2'")){
      this.sql.exec('UPDATE checkin_users SET previous_next=next,next=MIN(next,?+(uid%120)*1000),attempt_day=0,attempts=0 WHERE cipher IS NOT NULL AND expires>?',clock()+60000,clock());
      this.sql.exec("INSERT INTO checkin_meta(key,value) VALUES('schedule_v2',?)",clock());
      this.needsSchedule=true;
    }
  }
  rows(q,...args){return this.sql.exec(q,...args).toArray();}
  first(q,...args){return this.rows(q,...args)[0];}
  async lock(uid,fn){const previous=this.locks.get(uid)||Promise.resolve();const current=previous.catch(()=>{}).then(fn);this.locks.set(uid,current);try{return await current;}finally{if(this.locks.get(uid)===current)this.locks.delete(uid);}}
  budget(key,max){
    const day=Math.floor(clock()/DAY),row=this.first('SELECT * FROM checkin_limits WHERE key=?',key);
    if(row?.day===day&&row.n>=max)fail('今日尝试次数过多',429);
    this.sql.exec('INSERT INTO checkin_limits(key,day,n) VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET day=excluded.day,n=CASE WHEN checkin_limits.day=excluded.day THEN checkin_limits.n+1 ELSE 1 END',key,day);
  }
  async grant(req){
    const auth=req.headers.get('Authorization')||'';if(!/^Bearer [a-f0-9]{64}$/.test(auth))fail('请重新授权签到',401);
    const grant=this.first('SELECT * FROM checkin_grants WHERE token=?',await hash(auth.slice(7)));
    if(!grant||grant.expires<=clock())fail('签到授权已过期',401);return grant;
  }
  status(uid){const row=this.first('SELECT * FROM checkin_users WHERE uid=?',uid);return {enabled:!!row?.cipher&&row.expires>clock(),expires_at:row?.expires?iso(row.expires):null,next_at:row?.cipher&&row.next?iso(row.next):null,history:row?JSON.parse(row.history).map(item=>item.status==='already_signed'?{...item,status:'signed',performed:false}:item):[]};}
  async schedule(){return this.lock('alarm',async()=>{
    const row=this.first('SELECT MIN(MIN(next,expires)) AS due FROM checkin_users WHERE cipher IS NOT NULL');
    if(row?.due)await this.ctx.storage.setAlarm(Math.max(clock()+1000,row.due));else await this.ctx.storage.deleteAlarm();
  });}
  async eventOwner(req){
    try{return (await this.grant(req)).uid;}catch(error){if(error.status!==401)throw error;}
    const auth=req.headers.get('Authorization')||'';
    if(!/^Bearer [a-f0-9]{64}$/.test(auth)||!this.env.DM)fail('请先认证仓库账号',401);
    const response=await this.env.DM.get(this.env.DM.idFromName('xingyu-dm-v1')).fetch(new Request('https://internal/internal/identity',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token_hash:await hash(auth.slice(7))})}));
    if(response.status!==200)fail('消息身份已过期',401);
    const value=await response.json(),uid=value.user?.id;
    if(!Number.isSafeInteger(uid)||uid<1)fail('消息身份无效',401);return uid;
  }
  async fetch(req){try{
    if(this.needsSchedule){this.needsSchedule=false;await this.schedule();}
    const url=new URL(req.url),path=url.pathname;
    if(path==='/checkin/v1/admin/status'&&req.method==='GET'){
      const secret=this.env.ANNOUNCEMENTS_ADMIN_KEY,auth=req.headers.get('Authorization')||'';
      if(typeof secret!=='string'||!/^[a-f0-9]{64}$/.test(secret)||!/^Bearer [a-f0-9]{64}$/.test(auth)||await hash(auth.slice(7))!==await hash(secret))fail('无诊断权限',401);
      const uid=Number(url.searchParams.get('uid'));if(!Number.isSafeInteger(uid)||uid<1)fail('账号无效');
      const row=this.first('SELECT uid,next,previous_next,expires,attempt_day,attempts,history FROM checkin_users WHERE uid=?',uid);
      return json({uid,found:!!row,...(row?{...this.status(uid),previous_next_at:row.previous_next?iso(row.previous_next):null,attempt_day:row.attempt_day,attempts:row.attempts}:{}),schedule_version:2});
    }
    if(path==='/checkin/v1/events'||path==='/checkin/v1/events/read'){
      const uid=await this.eventOwner(req);
      if(path.endsWith('/read')){if(req.method!=='POST')fail('接口不存在',404);const data=await body(req);exact(data,['keys']);return await this.lock(uid,async()=>{this.budget('event-reads:'+uid,200);this.ctx.storage.transactionSync(()=>readCheckinEvents(this,uid,data.keys,clock()));return json({ok:true});});}
      if(req.method==='GET')return json({events:checkinEvents(this,uid,clock())});
      if(req.method!=='POST')fail('接口不存在',404);
      const data=await body(req);exact(data,['events']);
      if(!Array.isArray(data.events)||data.events.length<1||data.events.length>10)fail('签到记录无效');
      return await this.lock(uid,async()=>{this.budget('events:'+uid,100);const events=this.ctx.storage.transactionSync(()=>data.events.map(e=>recordCheckinEvent(this,uid,e,clock())));return json({events});});
    }
    if(path==='/checkin/v1/session'&&req.method==='POST'){
      await encryptionKey(this.env.CHECKIN_ENCRYPTION_KEY);
      const data=await body(req);exact(data,['site_cookie','expected_user_id']);
      const uid=data.expected_user_id;if(!Number.isSafeInteger(uid)||uid<1)fail('账号无效');cookieOK(data.site_cookie);
      const ip=await hash(req.headers.get('CF-Connecting-IP')||'local');
      this.ctx.storage.transactionSync(()=>{this.budget('ip:'+ip,20);this.budget('enroll',1000);this.budget('uid:'+uid,20);});
      await new CheckinSite(data.site_cookie,fetcher).account(uid);
      const token=random(),digest=await hash(token),expires=clock()+LEASE;
      return await this.lock(uid,async()=>{
        this.sql.exec('DELETE FROM checkin_grants WHERE expires<=?',clock());
        this.sql.exec('DELETE FROM checkin_limits WHERE day<?',Math.floor(clock()/DAY)-1);
        if(this.first('SELECT COUNT(*) AS n FROM checkin_users').n>=10000&&!this.first('SELECT uid FROM checkin_users WHERE uid=?',uid))fail('签到服务繁忙',503);
        if(this.first('SELECT COUNT(*) AS n FROM checkin_grants WHERE uid=?',uid).n>=5)fail('此账号授权设备过多，请在7天后重试',429);
        this.sql.exec('INSERT OR IGNORE INTO checkin_users(uid) VALUES(?)',uid);
        this.sql.exec('INSERT INTO checkin_grants(token,uid,expires) VALUES(?,?,?)',digest,uid,expires);
        return json({token,expires_at:iso(expires),user_id:uid});
      });
    }
    const grant=await this.grant(req),uid=grant.uid;
    if(path==='/checkin/v1/status'&&req.method==='GET')return json(this.status(uid));
    if(req.method!=='POST'||!['/checkin/v1/enable','/checkin/v1/disable'].includes(path))fail('接口不存在',404);
    const data=await body(req);
    return await this.lock(uid,async()=>{
      if(grant.expires<=clock())fail('签到授权已过期',401);
      if(path.endsWith('/disable')){
        exact(data,[]);this.sql.exec('UPDATE checkin_users SET cipher=NULL,expires=0,next=0 WHERE uid=?',uid);
      }else{
        exact(data,['site_cookie','consent']);if(data.consent!==true)fail('需要独立同意云端签到');
        this.budget('enable:'+uid,10);
        const site=new CheckinSite(data.site_cookie,fetcher);await site.account(uid);
        const cipher=await sealCookie(site.cookie(),uid,this.env.CHECKIN_ENCRYPTION_KEY);
        this.sql.exec('UPDATE checkin_users SET cipher=?,expires=?,next=? WHERE uid=?',cipher,Math.min(clock()+LEASE,grant.expires),clock()+60000,uid);
      }
      await this.schedule();return json(this.status(uid));
    });
  }catch(error){return json({error:error.status?error.message:'签到服务暂不可用'},error.status||503);}}
  async run(uid){return this.lock(uid,async()=>{
    let row=this.first('SELECT * FROM checkin_users WHERE uid=?',uid);if(!row?.cipher)return;
    const now=clock(),day=checkinDay(now);
    if(row.next>now&&row.expires>now)return;
    let status, reward={},next=nextCheckin(now),cipher=row.cipher;
    if(row.expires<=now){status='expired';cipher=null;}
    else {
      const attempts=row.attempt_day===day?row.attempts:0;
      if(attempts>=12){this.sql.exec('UPDATE checkin_users SET next=? WHERE uid=?',next,uid);return;}
      try { this.budget('execution',10000); }
      catch { this.sql.exec('UPDATE checkin_users SET next=? WHERE uid=?',next,uid); return; }
      this.sql.exec('UPDATE checkin_users SET attempt_day=?,attempts=? WHERE uid=?',day,attempts+1,uid);
      let site;
      try{
        const cookie=await openCookie(row.cipher,uid,this.env.CHECKIN_ENCRYPTION_KEY);site=new CheckinSite(cookie,fetcher);
        reward=await site.run(uid);status='signed';if(reward.performed)recordCheckinEvent(this,uid,{time:now,client:'cloud',method:'cloud'},now,{cloud:true});cipher=await sealCookie(site.cookie(),uid,this.env.CHECKIN_ENCRYPTION_KEY);
      }catch(error){reward={phase:site?.phase||'session',http_status:site?.httpStatus||0};status=error.status===401?'login_required':'network';if(status==='login_required')cipher=null;else next=Math.min(now+retryDelay(attempts),nextCheckin(now));}
    }
    const history=[{...reward,time:iso(now),status},...JSON.parse(row.history)].slice(0,10);
    this.sql.exec('UPDATE checkin_users SET cipher=?,next=?,history=? WHERE uid=?',cipher,cipher?next:0,JSON.stringify(history),uid);
  });}
  async alarm(){
    this.needsSchedule=false;
    const due=this.rows('SELECT uid FROM checkin_users WHERE cipher IS NOT NULL AND (next<=? OR expires<=?) ORDER BY next LIMIT 10',clock(),clock());
    for(const row of due){try{await this.run(row.uid);}catch{this.sql.exec('UPDATE checkin_users SET next=? WHERE uid=? AND cipher IS NOT NULL',clock()+300000,row.uid);}}
    this.sql.exec('DELETE FROM checkin_grants WHERE expires<=?',clock());
    await this.schedule();
  }
};}
