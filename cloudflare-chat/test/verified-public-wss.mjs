// Receives one ephemeral verified token through stdin only. Sends heartbeat, never messages.
import assert from 'node:assert/strict';
import WebSocket from 'ws';
let raw='';for await(const chunk of process.stdin){raw+=chunk;if(raw.length>2048)throw Error('Input too large');}
const {token,uid}=JSON.parse(raw);raw='';assert.match(token,/^[a-f0-9]{64}$/);assert.ok(Number.isSafeInteger(uid));
const origin='https://xingyu-chat-ccjk45415.pages.dev';
for(const channel of ['1','2']){
  const socket=new WebSocket(origin.replace('https:','wss:')+'/ws?channel='+channel,{headers:{Authorization:'Bearer '+token}});
  try{await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('Verified WSS timeout')),20000);
    const fail=e=>{clearTimeout(timer);reject(e);};socket.on('error',fail);
    socket.on('unexpected-response',(_q,r)=>{r.resume();fail(Error('Verified WSS HTTP '+r.statusCode));});
    socket.on('message',data=>{try{
      if(data.toString()==='pong'){clearTimeout(timer);resolve();return;}
      const event=JSON.parse(data.toString());if(event.type!=='ready')return;
      assert.equal(event.channel,channel);assert.equal(event.user.id,uid);assert.equal(typeof event.user.nickname,'string');assert.equal(typeof event.user.avatar,'string');socket.send('ping');
    }catch(e){fail(e);}});
  });}finally{socket.terminate();}
}
console.log(JSON.stringify({wss_channels:['1','2'],certified_identity:'pass',heartbeat:'pass',public_messages_sent:0,tls_certificate_verification:true}));
