import {initFollows,serveFollows} from './follows.mjs';
import {initMedia,serveMedia,claimMedia,cleanMedia,mediaId} from './media.mjs';
// Independent private messages. No website password, cookie, or response body is persisted.
export const DM_LIMITS=Object.freeze({days:7,session_days:7,characters:500,gap_ms:3000,minute:15,user_day:100,global_day:2000,contacts_day:10,verification_ip_day:20,verification_user_day:20,verification_global_day:1000,users:10000,sessions:20000});
const enc=new TextEncoder(),DAY=86400000;
const json=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
const digest=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(value))),x=>x.toString(16).padStart(2,'0')).join('');
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
const dayStart=t=>Math.floor(t/DAY)*DAY;
function uid(value){if(!Number.isSafeInteger(value)||value<1)fail('用户 ID 无效');return value;}
function integer(value,fallback=0){if(value===null||value===undefined||value==='')return fallback;const n=Number(value);if(!Number.isSafeInteger(n)||n<0)fail('分页参数无效');return n;}
function keys(b,allowed){if(Object.keys(b).some(k=>!allowed.includes(k)))fail('请求包含不支持的字段');}
async function limitedBytes(stream,max){if(!stream)fail('请求内容为空');const r=stream.getReader(),chunks=[];let n=0;for(;;){const v=await r.read();if(v.done)break;n+=v.value.length;if(n>max){await r.cancel();fail('数据过大',413);}chunks.push(v.value);}const bytes=new Uint8Array(n);let i=0;for(const c of chunks){bytes.set(c,i);i+=c.length;}return bytes;}
async function body(req){if(!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))fail('请求应为 JSON');const bytes=await limitedBytes(req.body,8192);try{const b=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));if(!b||typeof b!=='object'||Array.isArray(b))fail('请求格式错误');return b;}catch{fail('JSON 格式错误');}}
function content(value){if(typeof value!=='string')fail('消息内容无效');const s=value.trim();if(!s||Array.from(s).length>DM_LIMITS.characters||/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(s))fail('消息须为 1–500 字纯文字');return s;}
const nonce=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{16,80}$/.test(value);
function publicUser(u){return {id:u.id,nickname:u.nickname,avatar:u.avatar};}
function message(m){return {image:m.image_id?{id:m.image_id}:null,id:m.id,sender_id:m.sender,recipient_id:m.recipient,text:m.text,client_id:m.client_id,created_at:new Date(m.created).toISOString()};}

/** Fixed HTTPS target, manual redirects, bounded body, no caller-selected URL or logging. */
export async function verifySiteIdentity(cookie,expected,fetcher=fetch){
  uid(expected);
  if(typeof cookie!=='string'||!cookie.trim()||enc.encode(cookie).length>7000||/[\u0000-\u001F\u007F]/.test(cookie))fail('官网登录会话无效',401);
  let response,payload;
  try{
    response=await fetcher('https://cangku.moe/api/v1/auth/me',{method:'GET',redirect:'manual',signal:AbortSignal.timeout(12000),headers:{Cookie:cookie,Accept:'application/json','X-Requested-With':'XMLHttpRequest','User-Agent':'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/125.0.0.0 Mobile Safari/537.36',Referer:'https://cangku.moe/',Origin:'https://cangku.moe'}});
    if(response.status!==200)fail('官网登录会话验证失败',401);
    payload=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(await limitedBytes(response.body,262144)));
  }catch{fail('官网登录会话验证失败，请重新登录或稍后重试',401);}
  const u=payload?.data;
  if(payload?.code!==0||!u||u.id!==expected||u.should_verify_otp||payload.should_verify_otp||u.is_banned||u.is_muted)fail('官网身份不匹配、待验证或不可用',403);
  // Reject malformed upstream flags instead of accepting ambiguous identity data.
  if(!Number.isSafeInteger(u.id)||u.id<1||typeof u.nickname!=='string'||!u.nickname.trim()||u.nickname.length>200||typeof u.is_banned!=='boolean'||typeof u.is_muted!=='boolean')fail('官网身份数据不完整',403);
  let avatar='';try{const a=new URL(u.avatar);if(a.protocol==='https:'&&!a.username&&!a.password&&a.href.length<=2048)avatar=a.href;}catch{}
  return {id:u.id,nickname:u.nickname.trim(),avatar};
}

/** Test construction injects a verifier/clock in code; production has no request/env override. */
export function createDmHub(Base,{verify=verifySiteIdentity,clock=()=>Date.now()}={}){
  return class extends Base {
    constructor(ctx,env){super(ctx,env);this.ctx=ctx;this.sql=ctx.storage.sql;this.clock=clock;this.readBudget=new Map();
      for(const q of [
        'CREATE TABLE IF NOT EXISTS dm_users(id INTEGER PRIMARY KEY,nickname TEXT NOT NULL,avatar TEXT NOT NULL,enrolled_until INTEGER NOT NULL,banned INTEGER NOT NULL DEFAULT 0,muted INTEGER NOT NULL DEFAULT 0)',
        'CREATE TABLE IF NOT EXISTS dm_sessions(token TEXT PRIMARY KEY,uid INTEGER NOT NULL,expires INTEGER NOT NULL,created INTEGER NOT NULL)',
        'CREATE INDEX IF NOT EXISTS dm_sessions_uid ON dm_sessions(uid,created)',
        'CREATE INDEX IF NOT EXISTS dm_sessions_expiry ON dm_sessions(expires)',
        'CREATE TABLE IF NOT EXISTS dm_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,sender INTEGER NOT NULL,recipient INTEGER NOT NULL,text TEXT NOT NULL,client_id TEXT NOT NULL,created INTEGER NOT NULL,UNIQUE(sender,client_id))',
        'CREATE INDEX IF NOT EXISTS dm_messages_sender_time ON dm_messages(sender,created)',
        'CREATE INDEX IF NOT EXISTS dm_messages_recipient_id ON dm_messages(recipient,id)',
        'CREATE INDEX IF NOT EXISTS dm_messages_pair ON dm_messages(sender,recipient,id)',
        'CREATE INDEX IF NOT EXISTS dm_messages_created ON dm_messages(created)',
        'CREATE TABLE IF NOT EXISTS dm_pairs(a INTEGER NOT NULL,b INTEGER NOT NULL,last_id INTEGER NOT NULL,read_a INTEGER NOT NULL DEFAULT 0,read_b INTEGER NOT NULL DEFAULT 0,delivered_a INTEGER NOT NULL DEFAULT 0,delivered_b INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(a,b))',
        'CREATE INDEX IF NOT EXISTS dm_pairs_a_last ON dm_pairs(a,last_id)',
        'CREATE INDEX IF NOT EXISTS dm_pairs_b_last ON dm_pairs(b,last_id)',
        'CREATE TABLE IF NOT EXISTS dm_blocks(owner INTEGER NOT NULL,peer INTEGER NOT NULL,PRIMARY KEY(owner,peer))',
        'CREATE INDEX IF NOT EXISTS dm_blocks_peer ON dm_blocks(peer,owner)',
        'CREATE TABLE IF NOT EXISTS dm_counts(key TEXT PRIMARY KEY,n INTEGER NOT NULL,day INTEGER NOT NULL)',
        'CREATE TABLE IF NOT EXISTS dm_contacts(sender INTEGER NOT NULL,recipient INTEGER NOT NULL,day INTEGER NOT NULL,PRIMARY KEY(sender,recipient,day))',
        'CREATE TABLE IF NOT EXISTS dm_attempts(ip TEXT PRIMARY KEY,day INTEGER NOT NULL,n INTEGER NOT NULL)'
      ])this.sql.exec(q);
      initMedia(this.sql);initFollows(this.sql);
      if(!this.rows('PRAGMA table_info(dm_messages)').some(c=>c.name==='image_id'))this.sql.exec('ALTER TABLE dm_messages ADD COLUMN image_id TEXT');
    }
    rows(q,...args){return this.sql.exec(q,...args).toArray();}
    first(q,...args){return this.rows(q,...args)[0];}
    count(key){return this.first('SELECT n FROM dm_counts WHERE key=?',key)?.n||0;}
    increment(key,day){this.sql.exec('INSERT INTO dm_counts(key,n,day) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET n=n+1',key,day);}
    pair(a,b){return a<b?[a,b]:[b,a];}
    peer(id,now){const p=this.first('SELECT * FROM dm_users WHERE id=?',id);return p&&p.enrolled_until>now&&!p.banned?p:null;}
    validSession(secret,now){const s=this.first('SELECT s.token,s.expires,u.* FROM dm_sessions s JOIN dm_users u ON u.id=s.uid WHERE s.token=?',secret);if(!s||s.expires<=now)fail('私信身份已过期，请重新开通',401);if(s.banned)fail('此私信身份已停用',403);return s;}
    async user(req){const a=req.headers.get('Authorization')||'';if(!/^Bearer [a-f0-9]{64}$/.test(a))fail('请先开通私信',401);return this.validSession(await digest(a.slice(7)),this.clock());}
    budget(id,now){const b=this.readBudget.get(id)||{at:now,n:0};if(now-b.at>=60000){b.at=now;b.n=0;}if(++b.n>60)fail('私信请求过快，请稍后再试',429);this.readBudget.set(id,b);if(this.readBudget.size>DM_LIMITS.users)this.readBudget.clear();}
    async ensureAlarm(now){if(!await this.ctx.storage.getAlarm())await this.ctx.storage.setAlarm(now+3600000);}
    async fetch(req){try{
      const url=new URL(req.url),path=url.pathname,now=this.clock(),day=dayStart(now),cutoff=now-DM_LIMITS.days*DAY;
      if(path==='/dm/v1/session'&&req.method==='POST'){
        const b=await body(req);keys(b,['site_cookie','expected_user_id']);const expected=uid(b.expected_user_id);
        if(typeof b.site_cookie!=='string'||!b.site_cookie.trim()||enc.encode(b.site_cookie).length>7000||/[\u0000-\u001F\u007F]/.test(b.site_cookie))fail('官网登录会话无效',401);
        const ip=await digest(req.headers.get('CF-Connecting-IP')||'local');
        this.ctx.storage.transactionSync(()=>{const a=this.first('SELECT * FROM dm_attempts WHERE ip=?',ip);if(a?.day===day&&a.n>=DM_LIMITS.verification_ip_day)fail('此网络今日验证次数过多，请明日再试',429);if(this.count('v:'+day)>=DM_LIMITS.verification_global_day)fail('今日私信验证额度已用完',429);this.sql.exec('INSERT INTO dm_attempts(ip,day,n) VALUES(?,?,1) ON CONFLICT(ip) DO UPDATE SET n=CASE WHEN day=excluded.day THEN n+1 ELSE 1 END,day=excluded.day',ip,day);this.increment('v:'+day,day);});
        await this.ensureAlarm(now);
        const identity=await verify(b.site_cookie,expected);if(identity.id!==expected)fail('官网身份不匹配',403);
        const token=random(),secret=await digest(token),issued=this.clock(),expires=issued+DM_LIMITS.session_days*DAY,issuedDay=dayStart(issued);
        this.ctx.storage.transactionSync(()=>{
          const old=this.first('SELECT * FROM dm_users WHERE id=?',identity.id);if(old?.banned||old?.muted>issued)fail('此私信身份不可用',403);
          if(this.count('r:'+identity.id+':'+issuedDay)>=DM_LIMITS.verification_user_day)fail('此账号今日开通次数过多',429);
          if(!old&&this.first('SELECT COUNT(*) AS n FROM dm_users').n>=DM_LIMITS.users)fail('私信服务暂时已满',503);
          if(this.first('SELECT COUNT(*) AS n FROM dm_sessions').n>=DM_LIMITS.sessions)fail('私信服务暂时已满',503);
          this.sql.exec('INSERT INTO dm_users(id,nickname,avatar,enrolled_until) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET nickname=excluded.nickname,avatar=excluded.avatar,enrolled_until=excluded.enrolled_until',identity.id,identity.nickname,identity.avatar,expires);
          this.sql.exec('DELETE FROM dm_sessions WHERE token IN (SELECT token FROM dm_sessions WHERE uid=? ORDER BY created DESC LIMIT -1 OFFSET 2)',identity.id);
          this.sql.exec('INSERT INTO dm_sessions(token,uid,expires,created) VALUES(?,?,?,?)',secret,identity.id,expires,issued);this.increment('r:'+identity.id+':'+issuedDay,issuedDay);
        });
        return json({token,user:identity,expires_at:new Date(expires).toISOString()});
      }
      // These internal routes are reachable only through a DO binding. The public Worker never routes /internal/*.
      if(path==='/internal/identity'||path==='/internal/media/claim'){
        if(req.method!=='POST')fail('接口不存在',404);const b=await body(req);if(typeof b.token_hash!=='string'||!/^[a-f0-9]{64}$/.test(b.token_hash))fail('身份无效',401);
        const user=this.validSession(b.token_hash,now);if(user.muted>now)fail('当前账号已禁言',403);
        if(path==='/internal/identity')return json({user:publicUser(user),expires_at:user.expires});
        const image=claimMedia(this,user,b.image_id,'chat',b.channel,b.client_id);return json({image});
      }
      const u=await this.user(req);this.budget(u.id,now);
      if(path==='/dm/v1/follows'||path.startsWith('/dm/v1/follows/'))return await serveFollows(this,req,url,u,body);
      if(path==='/dm/v1/profile/sync'&&req.method==='POST'){
        const b=await body(req);keys(b,['site_cookie']);
        // Existing verified sessions may refresh their own profile, never choose a UID/name.
        this.ctx.storage.transactionSync(()=>{
          if(this.count('profile:'+u.id+':'+day)>=20||this.count('v:'+day)>=DM_LIMITS.verification_global_day)fail('今日资料同步次数已用完，请稍后再试',429);
          this.increment('profile:'+u.id+':'+day,day);this.increment('v:'+day,day);
        });
        const identity=await verify(b.site_cookie,u.id);if(identity.id!==u.id)fail('官网身份不匹配',403);
        this.ctx.storage.transactionSync(()=>{this.validSession(u.token,this.clock());this.sql.exec('UPDATE dm_users SET nickname=?,avatar=? WHERE id=?',identity.nickname,identity.avatar,u.id);});
        return json({user:identity});
      }
      if(path.startsWith('/media/v1/'))return await serveMedia(this,req,u);
      if(path==='/dm/v1/me'&&req.method==='GET')return json({user:publicUser(u)});
      if(path==='/dm/v1/logout'&&req.method==='POST'){this.sql.exec('DELETE FROM dm_sessions WHERE token=?',u.token);return json({ok:true});}
      if(path==='/dm/v1/peer'&&req.method==='GET'){const p=this.peer(uid(integer(url.searchParams.get('id'))),now);return json(p?{available:true,user:publicUser(p)}:{available:false});}
      if(path==='/dm/v1/blocks'&&req.method==='GET')return json({users:this.rows('SELECT u.* FROM dm_blocks b JOIN dm_users u ON u.id=b.peer WHERE b.owner=? ORDER BY u.id LIMIT 200',u.id).map(publicUser)});
      if(path==='/dm/v1/block'&&req.method==='POST'){
        const b=await body(req);keys(b,['peer_id','blocked']);const peer=uid(b.peer_id);if(peer===u.id||typeof b.blocked!=='boolean')fail('屏蔽参数无效');if(!this.first('SELECT id FROM dm_users WHERE id=?',peer))fail('用户尚未开通私信',404);
        this.ctx.storage.transactionSync(()=>{this.validSession(u.token,this.clock());if(b.blocked){if(this.first('SELECT COUNT(*) AS n FROM dm_blocks WHERE owner=?',u.id).n>=200&&!this.first('SELECT 1 FROM dm_blocks WHERE owner=? AND peer=?',u.id,peer))fail('屏蔽列表已满',429);this.sql.exec('INSERT OR IGNORE INTO dm_blocks(owner,peer) VALUES(?,?)',u.id,peer);}else this.sql.exec('DELETE FROM dm_blocks WHERE owner=? AND peer=?',u.id,peer);});return json({ok:true});
      }
      if(path==='/dm/v1/conversations'&&req.method==='GET'){
        const before=integer(url.searchParams.get('before'),Number.MAX_SAFE_INTEGER);
        let rows=this.rows(`SELECT p.*,m.id,m.sender,m.recipient,m.text,m.client_id,m.created,m.image_id,u.id AS peer_id,u.nickname,u.avatar,(SELECT COUNT(*) FROM dm_messages n WHERE n.sender=u.id AND n.recipient=? AND n.id>CASE WHEN p.a=? THEN p.read_a ELSE p.read_b END AND n.created>=?) AS unread FROM dm_pairs p JOIN dm_messages m ON m.id=p.last_id JOIN dm_users u ON u.id=CASE WHEN p.a=? THEN p.b ELSE p.a END WHERE (p.a=? OR p.b=?) AND m.id<? AND m.created>=? ORDER BY m.id DESC LIMIT 31`,u.id,u.id,cutoff,u.id,u.id,u.id,before,cutoff);
        const more=rows.length>30;rows=rows.slice(0,30);return json({conversations:rows.map(r=>({peer:{id:r.peer_id,nickname:r.nickname,avatar:r.avatar},last_message:message(r),unread:r.unread})),has_more:more});
      }
      if(path==='/dm/v1/messages'&&req.method==='GET'){
        const id=uid(integer(url.searchParams.get('peer'))),p=this.first('SELECT * FROM dm_users WHERE id=?',id);if(!p||id===u.id)fail('用户不存在或尚未开通私信',404);
        const before=integer(url.searchParams.get('before'),Number.MAX_SAFE_INTEGER),after=integer(url.searchParams.get('after')),limit=Math.min(30,Math.max(1,integer(url.searchParams.get('limit'),30)));
        if(url.searchParams.has('before')&&url.searchParams.has('after'))fail('请只使用一个分页方向');
        const forward=url.searchParams.has('after');let rows=this.rows(`SELECT * FROM dm_messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) AND created>=? AND id<? AND id>? ORDER BY id ${forward?'ASC':'DESC'} LIMIT ?`,u.id,id,id,u.id,cutoff,before,after,limit+1);
        const more=rows.length>limit;rows=rows.slice(0,limit);if(!forward)rows.reverse();
        const delivered=Math.max(0,...rows.filter(m=>m.recipient===u.id).map(m=>m.id));if(delivered){const [a,b]=this.pair(u.id,id),col=u.id===a?'delivered_a':'delivered_b';this.sql.exec(`UPDATE dm_pairs SET ${col}=MAX(${col},?) WHERE a=? AND b=? AND ${col}<?`,delivered,a,b,delivered);}
        const first=rows[0]?.id||after,older=!!this.first('SELECT id FROM dm_messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) AND created>=? AND id<? LIMIT 1',u.id,id,id,u.id,cutoff,first);
        return json({peer:publicUser(p),messages:rows.map(message),has_older:older,has_more:forward&&more,cursor:rows.at(-1)?.id||after});
      }
      if(path==='/dm/v1/messages'&&req.method==='POST'){
        const b=await body(req);keys(b,['peer_id','text','client_id','image_id']);const image=b.image_id||null;if(image&&!mediaId(image))fail('图片编号无效');const inputText=b.text??'';if(typeof inputText!=='string')fail('消息内容无效');const id=uid(b.peer_id),text=image&&!inputText.trim()?'':content(inputText);if(id===u.id||!nonce(b.client_id))fail('收件人或消息编号无效');let record;
        this.ctx.storage.transactionSync(()=>{
          const time=this.clock(),day=dayStart(time),actor=this.validSession(u.token,time);if(actor.muted>time)fail('你暂时无法发送私信',403);
          const peer=this.peer(id,time);if(!peer||peer.muted>time)fail('对方尚未开通私信或暂时不可用',404);
          if(this.first('SELECT 1 FROM dm_blocks WHERE (owner=? AND peer=?) OR (owner=? AND peer=?)',u.id,id,id,u.id))fail('当前无法向该用户发送私信',403);
          const saved=this.first('SELECT * FROM dm_messages WHERE sender=? AND client_id=?',u.id,b.client_id);if(saved){if(saved.recipient!==id||saved.text!==text||(saved.image_id||null)!==image)fail('重试消息与原消息不一致',409);record=saved;return;}
          const last=this.first('SELECT created,text FROM dm_messages WHERE sender=? ORDER BY id DESC LIMIT 1',u.id);
          if(last&&time-last.created<DM_LIMITS.gap_ms)fail('请间隔 3 秒再发送',429);
          if(this.first('SELECT COUNT(*) AS n FROM dm_messages WHERE sender=? AND created>?',u.id,time-60000).n>=DM_LIMITS.minute)fail('每分钟最多发送 15 条私信',429);
          if(this.first('SELECT COUNT(*) AS n FROM dm_messages WHERE sender=? AND created>=?',u.id,day).n>=DM_LIMITS.user_day)fail('今日私信额度已用完',429);
          if(this.count('m:'+day)>=DM_LIMITS.global_day)fail('今日私信服务额度已用完',429);
          if(!image&&last?.text===text&&time-last.created<60000)fail('请勿重复发送相同内容',429);
          const fresh=!this.first('SELECT 1 FROM dm_contacts WHERE sender=? AND recipient=? AND day=?',u.id,id,day);
          if(fresh&&this.first('SELECT COUNT(*) AS n FROM dm_contacts WHERE sender=? AND day=?',u.id,day).n>=DM_LIMITS.contacts_day)fail('每天最多主动联系 10 位用户',429);
          if(image)claimMedia(this,actor,image,'dm',id,b.client_id);
          record=this.first('INSERT INTO dm_messages(sender,recipient,text,client_id,created,image_id) VALUES(?,?,?,?,?,?) RETURNING *',u.id,id,text,b.client_id,time,image);
          const [a,bp]=this.pair(u.id,id);this.sql.exec('INSERT INTO dm_pairs(a,b,last_id) VALUES(?,?,?) ON CONFLICT(a,b) DO UPDATE SET last_id=excluded.last_id',a,bp,record.id);
          if(fresh)this.sql.exec('INSERT INTO dm_contacts(sender,recipient,day) VALUES(?,?,?)',u.id,id,day);this.increment('m:'+day,day);
        });return json({message:message(record)});
      }
      if(path==='/dm/v1/read'&&req.method==='POST'){
        const b=await body(req);keys(b,['peer_id','last_id']);const peer=uid(b.peer_id),id=uid(b.last_id);if(peer===u.id)fail('收件人无效');
        this.ctx.storage.transactionSync(()=>{this.validSession(u.token,this.clock());const m=this.first('SELECT * FROM dm_messages WHERE id=? AND sender=? AND recipient=? AND created>=?',id,peer,u.id,cutoff);if(!m)fail('只能标记收到的私信',403);const [a,bp]=this.pair(u.id,peer),p=this.first('SELECT * FROM dm_pairs WHERE a=? AND b=?',a,bp),read=u.id===a?'read_a':'read_b',delivered=u.id===a?'delivered_a':'delivered_b';if(!p||p[delivered]<id)fail('请先加载对应私信',403);this.sql.exec(`UPDATE dm_pairs SET ${read}=MAX(${read},?) WHERE a=? AND b=? AND ${read}<?`,id,a,bp,id);});return json({ok:true});
      }
      fail('接口不存在',404);
    }catch(e){return json({error:e.status?e.message:'私信服务暂时不可用，请稍后重试'},e.status||503);}}
    async alarm(){const now=this.clock(),cutoff=now-DM_LIMITS.days*DAY;cleanMedia(this,now);
      this.sql.exec('DELETE FROM dm_messages WHERE id IN (SELECT id FROM dm_messages WHERE created<? LIMIT 1000)',cutoff);
      this.sql.exec('DELETE FROM dm_sessions WHERE token IN (SELECT token FROM dm_sessions WHERE expires<=? LIMIT 500)',now);
      this.sql.exec('DELETE FROM dm_pairs WHERE last_id NOT IN (SELECT id FROM dm_messages)');
      this.sql.exec('DELETE FROM dm_counts WHERE day<?',dayStart(cutoff));this.sql.exec('DELETE FROM dm_contacts WHERE day<?',dayStart(cutoff));this.sql.exec('DELETE FROM dm_attempts WHERE day<?',dayStart(now)-DAY);
      // Preserve moderation and block decisions; remove inactive ordinary identities only after history expires.
      this.sql.exec('DELETE FROM dm_users WHERE id IN (SELECT u.id FROM dm_users u WHERE u.enrolled_until<? AND u.banned=0 AND u.muted=0 AND NOT EXISTS(SELECT 1 FROM dm_messages m WHERE m.sender=u.id OR m.recipient=u.id) AND NOT EXISTS(SELECT 1 FROM dm_blocks b WHERE b.owner=u.id OR b.peer=u.id) AND NOT EXISTS(SELECT 1 FROM social_follows f WHERE f.owner=u.id OR f.peer=u.id) LIMIT 100)',cutoff);
      await this.ctx.storage.setAlarm(now+3600000);
    }
  };
}
