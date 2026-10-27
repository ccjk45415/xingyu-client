const DAY=86400000;
const fail=(message,status=400)=>{throw Object.assign(new Error(message),{status});};
export const checkinDay=time=>Math.floor(time/DAY); // Official reset: 08:00 Asia/Shanghai = 00:00 UTC.
export function initCheckinEvents(sql){
  sql.exec('CREATE TABLE IF NOT EXISTS checkin_events(uid INTEGER NOT NULL,day INTEGER NOT NULL,time INTEGER NOT NULL,client TEXT NOT NULL,method TEXT NOT NULL,PRIMARY KEY(uid,day))');
  if(!sql.exec('PRAGMA table_info(checkin_events)').toArray().some(c=>c.name==='read_at'))sql.exec('ALTER TABLE checkin_events ADD COLUMN read_at INTEGER');
  sql.exec('CREATE INDEX IF NOT EXISTS checkin_events_time ON checkin_events(time)');
}
export function eventData(row){return {key:`checkin:${row.day}`,time:new Date(row.time).toISOString(),client:row.client,method:row.method,read:row.read_at!=null};}
export function recordCheckinEvent(hub,uid,{time,client,method},now,{cloud=false}={}){
  const timestamp=typeof time==='number'?time:Date.parse(time);
  if(!Number.isFinite(timestamp)||timestamp>now+60000||timestamp<now-7*DAY||
     !(cloud?client==='cloud'&&method==='cloud':['android','windows','macos'].includes(client)&&['manual','open','background'].includes(method)))fail('签到记录无效');
  const day=checkinDay(timestamp);
  hub.sql.exec('INSERT OR IGNORE INTO checkin_events(uid,day,time,client,method) VALUES(?,?,?,?,?)',uid,day,timestamp,client,method);
  hub.sql.exec('DELETE FROM checkin_events WHERE uid=? AND day<?',uid,checkinDay(now)-14);
  return eventData(hub.first('SELECT * FROM checkin_events WHERE uid=? AND day=?',uid,day));
}
export function checkinEvents(hub,uid,now){return hub.rows('SELECT * FROM checkin_events WHERE uid=? AND day>=? ORDER BY day DESC LIMIT 14',uid,checkinDay(now)-14).map(eventData);}

export function readCheckinEvents(hub,uid,keys,now){
  if(!Array.isArray(keys)||keys.length<1||keys.length>60||!keys.every(k=>typeof k==='string'&&/^checkin:[1-9][0-9]{0,15}$/.test(k)))fail('签到已读标记无效');
  for(const key of new Set(keys))hub.sql.exec('UPDATE checkin_events SET read_at=COALESCE(read_at,?) WHERE uid=? AND day=?',now,uid,Number(key.slice(8)));
}
