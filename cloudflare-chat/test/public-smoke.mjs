// Read-only production checks: no chat messages, anonymous enrollments or board writes.
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import {writeFile} from 'node:fs/promises';
const origin='https://xingyu-chat-ccjk45415.pages.dev';
let socket;
try {
  const health=await (await fetch(origin+'/health')).json();assert.equal(health.protocol,3);
  assert.equal((await fetch(origin+'/v1/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({nickname:'disabled'})})).status,410);
  assert.equal((await fetch(origin+'/v1/me')).status,401);
  assert.equal((await fetch(origin+'/media/v1/images/'+'0'.repeat(32))).status,401);
  const response=await fetch(origin+'/announcements');assert.equal(response.status,200);assert.match(response.headers.get('cache-control'),/no-store/);
  const board=await response.json();assert.equal(board.schema,1);assert.ok(Array.isArray(board.items));
  assert.equal((await fetch(origin+'/announcements/publish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:[],base_revision:-1})})).status,401);
  socket=new WebSocket(origin.replace('https:','wss:')+'/announcements/live');
  await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('Announcement WSS timeout')),20000);
    const fail=e=>{clearTimeout(timer);reject(e);};socket.on('error',fail);
    socket.on('unexpected-response',(_q,r)=>{r.resume();fail(Error('WSS HTTP '+r.statusCode));});
    socket.on('message',raw=>{try{
      if(raw.toString()==='pong'){clearTimeout(timer);resolve();return;}
      const event=JSON.parse(raw.toString());assert.equal(event.type,'announcements');assert.equal(event.data.schema,1);assert.ok(event.data.revision>=board.revision);socket.send('ping');
    }catch(e){fail(e);}});
  });
  const report={origin,protocol:3,anonymous_chat_disabled:true,unauthenticated_media_rejected:true,announcement_snapshot_and_heartbeat:'pass',announcement_publish_requires_secret:true,tls_certificate_verification:true,public_messages_sent:0,public_announcements_written:0};
  await writeFile(new URL('../../evidence/cloudflare-public.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
}finally{socket?.terminate();}
