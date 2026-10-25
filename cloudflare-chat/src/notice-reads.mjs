const DAY=86400000, RETENTION=14*DAY, MAX_KEYS=512;
const valid=key=>typeof key==='string'&&/^(?:dm:[1-9][0-9]{0,15}|chat:[12]:[1-9][0-9]{0,15}|(?:reply|vote):[A-Za-z0-9_-]{1,100})$/.test(key);
const fail=(message,status=400)=>{throw Object.assign(new Error(message),{status});};
export function initNoticeReads(sql){
  sql.exec('CREATE TABLE IF NOT EXISTS notice_reads(uid INTEGER NOT NULL,key TEXT NOT NULL,read_at INTEGER NOT NULL,PRIMARY KEY(uid,key))');
  sql.exec('CREATE INDEX IF NOT EXISTS notice_reads_expiry ON notice_reads(read_at)');
}
export async function serveNoticeReads(hub,req,user,body){
  const now=hub.clock(),cutoff=now-RETENTION;
  if(req.method==='GET')return Response.json({keys:hub.rows('SELECT key FROM notice_reads WHERE uid=? AND read_at>=? ORDER BY read_at DESC,rowid DESC LIMIT ?',user.id,cutoff,MAX_KEYS).map(r=>r.key)},{headers:{'Cache-Control':'no-store'}});
  if(req.method!=='POST')fail('接口不存在',404);
  const value=await body(req);
  if(Object.keys(value).length!==1||!Array.isArray(value.keys)||value.keys.length<1||value.keys.length>60||!value.keys.every(valid))fail('已读标记无效');
  const keys=[...new Set(value.keys)],day=Math.floor(now/DAY)*DAY;
  hub.ctx.storage.transactionSync(()=>{
    hub.validSession(user.token,hub.clock());
    if(hub.count('notice:'+user.id+':'+day)>=2000||hub.count('notice-global:'+day)>=20000)fail('已读同步过于频繁，请稍后重试',429);
    const count=hub.first('SELECT COUNT(*) AS n FROM notice_reads').n;
    if(count>=100000&&keys.some(key=>!hub.first('SELECT 1 FROM notice_reads WHERE uid=? AND key=?',user.id,key)))fail('已读同步暂时繁忙',503);
    for(const key of keys)hub.sql.exec('INSERT OR IGNORE INTO notice_reads(uid,key,read_at) VALUES(?,?,?)',user.id,key,now);
    hub.sql.exec('DELETE FROM notice_reads WHERE uid=? AND key NOT IN (SELECT key FROM notice_reads WHERE uid=? ORDER BY read_at DESC,rowid DESC LIMIT ?)',user.id,user.id,MAX_KEYS);
    hub.increment('notice:'+user.id+':'+day,day);hub.increment('notice-global:'+day,day);
  });
  return Response.json({ok:true},{headers:{'Cache-Control':'no-store'}});
}
export function cleanNoticeReads(hub,now){hub.sql.exec('DELETE FROM notice_reads WHERE rowid IN (SELECT rowid FROM notice_reads WHERE read_at<? LIMIT 1000)',now-RETENTION);}
