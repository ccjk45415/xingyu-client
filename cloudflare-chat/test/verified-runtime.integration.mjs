// Entirely local. Synthetic site verifier, production routing + media storage + verified chat code.
import assert from 'node:assert/strict';import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,openSync,readFileSync,closeSync} from 'node:fs';import {resolve,join} from 'node:path';import {fileURLToPath} from 'node:url';import WebSocket from 'ws';
const root=resolve(fileURLToPath(new URL('../..',import.meta.url))),cwd=join(root,'cloudflare-chat'),base='http://127.0.0.1:8794',task=mkdtempSync(join(root,'.toolchain','verified-test-')),pages=process.env.CHAT_TEST_PAGES==='1';
const config=JSON.parse(readFileSync(join(cwd,'wrangler.jsonc'),'utf8'));delete config.$schema;config.name='verified-backend-local';config.main=join(cwd,'test/verified-runtime.mjs');config.assets.directory=join(cwd,'public');config.durable_objects.bindings.find(b=>b.name==='DM').class_name='TestDmHub';delete config.ai;config.durable_objects.bindings.find(b=>b.name==='AI_DRAFTS').class_name='TestAiDraftHub';config.migrations=[{tag:'local-v1',new_sqlite_classes:['ChatHub','TestDmHub','VerifiedChatHub','AnnouncementHub','TestAiDraftHub']}];
writeFileSync(join(task,'backend.json'),JSON.stringify(config));let configs=[join(task,'backend.json')];
if(pages){const entry={name:'verified-entry-local',main:join(root,'cloudflare-entry/_worker.mjs'),compatibility_date:'2026-10-20',services:[{binding:'CHAT_SERVICE',service:config.name}],assets:{directory:join(cwd,'public'),binding:'ASSETS',run_worker_first:config.assets.run_worker_first}};writeFileSync(join(task,'entry.json'),JSON.stringify(entry));configs=[join(task,'entry.json'),...configs];}
const log=openSync(join(task,'runtime.log'),'w'),args=configs.flatMap(c=>['--config',c]),child=spawn(process.execPath,[join(cwd,'node_modules/wrangler/bin/wrangler.js'),'dev',...args,'--local','--ip','127.0.0.1','--port','8794','--persist-to',join(task,'state')],{cwd,windowsHide:true,stdio:['ignore',log,log],env:{...process.env,CI:'true',WRANGLER_SEND_METRICS:'false',XDG_CONFIG_HOME:join(root,'.toolchain/cloudflare-auth')}});
const PHOTO=readFileSync(join(cwd,'test/fixtures/chat-test.jpg')),sockets=[];let checks=0;const check=(a,b)=>{assert.deepEqual(a,b);checks++;},pause=ms=>new Promise(r=>setTimeout(r,ms));
async function api(path,{token,body,bytes,method,nonce=crypto.randomUUID(),ip='198.51.100.1'}={}){const r=await fetch(base+path,{method:method||(body||bytes?'POST':'GET'),headers:{'CF-Connecting-IP':ip,...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),...(bytes?{'Content-Type':'image/jpeg','X-Upload-ID':nonce}:{})},body:body?JSON.stringify(body):bytes});const raw=await r.arrayBuffer();let data;try{data=JSON.parse(new TextDecoder().decode(raw));}catch{data=new Uint8Array(raw);}return {status:r.status,data,headers:r.headers};}
async function session(id){const r=await api('/dm/v1/session',{ip:'198.18.'+Math.floor(id/250)+'.'+(id%250+1),body:{site_cookie:'synthetic-uid:'+id,expected_user_id:id}});check(r.status,200);return r.data.token;}
async function until(fn){for(let i=0;i<150;i++){const result=fn();if(result)return result;await pause(20);}throw Error('Expected event did not arrive');}
async function open(token,channel){const ws=new WebSocket(base.replace('http:','ws:')+'/ws?channel='+channel,{headers:{Authorization:'Bearer '+token}});sockets.push(ws);ws.events=[];ws.on('message',raw=>ws.events.push(raw.toString()==='pong'?'pong':JSON.parse(raw.toString())));await new Promise((yes,no)=>{ws.once('open',yes);ws.once('error',no);ws.once('unexpected-response',(_q,r)=>{r.resume();no(Object.assign(new Error('WS rejected'),{status:r.statusCode}));});});await until(()=>ws.events.length);return ws;}
async function send(ws,channel,text,extra={}){const nonce=extra.client_id||crypto.randomUUID();ws.send(JSON.stringify({type:'send',channel,text,client_id:nonce,...extra}));return until(()=>ws.events.find(e=>e.client_id===nonce||e.messages?.some(m=>m.client_id===nonce)));}
try{
  let ready=false;for(let i=0;i<100;i++){if(child.exitCode!==null)break;try{if((await api('/health')).status===200){ready=true;break;}}catch{}await pause(200);}if(!ready)throw Error(readFileSync(join(task,'runtime.log'),'utf8').slice(-3000));
  check((await api('/health')).data.protocol,3);check((await api('/v1/session',{body:{nickname:'匿名用户'}})).status,410);check((await api('/v1/me',{token:'f'.repeat(64)})).status,401);
  const ta=await session(1),tb=await session(2),tc=await session(3),td=await session(4),a=await open(ta,'1'),b=await open(tb,'1'),c=await open(tc,'2');
  check((await api('/ai/v1/quota')).status,401);
  check((await api('/ai/v1/quota',{token:ta})).data.remaining,3);
  const aiInput={request_id:crypto.randomUUID(),type:'auto',sources:[{url:'https://example.com/work',text:'这是一个来源中的游戏作品介绍。',cover:''}],material:''};
  check((await api('/ai/v1/draft',{token:ta,body:{...aiInput,messages:[]}})).status,400);
  const aiResult=await api('/ai/v1/draft',{token:ta,body:aiInput});check(aiResult.status,200);check(aiResult.data.remaining,2);check(aiResult.data.draft.sources[0].url,'https://example.com/work');
  check((await api('/ai/v1/draft',{token:ta,body:aiInput})).data.cached,true);
  check((await api('/ai/v1/draft',{token:ta,body:{...aiInput,material:'changed'}})).status,409);
  for(let n=0;n<2;n++)check((await api('/ai/v1/draft',{token:ta,body:{...aiInput,request_id:crypto.randomUUID()}})).status,200);
  check((await api('/ai/v1/draft',{token:ta,body:{...aiInput,request_id:crypto.randomUUID()}})).status,429);
  check(a.events[0].user.id,1);check(a.events[0].user.nickname,'仓库用户1');check(a.events[0].user.avatar,'https://images.example/1.jpg');
  const peers=[];for(let i=0;i<297;i++)peers.push(await open(await session(100+i),i%2?'1':'2'));
  let refused=0;try{await open(await session(999),'1');}catch(e){refused=e.status;}check(refused,503);for(const peer of peers)peer.terminate();await pause(150);
  const first=await send(a,'1','认证消息 😀');check(first.type,'message');const original=first.messages[0];check(original.sender.id,1);check(original.sender.nickname,'仓库用户1');check(original.sender.avatar,'https://images.example/1.jpg');
  const reply=await send(b,'1','@仓库用户1(UID:1) 我来回复',{mentions:[1],reply_to_id:original.id});check(reply.messages[0].mentions[0].id,1);check(reply.messages[0].reply_to.id,original.id);check(reply.messages[0].reply_to.sender.id,1);
  const renamed=await api('/dm/v1/profile/sync',{token:ta,body:{site_cookie:'synthetic-uid:1:updated'}});check(renamed.status,200);check(renamed.data.user.nickname,'改名后的用户1');
  check((await api('/v1/me',{token:ta})).data.user.avatar,'https://images.example/1-new.jpg');
  await until(()=>b.events.some(e=>e.type==='profile'&&e.user.id===1));await until(()=>c.events.some(e=>e.type==='profile'&&e.user.id===1));
  check(b.events.find(e=>e.type==='profile'&&e.user.id===1).channel,'1');check(c.events.find(e=>e.type==='profile'&&e.user.id===1).channel,'2');
  const renamedHistory=(await api('/v1/channels/1/messages',{token:tb})).data.messages;
  check(renamedHistory.find(m=>m.id===original.id).sender.nickname,'改名后的用户1');check(renamedHistory.find(m=>m.reply_to).reply_to.sender.nickname,'改名后的用户1');
  check((await send(c,'2','不允许跨频道引用',{reply_to_id:original.id})).type,'error');check(c.events.some(e=>e.messages?.some(m=>m.id===original.id)),false);
  check((await send(c,'2','试图冒充',{sender_id:1,nickname:'伪装'})).type,'error');check((await send(c,'2','UID:1 隐藏艾特',{mentions:[1]})).type,'error');
  const upload=await api('/media/v1/images?scope=chat&target=1',{token:ta,bytes:PHOTO});check(upload.status,200);const photo=upload.data.image;
  check((await api('/media/v1/images/'+photo.id,{token:tb})).status,403);await pause(3100);const imageEvent=await send(a,'1','图片说明',{image_id:photo.id});check(imageEvent.messages[0].image.id,photo.id);
  check(imageEvent.messages[0].sender.nickname,'改名后的用户1');const read=await api('/media/v1/images/'+photo.id,{token:tb});check(read.status,200);check(Buffer.from(read.data).equals(PHOTO),true);check((await api('/media/v1/images/'+photo.id)).status,401);
  check((await send(c,'2','跨频道盗用图片',{image_id:photo.id})).type,'error');
  const privateUpload=await api('/media/v1/images?scope=dm&target=2',{token:ta,bytes:PHOTO});check(privateUpload.status,200);const privateId=privateUpload.data.image.id,nonce=crypto.randomUUID();
  const sent=await api('/dm/v1/messages',{token:ta,body:{peer_id:2,text:'',image_id:privateId,client_id:nonce}});check(sent.status,200);check((await api('/dm/v1/messages',{token:ta,body:{peer_id:2,text:'',image_id:privateId,client_id:nonce}})).data.message.id,sent.data.message.id);
  check((await api('/media/v1/images/'+privateId,{token:tb})).status,200);check((await api('/media/v1/images/'+privateId,{token:tc})).status,403);
  check((await api('/internal/identity',{body:{token_hash:'a'.repeat(64)}})).status===200,false);check((await api('/dm/v1/messages?peer=1',{token:tc})).data.messages,[]);
  const jdk=process.env.JAVA_HOME||'C:/Program Files/Java/jdk-17',classes=join(task,'classes'),compile=spawnSync(join(jdk,'bin/javac.exe'),['-encoding','UTF-8','-d',classes,join(root,'app/src/main/java/moe/cangku/reader/ChatRules.java'),join(root,'app/src/main/java/moe/cangku/reader/ChatSocket.java'),join(root,'tests/VerifiedChatWireTest.java')],{windowsHide:true,stdio:'inherit'});check(compile.status,0);
  const jvm=spawn(join(jdk,'bin/java.exe'),['-ea','-cp',classes,'VerifiedChatWireTest',base,td],{windowsHide:true,stdio:'inherit'});check(await new Promise(r=>jvm.once('exit',r)),0);
  if(process.env.CHAT_TEST_FLUTTER==='1'){
    const sdk=process.env.FLUTTER_ROOT||'C:/codex-tools/flutter',flutter=spawn(join(sdk,'bin/cache/dart-sdk/bin/dart.exe'),[join(sdk,'bin/cache/flutter_tools.snapshot'),'test','test/local_transport_test.dart','--reporter','expanded'],{cwd:process.env.XINGYU_DESKTOP_TEST_DIR||join(root,'desktop'),windowsHide:true,stdio:'inherit',env:{...process.env,CHAT_TEST_ORIGIN:base,CHAT_TEST_ROOT:root,CHAT_TEST_A:await session(1001),CHAT_TEST_B:await session(1002)}});
    check(await new Promise(r=>flutter.once('exit',r)),0);
  }
  check((await api('/dm/v1/logout',{token:ta,body:{}})).status,200);a.send(JSON.stringify({type:'send',channel:'1',text:'撤销后不能再发',client_id:crypto.randomUUID()}));await until(()=>a.readyState===WebSocket.CLOSED);check((await api('/v1/channels/1/messages',{token:ta})).status,401);
  const report={local_only:true,ingress:pages?'Pages -> internal binding':'Worker direct',protocol:3,verified_capacity:300,checks,images:'chat + private ACL passed',mentions_and_replies:'passed',production_messages_sent:0,real_website_requests:0};writeFileSync(join(root,'evidence/verified-media-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
}finally{for(const ws of sockets)ws.terminate();if(child.pid){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else child.kill('SIGTERM');}closeSync(log);}
