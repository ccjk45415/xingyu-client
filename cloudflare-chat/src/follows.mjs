// Independent follows: actor comes exclusively from the existing verified session.
export function initFollows(sql){
 sql.exec('CREATE TABLE IF NOT EXISTS social_follows(owner INTEGER NOT NULL,peer INTEGER NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(owner,peer),CHECK(owner<>peer))');
 sql.exec('CREATE INDEX IF NOT EXISTS social_follows_peer ON social_follows(peer,created,owner)');
}
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
const json=value=>Response.json(value,{headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
function id(raw){const value=Number(raw);if(!Number.isSafeInteger(value)||value<=0||value>2147483647)fail('用户UID无效');return value;}
function counts(h,peer){return {following_count:h.first('SELECT COUNT(*) AS n FROM social_follows WHERE owner=?',peer).n,follower_count:h.first('SELECT COUNT(*) AS n FROM social_follows WHERE peer=?',peer).n};}
export async function serveFollows(h,req,url,u,readBody){
 const path=url.pathname;
 if(path==='/dm/v1/follows/status'&&req.method==='GET'){
  const peer=id(url.searchParams.get('peer')||u.id);
  return json({...counts(h,peer),following:!!h.first('SELECT 1 FROM social_follows WHERE owner=? AND peer=?',u.id,peer),follows_you:!!h.first('SELECT 1 FROM social_follows WHERE owner=? AND peer=?',peer,u.id),scope:'xingyu'});
 }
 if(path==='/dm/v1/follows/ids'&&req.method==='GET')return json({ids:h.rows('SELECT peer FROM social_follows WHERE owner=? ORDER BY created DESC,peer DESC LIMIT 500',u.id).map(r=>r.peer),authors:h.rows('SELECT f.peer AS id,u.nickname,u.avatar FROM social_follows f LEFT JOIN dm_users u ON u.id=f.peer WHERE f.owner=? ORDER BY f.created DESC,f.peer DESC LIMIT 20',u.id).map(r=>({...r,nickname:r.nickname||('UID '+r.id),avatar:r.avatar||''})),...counts(h,u.id),scope:'xingyu'});
 if(path==='/dm/v1/follows'&&req.method==='GET'){
  const kind=url.searchParams.get('kind')||'following';if(!['following','followers'].includes(kind))fail('列表类型无效');
  const page=Number(url.searchParams.get('page')||1);if(!Number.isSafeInteger(page)||page<1||page>10000)fail('页码无效');
  const followers=kind==='followers',field=followers?'peer':'owner',other=followers?'owner':'peer';
  const total=h.first(`SELECT COUNT(*) AS n FROM social_follows WHERE ${field}=?`,u.id).n;
  const users=h.rows(`SELECT f.${other} AS id,u.nickname,u.avatar,EXISTS(SELECT 1 FROM social_follows b WHERE b.owner=? AND b.peer=f.${other}) AS following,EXISTS(SELECT 1 FROM social_follows b WHERE b.owner=f.${other} AND b.peer=?) AS follows_you FROM social_follows f LEFT JOIN dm_users u ON u.id=f.${other} WHERE f.${field}=? ORDER BY f.created DESC,f.${other} DESC LIMIT 20 OFFSET ?`,u.id,u.id,u.id,(page-1)*20).map(r=>({...r,nickname:r.nickname||('UID '+r.id),avatar:r.avatar||'',following:!!r.following,follows_you:!!r.follows_you}));
  return json({users,page,total,total_pages:Math.max(1,Math.ceil(total/20)),...counts(h,u.id),scope:'xingyu'});
 }
 if(path==='/dm/v1/follows'&&req.method==='POST'){
  const b=await readBody(req);if(Object.keys(b).some(k=>!['peer_id','following'].includes(k))||typeof b.following!=='boolean')fail('关注参数无效');
  const peer=id(b.peer_id);if(peer===u.id)fail('不能关注自己');
  const now=h.clock(),day=Math.floor(now/86400000)*86400000;
  h.ctx.storage.transactionSync(()=>{
   h.validSession(u.token,h.clock());const exists=!!h.first('SELECT 1 FROM social_follows WHERE owner=? AND peer=?',u.id,peer);
   if(exists===b.following)return;
   if(h.count('follow:'+u.id+':'+day)>=500)fail('今日关注操作过多，请明天再试',429);
   if(b.following){
    if(h.first('SELECT 1 FROM dm_blocks WHERE (owner=? AND peer=?) OR (owner=? AND peer=?)',u.id,peer,peer,u.id))fail('暂时无法关注此用户',403);
    if(counts(h,u.id).following_count>=500)fail('最多关注500位作者',429);
    if(h.first('SELECT COUNT(*) AS n FROM social_follows').n>=250000)fail('关注服务暂时已满',503);
    h.sql.exec('INSERT INTO social_follows(owner,peer,created) VALUES(?,?,?)',u.id,peer,now);
   }else h.sql.exec('DELETE FROM social_follows WHERE owner=? AND peer=?',u.id,peer);
   h.increment('follow:'+u.id+':'+day,day);
  });
  return json({ok:true,following:b.following,...counts(h,u.id),scope:'xingyu'});
 }
 fail('接口不存在',404);
}
