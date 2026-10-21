import {DurableObject} from 'cloudflare:workers';
import {LIMITS,roomOK,nonceOK,limitReason,dayStart} from './policy.mjs';
const enc=new TextEncoder(),DAY=86400000;
const json=(o,status=200)=>Response.json(o,{status,headers:{'Cache-Control':'no-store'}});
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
const hash=async token=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(token))),b=>b.toString(16).padStart(2,'0')).join('');
export class VerifiedChatHub extends DurableObject {
  constructor(ctx,env){super(ctx,env);this.ctx=ctx;this.env=env;this.sql=ctx.storage.sql;this.locks=new Map();this.reads=new Map();
    this.sql.exec('CREATE TABLE IF NOT EXISTS verified_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,channel TEXT NOT NULL,sender INTEGER NOT NULL,nickname TEXT NOT NULL,avatar TEXT NOT NULL,text TEXT NOT NULL,image TEXT,mentions TEXT NOT NULL,reply TEXT,client_id TEXT NOT NULL,created INTEGER NOT NULL,UNIQUE(sender,client_id))');
    this.sql.exec('CREATE INDEX IF NOT EXISTS verified_messages_channel ON verified_messages(channel,id)');this.sql.exec('CREATE INDEX IF NOT EXISTS verified_messages_sender ON verified_messages(sender,created)');
    this.sql.exec('CREATE TABLE IF NOT EXISTS participants(id INTEGER PRIMARY KEY,nickname TEXT NOT NULL,avatar TEXT NOT NULL,seen INTEGER NOT NULL)');this.sql.exec('CREATE TABLE IF NOT EXISTS counts(day INTEGER PRIMARY KEY,n INTEGER NOT NULL)');
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping','pong'));
  }
  rows(q,...args){return this.sql.exec(q,...args).toArray();}first(q,...args){return this.rows(q,...args)[0];}
  async internal(path,data){const r=await this.env.DM.get(this.env.DM.idFromName('xingyu-dm-v1')).fetch(new Request('https://internal.invalid'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}));const result=await r.json();if(!r.ok)throw Object.assign(new Error(result.error||'仓库认证已过期，请重新认证'),{status:r.status,auth:path==='/internal/identity'&&[401,403].includes(r.status)});return result;}
  remember(u){
    const previous=this.first('SELECT * FROM participants WHERE id=?',u.id),changed=previous&&(previous.nickname!==u.nickname||previous.avatar!==u.avatar);
    if(!previous||changed)this.sql.exec('INSERT INTO participants(id,nickname,avatar,seen) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET nickname=excluded.nickname,avatar=excluded.avatar,seen=excluded.seen',u.id,u.nickname,u.avatar,Date.now());
    if(changed)for(const ws of this.ctx.getWebSockets())try{if(ws.readyState===1)ws.send(JSON.stringify({type:'profile',channel:ws.deserializeAttachment().channel,user:{id:u.id,nickname:u.nickname,avatar:u.avatar}}));}catch{}
  }
  async user(req){const header=req.headers.get('Authorization')||'';if(!/^Bearer [a-f0-9]{64}$/.test(header))fail('请先绑定仓库账号',401);const token_hash=await hash(header.slice(7)),result=await this.internal('/internal/identity',{token_hash});this.remember(result.user);return {...result.user,token_hash};}
  profile(id,fallback){const p=this.first('SELECT * FROM participants WHERE id=?',id);return p?{id:p.id,nickname:p.nickname,avatar:p.avatar}:fallback;}
  message(m){const reply=m.reply?JSON.parse(m.reply):null;if(reply)reply.sender=this.profile(reply.sender.id,reply.sender);return {id:m.id,channel:m.channel,sender:this.profile(m.sender,{id:m.sender,nickname:m.nickname,avatar:m.avatar}),text:m.text,image:m.image?JSON.parse(m.image):null,mentions:JSON.parse(m.mentions).map(p=>this.profile(p.id,p)),reply_to:reply,client_id:m.client_id,created_at:new Date(m.created).toISOString()};}
  async fetch(req){try{
    const url=new URL(req.url);if(url.pathname==='/v1/session')fail('匿名聊天已关闭，请使用仓库账号认证',410);
    const u=await this.user(req),now=Date.now();
    if(url.pathname==='/v1/me'&&req.method==='GET')return json({user:{id:u.id,nickname:u.nickname,avatar:u.avatar}});
    if(url.pathname==='/v1/channels'&&req.method==='GET')return json({channels:[{id:'1',name:'频道一'},{id:'2',name:'频道二'}]});
    if(url.pathname==='/ws'&&req.method==='GET'){
      const channel=url.searchParams.get('channel');if(!roomOK(channel))fail('频道不存在',404);if(req.headers.get('Upgrade')?.toLowerCase()!=='websocket')fail('需要WebSocket连接',426);
      const open=this.ctx.getWebSockets().filter(w=>w.readyState===1),old=open.filter(w=>w.deserializeAttachment()?.uid===u.id);if(open.length-old.length>=LIMITS.online)fail('聊天室已满300人',503);
      for(const w of old)w.close(4001,'账号已在另一个连接进入');this.sql.exec('INSERT INTO participants(id,nickname,avatar,seen) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET nickname=excluded.nickname,avatar=excluded.avatar,seen=excluded.seen',u.id,u.nickname,u.avatar,now);
      const pair=new WebSocketPair(),client=pair[0],server=pair[1];server.serializeAttachment({uid:u.id,token_hash:u.token_hash,channel});this.ctx.acceptWebSocket(server,[channel]);server.send(JSON.stringify({type:'ready',channel,user:{id:u.id,nickname:u.nickname,avatar:u.avatar}}));
      if(!await this.ctx.storage.getAlarm())await this.ctx.storage.setAlarm(now+3600000);return new Response(null,{status:101,webSocket:client});
    }
    const match=/^\/v1\/channels\/([12])\/messages$/.exec(url.pathname);
    if(match&&req.method==='GET'){
      const budget=this.reads.get(u.id)||{at:now,n:0};if(now-budget.at>60000){budget.at=now;budget.n=0;}if(++budget.n>30)fail('加载历史过快',429);this.reads.set(u.id,budget);if(this.reads.size>2000)this.reads.clear();
      const limit=Math.max(1,Math.min(30,Number(url.searchParams.get('limit'))||30)),before=Number(url.searchParams.get('before'))||Number.MAX_SAFE_INTEGER,after=Number(url.searchParams.get('after'))||0;
      let rows=this.rows('SELECT * FROM verified_messages WHERE channel=? AND created>=? AND id<? AND id>? ORDER BY id DESC LIMIT ?',match[1],now-7*DAY,before,after,limit+1);const older=rows.length>limit;rows=rows.slice(0,limit).reverse();return json({channel:match[1],messages:rows.map(m=>this.message(m)),has_older:older,cursor:rows.at(-1)?.id||after});
    }fail('接口不存在',404);
  }catch(e){return json({error:e.status?e.message:'聊天室暂时不可用'},e.status||503);}}
  async webSocketMessage(ws,raw){
    const a=ws.deserializeAttachment();if(typeof raw!=='string'||enc.encode(raw).length>4096){ws.close(1009,'消息过大');return;}
    // Serialize the entire auth/claim/write sequence per UID despite asynchronous DO calls.
    const previous=this.locks.get(a.uid)||Promise.resolve();const next=previous.catch(()=>{}).then(()=>this.send(ws,a,raw));this.locks.set(a.uid,next);try{await next;}finally{if(this.locks.get(a.uid)===next)this.locks.delete(a.uid);}
  }
  async send(ws,a,raw){let b;try{
    b=JSON.parse(raw);if(!b||b.type!=='send'||!nonceOK(b.client_id)||b.channel!==a.channel||Object.keys(b).some(k=>!['type','channel','text','client_id','image_id','mentions','reply_to_id'].includes(k)))fail('消息格式不正确');
    if(b.text!==undefined&&typeof b.text!=='string')fail('消息正文必须是文字');const text=typeof b.text==='string'?b.text.trim():'',imageId=b.image_id||null;if((!text&&!imageId)||[...text].length>300||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u.test(text)||imageId&&!/^[a-f0-9]{32}$/.test(imageId))fail('消息格式不正确');
    const ids=b.mentions||[];if(!Array.isArray(ids)||ids.length>5||new Set(ids).size!==ids.length||ids.some(id=>!Number.isSafeInteger(id)||id<1))fail('每条最多艾特5位用户');
    const uidResult=await this.internal('/internal/identity',{token_hash:a.token_hash}),u=uidResult.user;if(u.id!==a.uid)fail('认证身份不一致',401);this.remember(u);
    const now=Date.now(),day=dayStart(now),saved=this.first('SELECT * FROM verified_messages WHERE sender=? AND client_id=?',u.id,b.client_id);
    const same=saved&&saved.channel===a.channel&&saved.text===text&&(saved.image?JSON.parse(saved.image).id:null)===imageId&&JSON.stringify(JSON.parse(saved.mentions).map(m=>m.id))===JSON.stringify(ids)&&(saved.reply?JSON.parse(saved.reply).id:0)===(b.reply_to_id||0);
    if(saved){if(!same)fail('重试消息与原消息不一致',409);ws.send(JSON.stringify({type:'message',channel:a.channel,messages:[this.message(saved)],cursor:saved.id}));return;}
    const last=this.first('SELECT created,text,image FROM verified_messages WHERE sender=? ORDER BY id DESC LIMIT 1',u.id),minute=this.first('SELECT COUNT(*) AS n FROM verified_messages WHERE sender=? AND created>?',u.id,now-60000).n,user=this.first('SELECT COUNT(*) AS n FROM verified_messages WHERE sender=? AND created>=?',u.id,day).n;
    const reason=limitReason({last:last?.created||0,minute,user,all:this.first('SELECT n FROM counts WHERE day=?',day)?.n||0},now);if(reason)fail(reason,429);if(!imageId&&last?.text===text&&!last.image&&now-last.created<60000)fail('请勿重复发送相同内容',429);
    const mentions=ids.map(id=>{const peer=this.first('SELECT * FROM participants WHERE id=? AND seen>=?',id,now-7*DAY);if(!peer||!text.includes('(UID:'+id+')'))fail('艾特对象无效或已从正文移除');return {id:peer.id,nickname:peer.nickname};});
    let reply=null;if(b.reply_to_id){if(!Number.isSafeInteger(b.reply_to_id))fail('引用消息无效');const original=this.first('SELECT * FROM verified_messages WHERE id=? AND channel=? AND created>=?',b.reply_to_id,a.channel,now-7*DAY);if(!original)fail('只能回复当前频道7天内的消息');reply={id:original.id,sender:{id:original.sender,nickname:original.nickname},text:[...original.text].slice(0,200).join(''),has_image:!!original.image};}
    const image=imageId?(await this.internal('/internal/media/claim',{token_hash:a.token_hash,image_id:imageId,channel:a.channel,client_id:b.client_id})).image:null;
    // Revalidate after the media RPC, then enforce quotas again in the synchronous write transaction.
    await this.internal('/internal/identity',{token_hash:a.token_hash});let row;
    this.ctx.storage.transactionSync(()=>{
      const moment=Date.now(),window=dayStart(moment),recent=this.first('SELECT created FROM verified_messages WHERE sender=? ORDER BY id DESC LIMIT 1',u.id);
      const check=limitReason({last:recent?.created||0,minute:this.first('SELECT COUNT(*) AS n FROM verified_messages WHERE sender=? AND created>?',u.id,moment-60000).n,user:this.first('SELECT COUNT(*) AS n FROM verified_messages WHERE sender=? AND created>=?',u.id,window).n,all:this.first('SELECT n FROM counts WHERE day=?',window)?.n||0},moment);if(check)fail(check,429);
      row=this.first('INSERT INTO verified_messages(channel,sender,nickname,avatar,text,image,mentions,reply,client_id,created) VALUES(?,?,?,?,?,?,?,?,?,?) RETURNING *',a.channel,u.id,u.nickname,u.avatar,text,image?JSON.stringify(image):null,JSON.stringify(mentions),reply?JSON.stringify(reply):null,b.client_id,moment);this.sql.exec('INSERT INTO counts(day,n) VALUES(?,1) ON CONFLICT(day) DO UPDATE SET n=n+1',window);});
    const event=JSON.stringify({type:'message',channel:a.channel,messages:[this.message(row)],cursor:row.id});for(const peer of this.ctx.getWebSockets(a.channel))try{if(peer.readyState===1)peer.send(event);}catch{}
  }catch(e){if(e.status===401||e.auth){try{ws.close(4003,'认证已失效');}catch{}return;}try{ws.send(JSON.stringify({type:'error',channel:a.channel,client_id:b?.client_id||'',error:e.status?e.message:'消息格式不正确'}));}catch{}}}
  webSocketClose(ws,code){try{ws.close(code===1005?1000:code);}catch{}}webSocketError(ws){try{ws.close(1011,'请重新连接');}catch{}}
  async alarm(){const now=Date.now();this.sql.exec('DELETE FROM verified_messages WHERE id IN (SELECT id FROM verified_messages WHERE created<? LIMIT 500)',now-7*DAY);this.sql.exec('DELETE FROM participants WHERE seen<?',now-7*DAY);this.sql.exec('DELETE FROM counts WHERE day<?',dayStart(now)-8*DAY);await this.ctx.storage.setAlarm(now+3600000);}
}
