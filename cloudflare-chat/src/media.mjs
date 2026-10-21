export const MEDIA_LIMITS=Object.freeze({bytes:262144,edge:1600,pixels:2560000,user_day:10,global_day:100,storage:64*1024*1024,days:7});
const DAY=86400000;
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
export const mediaId=id=>typeof id==='string'&&/^[a-f0-9]{32}$/.test(id);
export function initMedia(sql){
  sql.exec('CREATE TABLE IF NOT EXISTS dm_media(id TEXT PRIMARY KEY,owner INTEGER NOT NULL,scope TEXT NOT NULL,target TEXT NOT NULL,data BLOB NOT NULL,bytes INTEGER NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,created INTEGER NOT NULL,upload_id TEXT NOT NULL,digest TEXT NOT NULL,claim_nonce TEXT,claimed_at INTEGER,UNIQUE(owner,upload_id))');
  sql.exec('CREATE INDEX IF NOT EXISTS dm_media_created ON dm_media(created)');
  if(!sql.exec('PRAGMA table_info(dm_media)').toArray().some(c=>c.name==='claimed_at'))sql.exec('ALTER TABLE dm_media ADD COLUMN claimed_at INTEGER');
}
export function jpegSize(bytes){
  if(bytes.length<20||bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)fail('只支持有效JPEG图片');
  let at=2,width=0,height=0,scan=false;
  while(at<bytes.length-2){
    if(bytes[at++]!==255)fail('JPEG结构无效');while(bytes[at]===255)at++;const marker=bytes[at++];
    if(marker===217)break;if(marker===216||marker===0||marker>=208&&marker<=215)fail('JPEG结构无效');
    if(at+2>bytes.length)fail('JPEG不完整');const length=(bytes[at]<<8)|bytes[at+1];if(length<2||at+length>bytes.length-2)fail('JPEG不完整');
    if(marker===225)fail('图片包含EXIF元数据，请重新压缩后上传');
    if([192,193,194].includes(marker)){if(length<8)fail('JPEG尺寸无效');height=(bytes[at+3]<<8)|bytes[at+4];width=(bytes[at+5]<<8)|bytes[at+6];}
    if(marker===218){scan=true;break;}at+=length;
  }
  if(!scan||!width||!height||width>MEDIA_LIMITS.edge||height>MEDIA_LIMITS.edge||width*height>MEDIA_LIMITS.pixels)fail('图片边长须不超过1600像素');
  return {width,height};
}
export function imageMeta(row){return {id:row.id,width:row.width,height:row.height,size:row.bytes,mime:'image/jpeg'};}
export function claimMedia(h,user,id,scope,target,nonce){
  if(!mediaId(id))fail('图片编号无效');const row=h.first('SELECT * FROM dm_media WHERE id=?',id),now=h.clock();
  if(!row||row.owner!==user.id||row.scope!==scope||row.target!==String(target)||(row.claimed_at||row.created)<now-MEDIA_LIMITS.days*DAY||(!row.claim_nonce&&row.created<now-3600000))fail('图片不存在、已过期或不属于此会话',403);
  if(row.claim_nonce&&row.claim_nonce!==nonce)fail('图片已用于另一条消息',409);
  h.sql.exec('UPDATE dm_media SET claim_nonce=?,claimed_at=? WHERE id=? AND claim_nonce IS NULL',nonce,now,id);return imageMeta(row);
}
export async function serveMedia(h,req,u){
  const url=new URL(req.url),id=url.pathname.split('/').at(-1),now=h.clock(),day=Math.floor(now/DAY)*DAY;
  if(url.pathname==='/media/v1/images'&&req.method==='POST'){
    if(u.muted>now)fail('当前账号无法上传图片',403);
    const scope=url.searchParams.get('scope'),target=url.searchParams.get('target'),upload=req.headers.get('X-Upload-ID');
    if(!['chat','dm'].includes(scope)||!upload||!/^[A-Za-z0-9_-]{16,80}$/.test(upload))fail('图片会话无效');
    if(scope==='chat'&&!['1','2'].includes(target))fail('频道不存在',404);
    if(scope==='dm'){
      const peer=Number(target);if(!Number.isSafeInteger(peer)||peer<1||peer===u.id||!h.peer(peer,now))fail('收信人未开通',404);
      if(h.first('SELECT 1 FROM dm_blocks WHERE (owner=? AND peer=?) OR (owner=? AND peer=?)',u.id,peer,peer,u.id))fail('当前无法向此用户发送图片',403);
    }
    if(req.headers.get('Content-Type')!=='image/jpeg')fail('仅支持JPEG图片');
    const r=req.body?.getReader();if(!r)fail('图片为空');let size=0,chunks=[];for(;;){const part=await r.read();if(part.done)break;size+=part.value.length;if(size>MEDIA_LIMITS.bytes){await r.cancel();fail('图片不得超过256KB',413);}chunks.push(part.value);}
    const data=new Uint8Array(size);let offset=0;for(const chunk of chunks){data.set(chunk,offset);offset+=chunk.length;}const dimensions=jpegSize(data);
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',data)),b=>b.toString(16).padStart(2,'0')).join('');let row;
    h.ctx.storage.transactionSync(()=>{
      const current=h.validSession(u.token,h.clock());if(current.muted>h.clock())fail('当前账号无法上传',403);
      row=h.first('SELECT * FROM dm_media WHERE owner=? AND upload_id=?',u.id,upload);if(row){if(row.scope!==scope||row.target!==target||row.digest!==digest)fail('重试图片与原图片不一致',409);return;}
      if(h.count('img:'+u.id+':'+day)>=MEDIA_LIMITS.user_day||h.count('imgall:'+day)>=MEDIA_LIMITS.global_day)fail('今日图片发送额度已用完',429);
      if((h.first('SELECT COALESCE(SUM(bytes),0) AS n FROM dm_media').n+size)>MEDIA_LIMITS.storage)fail('图片存储暂满，请稍后再试',503);
      const imageId=crypto.randomUUID().replaceAll('-','');h.sql.exec('INSERT INTO dm_media(id,owner,scope,target,data,bytes,width,height,created,upload_id,digest) VALUES(?,?,?,?,?,?,?,?,?,?,?)',imageId,u.id,scope,target,data,size,dimensions.width,dimensions.height,now,upload,digest);
      h.increment('img:'+u.id+':'+day,day);h.increment('imgall:'+day,day);row={id:imageId,bytes:size,...dimensions};
    });await h.ensureAlarm(now);return Response.json({image:imageMeta(row)},{headers:{'Cache-Control':'no-store'}});
  }
  if(!/^\/media\/v1\/images\/[a-f0-9]{32}$/.test(url.pathname)||!mediaId(id))fail('图片不存在',404);
  const row=h.first('SELECT * FROM dm_media WHERE id=?',id);
  if(!row||(row.claimed_at||row.created)<now-MEDIA_LIMITS.days*DAY||(!row.claim_nonce&&row.created<now-3600000))fail('图片已过期或不存在',404);
  if(req.method==='DELETE'){if(row.owner!==u.id||row.claim_nonce)fail('不能删除已发送的图片',403);h.sql.exec('DELETE FROM dm_media WHERE id=?',id);return Response.json({ok:true});}
  if(req.method!=='GET')fail('不支持的图片操作',405);
  if(!row.claim_nonce&&u.id!==row.owner)fail('图片尚未发送',403);
  if(row.scope==='dm'&&u.id!==row.owner&&u.id!==Number(row.target))fail('无权查看此私信图片',403);
  return new Response(row.data,{headers:{'Content-Type':'image/jpeg','Content-Length':String(row.bytes),'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"}});
}
export function cleanMedia(h,now){h.sql.exec('DELETE FROM dm_media WHERE id IN (SELECT id FROM dm_media WHERE (claim_nonce IS NOT NULL AND COALESCE(claimed_at,created)<?) OR (claim_nonce IS NULL AND created<?) LIMIT 200)',now-MEDIA_LIMITS.days*DAY,now-3600000);}
