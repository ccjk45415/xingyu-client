import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import WebSocket from 'ws';
import {writeFile,mkdir} from 'node:fs/promises';
const base=process.env.CHAT_TEST_URL||'http://127.0.0.1:8787';
if(!base.startsWith('http://127.0.0.1:'))throw Error('Integration/load tests only run against localhost');
const sockets=[];let checks=0;
const check=(condition,message)=>{assert.ok(condition,message);checks++;};
async function api(path,token,body,ip='198.51.100.1'){
  const r=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),'CF-Connecting-IP':ip},body:body?JSON.stringify(body):undefined});
  const data=await r.json();return {status:r.status,data};
}
async function identity(i){const r=await api('/v1/session',null,{nickname:'本机测试'+i},'198.18.'+Math.floor(i/250)+'.'+(i%250+1));check(r.status===200,'create synthetic identity');return r.data;}
async function open(session,channel){
  const ws=new WebSocket(base.replace('http:','ws:')+'/ws?channel='+channel,{headers:{Authorization:'Bearer '+session.token}});sockets.push(ws);ws.events=[];
  ws.on('message',raw=>{if(raw.toString()!=='pong')ws.events.push(JSON.parse(raw));});
  await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);ws.once('unexpected-response',(_q,r)=>reject(new Error('WS HTTP '+r.statusCode)));});
  await until(()=>ws.events.find(e=>e.type==='ready'));return ws;
}
async function until(fn,ms=10000){const start=Date.now();while(Date.now()-start<ms){const r=fn();if(r)return r;await new Promise(r=>setTimeout(r,10));}throw Error('Timed out waiting for expected event');}
const send=(ws,channel,text,id=randomUUID())=>{ws.send(JSON.stringify({type:'send',channel,text,client_id:id}));return id;};
try{
  check((await api('/health')).data.protocol===2,'protocol 2 health');
  const update=await api('/updates/android');check(update.status===200&&update.data.available===true,'update metadata available');
  const artifact=await fetch(base+new URL(update.data.url).pathname);const bytes=new Uint8Array(await artifact.arrayBuffer());check(bytes.length===update.data.size&&createHash('sha256').update(bytes).digest('hex')===update.data.sha256,'published APK matches manifest size and SHA256');
  check((await api('/v1/channels/1/messages')).status===401,'history requires independent bearer');
  check((await api('/v1/session',null,{nickname:'bad\nname'})).status===400,'invalid names rejected');
  const a=await identity(1),b=await identity(2),c=await identity(3);
  const one=await open(a,'1'),same=await open(c,'1'),two=await open(b,'2');
  const nonce=send(one,'1','频道隔离合成测试');
  const first=await until(()=>one.events.find(e=>e.type==='message'&&e.messages[0].client_id===nonce));
  await until(()=>same.events.find(e=>e.type==='message'&&e.messages[0].client_id===nonce));
  check(!two.events.some(e=>e.type==='message'&&e.messages[0].client_id===nonce),'live events isolated across channels');
  const id=first.messages[0].id;send(one,'1','频道隔离合成测试',nonce);
  await until(()=>one.events.filter(e=>e.type==='message'&&e.messages[0].id===id).length===2);
  const history=await api('/v1/channels/1/messages?limit=30',a.token);
  check(history.data.messages.filter(m=>m.client_id===nonce).length===1,'idempotent retry only stores one message');
  check(!(await api('/v1/channels/2/messages',a.token)).data.messages.some(m=>m.id===id),'history isolated');
  const fast=send(one,'1','过快消息');await until(()=>one.events.some(e=>e.type==='error'&&e.client_id===fast));check(true,'server rate limit');
  const switched=await open(a,'2');const conflict=send(switched,'2','频道隔离合成测试',nonce);
  await until(()=>switched.events.find(e=>e.type==='error'&&e.client_id===conflict));check(true,'idempotency key cannot cross channels');
  // Invalid payload cannot spoof the sender or channel.
  same.send(JSON.stringify({type:'send',channel:'2',text:'伪造频道',client_id:randomUUID(),sender:'admin'}));
  await until(()=>same.events.some(e=>e.type==='error'));check(true,'spoofed channel/sender rejected');
  switched.send('ping');await new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(Error('heartbeat failed')),3000);switched.on('message',raw=>{if(raw.toString()==='pong'){clearTimeout(t);resolve();}});});check(true,'hibernation-compatible heartbeat');
  for(const ws of sockets)ws.close();await until(()=>sockets.every(ws=>ws.readyState===WebSocket.CLOSED));sockets.length=0;
  const start=Date.now(),users=[];
  for(let i=0;i<300;i++){const user=await identity(1000+i);users.push(user);await open(user,i%2?'2':'1');}
  check(sockets.length===300&&sockets.every(s=>s.readyState===WebSocket.OPEN),'300 simultaneous local clients');
  const extra=await identity(1400);let denied=false;try{await open(extra,'1');}catch(e){denied=e.message.includes('503');}check(denied,'301st connection rejected');
  const targets=sockets.slice(0,300),sent=[];
  for(let i=0;i<20;i++){const room=i%2?'2':'1';sent.push({room,nonce:send(targets[i],room,'300人本机广播测试 '+i)});}
  await until(()=>targets.every((s,i)=>sent.filter(x=>x.room===(i%2?'2':'1')).every(x=>s.events.some(e=>e.type==='message'&&e.messages[0].client_id===x.nonce))),30000);
  check(targets.every((s,i)=>s.events.filter(e=>e.type==='message').every(e=>e.channel===(i%2?'2':'1'))),'300 clients receive only their channel broadcasts');
  const report={target:'localhost only',ingress:process.env.CHAT_TEST_PAGES?'Pages -> internal service binding':'Worker',transport:'real TCP WebSocket',simultaneous_clients:300,broadcast_messages:20,checks,elapsed_ms:Date.now()-start,public_capacity_tested:false};
  await mkdir('../evidence',{recursive:true});await writeFile('../evidence/'+(process.env.CHAT_TEST_PAGES?'cloudflare-entry-validation.json':'cloudflare-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
}finally{for(const ws of sockets){try{ws.terminate();}catch{}}}
