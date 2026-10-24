import {DurableObject} from 'cloudflare:workers';
import {LIMITS,roomOK,nickname,text,nonceOK,dayStart,limitReason} from './policy.mjs';
export {VerifiedChatHub} from './verified-chat.mjs';
export {AiDraftHub} from './ai.js';
export {DmHub} from './dm.js';
export {AnnouncementHub} from './announcements.js';
export {CheckinHub} from './checkin.js';
const encoder=new TextEncoder();
const json=(o,status=200)=>Response.json(o,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(s))),x=>x.toString(16).padStart(2,'0')).join('');
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
function fail(message,status=400){const e=new Error(message);e.status=status;throw e;}
async function body(req){
  if(!req.headers.get('content-type')?.startsWith('application/json'))fail('请求应为JSON');
  const reader=req.body?.getReader();if(!reader)fail('请求内容为空');let size=0,chunks=[];
  for(;;){const r=await reader.read();if(r.done)break;size+=r.value.length;if(size>8192){await reader.cancel();fail('请求过大',413);}chunks.push(r.value);}
  const bytes=new Uint8Array(size);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}
  try{const b=JSON.parse(new TextDecoder().decode(bytes));if(!b||typeof b!=='object'||Array.isArray(b))fail('请求格式错误');return b;}catch(e){fail(e.status?e.message:'JSON格式错误');}
}
export default {
  async fetch(req,env){
    const url=new URL(req.url);
    if(url.pathname.startsWith('/checkin/'))return env.CHECKIN.get(env.CHECKIN.idFromName('xingyu-checkin-v1')).fetch(req);
    if(url.pathname==='/health')return json({service:'xingyu-chat',protocol:3,channel_count:2,transport:'websocket',limits:LIMITS,features:{follows:1,submission_tools:1}});
    if(url.pathname.startsWith('/ai/'))return env.AI_DRAFTS.get(env.AI_DRAFTS.idFromName('xingyu-ai-v1')).fetch(req);
    if(url.pathname==='/client-config'||url.pathname.startsWith('/client-config/')||url.pathname==='/announcements'||url.pathname.startsWith('/announcements/')||url.pathname==='/discovery'||url.pathname.startsWith('/discovery/'))return env.ANNOUNCEMENTS.get(env.ANNOUNCEMENTS.idFromName('xingyu-announcements-v1')).fetch(req);
    if(url.pathname.startsWith('/dm/')||url.pathname.startsWith('/media/'))return env.DM.get(env.DM.idFromName('xingyu-dm-v1')).fetch(req);
    if(url.pathname.startsWith('/v1/')||url.pathname==='/ws'){
      return env.VERIFIED_CHAT.get(env.VERIFIED_CHAT.idFromName('xingyu-verified-chat-v1')).fetch(req);
    }
    // Version manifests and APKs are immutable/public assets; no management credential is exposed.
    if(url.pathname==='/updates/android')return env.ASSETS.fetch(new Request(new URL('/updates/android.json',url),req));
    return env.ASSETS.fetch(req);
  }
};

/** One hibernating hub enforces shared limits atomically for both independent channels. */
export class ChatHub extends DurableObject {
  constructor(ctx,env){
    super(ctx,env);this.ctx=ctx;this.sql=ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,id TEXT NOT NULL,nickname TEXT NOT NULL,expires INTEGER NOT NULL,banned INTEGER NOT NULL DEFAULT 0,muted INTEGER NOT NULL DEFAULT 0)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY AUTOINCREMENT,channel TEXT NOT NULL CHECK(channel IN ('1','2')),sender TEXT NOT NULL,nickname TEXT NOT NULL,text TEXT NOT NULL,client_id TEXT NOT NULL,created INTEGER NOT NULL,UNIQUE(sender,client_id))`);
    this.sql.exec(`CREATE INDEX IF NOT EXISTS messages_channel_time ON messages(channel,created,id)`);
    this.sql.exec(`CREATE INDEX IF NOT EXISTS messages_sender_time ON messages(sender,created)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS counts(key TEXT PRIMARY KEY,n INTEGER NOT NULL)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS registrations(ip TEXT PRIMARY KEY,day INTEGER NOT NULL,n INTEGER NOT NULL)`);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping','pong'));
    this.readBudget=new Map();
  }
  rows(q,...args){return this.sql.exec(q,...args).toArray();}
  first(q,...args){return this.rows(q,...args)[0];}
  sockets(){return this.ctx.getWebSockets().filter(ws=>ws.readyState===1);}
  message(row){return {id:row.id,channel:row.channel,sender:{id:row.sender,nickname:row.nickname},text:row.text,client_id:row.client_id,created_at:new Date(row.created).toISOString()};}
  count(key){return this.first('SELECT n FROM counts WHERE key=?',key)?.n||0;}
  increment(key){this.sql.exec('INSERT INTO counts(key,n) VALUES(?,1) ON CONFLICT(key) DO UPDATE SET n=n+1',key);}
  async user(req){
    const auth=req.headers.get('Authorization')||'';if(!/^Bearer [a-f0-9]{64}$/.test(auth))fail('聊天身份已过期，请重新输入昵称',401);
    const secret=await hash(auth.slice(7));const u=this.first('SELECT * FROM sessions WHERE token=?',secret);
    if(!u||u.expires<Date.now())fail('聊天身份已过期，请重新输入昵称',401);
    if(u.banned)fail('此聊天身份已被停用',403);return u;
  }
  async fetch(req){
    try{
      const url=new URL(req.url),now=Date.now(),day=dayStart(now);
      if(url.pathname==='/v1/session'&&req.method==='POST'){
        const b=await body(req);if(Object.keys(b).some(k=>k!=='nickname'))fail('只需要提供昵称');
        const name=nickname(b.nickname),ip=await hash(req.headers.get('CF-Connecting-IP')||'local');
        const token=random(),secret=await hash(token),id=crypto.randomUUID().replaceAll('-','').slice(0,16);
        // No asynchronous calls inside admission/quota transaction.
        this.ctx.storage.transactionSync(()=>{
          const rate=this.first('SELECT * FROM registrations WHERE ip=?',ip);
          if(rate?.day===day&&rate.n>=20)fail('此网络今日创建聊天身份过多，请保留现有身份或稍后再试',429);
          if(this.count('r:'+day)>=1000)fail('今日新身份额度已用完，请稍后再试',429);
          this.sql.exec('INSERT INTO sessions(token,id,nickname,expires) VALUES(?,?,?,?)',secret,id,name,now+30*86400_000);
          this.sql.exec('INSERT INTO registrations(ip,day,n) VALUES(?,?,1) ON CONFLICT(ip) DO UPDATE SET n=CASE WHEN day=excluded.day THEN n+1 ELSE 1 END,day=excluded.day',ip,day);
          this.increment('r:'+day);
        });
        if(!await this.ctx.storage.getAlarm())await this.ctx.storage.setAlarm(now+3600_000);
        return json({token,user:{id,nickname:name}});
      }
      const u=await this.user(req);
      if(url.pathname==='/v1/me'&&req.method==='GET')return json({user:{id:u.id,nickname:u.nickname}});
      if(url.pathname==='/v1/channels'&&req.method==='GET')return json({channels:[{id:'1',name:'频道一'},{id:'2',name:'频道二'}]});
      if(url.pathname==='/ws'&&req.method==='GET'){
        const channel=url.searchParams.get('channel');if(!roomOK(channel))fail('频道不存在',404);
        if(req.headers.get('Upgrade')?.toLowerCase()!=='websocket')fail('需要WebSocket连接',426);
        const open=this.sockets(),old=open.filter(w=>w.deserializeAttachment()?.user?.id===u.id);
        if(open.length-old.length>=LIMITS.online)fail('聊天室已满300人，请稍后再试',503);
        for(const w of old)w.close(4001,'另一个连接已进入');
        const pair=new WebSocketPair(),client=pair[0],server=pair[1];
        server.serializeAttachment({channel,user:{id:u.id,nickname:u.nickname,expires:u.expires,token:u.token}});
        this.ctx.acceptWebSocket(server,[channel]);
        server.send(JSON.stringify({type:'ready',channel,online:this.sockets().length}));
        return new Response(null,{status:101,webSocket:client});
      }
      const match=/^\/v1\/channels\/([12])\/messages$/.exec(url.pathname);
      if(match&&req.method==='GET'){
        const channel=match[1];
        const bucket=this.readBudget.get(u.id)||{at:now,n:0};if(now-bucket.at>60000){bucket.at=now;bucket.n=0;}
        if(++bucket.n>30)fail('历史消息加载过快，请稍后再试',429);this.readBudget.set(u.id,bucket);
        if(this.readBudget.size>2000)this.readBudget.clear();
        const limit=Math.max(1,Math.min(30,Number(url.searchParams.get('limit'))||30));
        const before=Number(url.searchParams.get('before'))||Number.MAX_SAFE_INTEGER;
        const after=Number(url.searchParams.get('after'))||0;
        let data=this.rows('SELECT * FROM messages WHERE channel=? AND created>=? AND id<? AND id>? ORDER BY created DESC,id DESC LIMIT ?',channel,now-LIMITS.days*86400_000,before,after,limit+1);
        const older=data.length>limit;data=data.slice(0,limit).reverse();
        return json({channel,messages:data.map(m=>this.message(m)),cursor:data.at(-1)?.id||after,has_older:older});
      }
      fail('接口不存在',404);
    }catch(e){return json({error:e.status?e.message:'聊天室暂时不可用，请稍后重试'},e.status||503);}
  }
  webSocketMessage(ws,raw){
    const a=ws.deserializeAttachment();
    try{
      if(typeof raw!=='string'||encoder.encode(raw).length>4096)fail('消息过大');
      const b=JSON.parse(raw);if(b.type!=='send'||!nonceOK(b.client_id)||b.channel!==a.channel||Object.keys(b).some(k=>!['type','channel','client_id','text'].includes(k)))fail('消息格式不正确');
      const content=text(b.text),now=Date.now(),day=dayStart(now);
      const u=this.first('SELECT * FROM sessions WHERE token=?',a.user.token);
      if(!u||u.expires<now||u.banned){ws.close(4003,'聊天身份失效');return;}
      if(u.muted>now)fail('你暂时被禁言，请稍后再试',403);
      const saved=this.first('SELECT * FROM messages WHERE sender=? AND client_id=?',u.id,b.client_id);
      if(saved){if(saved.channel!==a.channel||saved.text!==content)fail('重试消息与原消息不一致',409);ws.send(JSON.stringify({type:'message',channel:a.channel,messages:[this.message(saved)],cursor:saved.id}));return;}
      const last=this.first('SELECT created,text FROM messages WHERE sender=? ORDER BY created DESC LIMIT 1',u.id);
      const minute=this.first('SELECT COUNT(*) AS n FROM messages WHERE sender=? AND created>?',u.id,now-60000).n;
      const userCount=this.first('SELECT COUNT(*) AS n FROM messages WHERE sender=? AND created>=?',u.id,day).n;
      const reason=limitReason({last:last?.created||0,minute,user:userCount,all:this.count('m:'+day)},now);
      if(reason)fail(reason,429);
      if(last?.text===content&&now-last.created<60000)fail('请不要连续发送相同内容',429);
      let record;
      this.ctx.storage.transactionSync(()=>{
        record=this.sql.exec('INSERT INTO messages(channel,sender,nickname,text,client_id,created) VALUES(?,?,?,?,?,?) RETURNING *',a.channel,u.id,u.nickname,content,b.client_id,now).toArray()[0];
        this.increment('m:'+day);
      });
      const event=JSON.stringify({type:'message',channel:a.channel,messages:[this.message(record)],cursor:record.id});
      for(const peer of this.ctx.getWebSockets(a.channel)){try{if(peer.readyState===1)peer.send(event);}catch{try{peer.close(1011,'请重新连接');}catch{}}}
    }catch(e){try{ws.send(JSON.stringify({type:'error',channel:a?.channel,error:e.status?e.message:'消息格式不正确',client_id:(()=>{try{return JSON.parse(raw).client_id||'';}catch{return '';}})()}));}catch{}}
  }
  webSocketClose(ws,code){try{ws.close(code===1005?1000:code);}catch{}}
  webSocketError(ws){try{ws.close(1011,'请重新连接');}catch{}}
  async alarm(){
    const now=Date.now();
    this.sql.exec('DELETE FROM messages WHERE id IN (SELECT id FROM messages WHERE created<? LIMIT 500)',now-LIMITS.days*86400_000);
    this.sql.exec('DELETE FROM sessions WHERE token IN (SELECT token FROM sessions WHERE expires<? LIMIT 100)',now);
    this.sql.exec('DELETE FROM registrations WHERE day<?',dayStart(now)-86400_000);
    this.sql.exec('DELETE FROM counts WHERE key IN (SELECT key FROM counts WHERE CAST(substr(key,3,13) AS INTEGER)<? LIMIT 500)',dayStart(now)-8*86400_000);
    await this.ctx.storage.setAlarm(now+3600_000);
  }
}
