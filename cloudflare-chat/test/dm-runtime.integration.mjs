// Disposable local workerd + actual Durable Object SQLite. Does not contact production/site.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,openSync,readFileSync,closeSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(fileURLToPath(new URL('../..',import.meta.url))),cwd=join(root,'cloudflare-chat');
const task=mkdtempSync(join(root,'.toolchain','cf-dm-test-')),port=8792,origin='http://127.0.0.1:'+port;
const config={name:'xingyu-dm-isolated-test',main:join(cwd,'test/dm-runtime.mjs'),compatibility_date:'2026-10-20',durable_objects:{bindings:[{name:'DM',class_name:'TestDmHub'}]},migrations:[{tag:'local-v1',new_sqlite_classes:['TestDmHub']}]};
writeFileSync(join(task,'wrangler.json'),JSON.stringify(config));const log=openSync(join(task,'runtime.log'),'w');
const child=spawn(process.execPath,[join(cwd,'node_modules/wrangler/bin/wrangler.js'),'dev','--config',join(task,'wrangler.json'),'--local','--ip','127.0.0.1','--port',String(port),'--persist-to',join(task,'state')],{cwd,windowsHide:true,stdio:['ignore',log,log],env:{...process.env,CI:'true',WRANGLER_SEND_METRICS:'false',XDG_CONFIG_HOME:join(root,'.toolchain','cloudflare-auth')}});
const pause=ms=>new Promise(r=>setTimeout(r,ms));let checks=0;
async function request(path,{method='GET',token,body}={}){const r=await fetch(origin+'/dm/v1/'+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,body:await r.json()};}
function check(value,expected){assert.deepEqual(value,expected);checks++;}
async function session(id){const r=await request('session',{method:'POST',body:{site_cookie:'local-fake-site-session-'+id,expected_user_id:id}});check(r.status,200);return r.body.token;}
const send=(token,peer,text,nonce=crypto.randomUUID().replaceAll('-',''))=>request('messages',{token,method:'POST',body:{peer_id:peer,text,client_id:nonce}});
try{
  let ready=false;for(let i=0;i<100;i++){if(child.exitCode!==null)break;try{const r=await fetch(origin+'/health');if(r.ok&&(await r.json()).local_test){ready=true;break;}}catch{}await pause(200);}
  if(!ready)throw Error('Local workerd failed: '+readFileSync(join(task,'runtime.log'),'utf8').slice(-3000));
  const a=await session(1),b=await session(2),c=await session(3);
  check((await request('me')).status,401);check((await request('me',{token:a})).body.user.id,1);
  check((await request('session',{method:'POST',body:{site_cookie:'local-fake-site-session-1',expected_user_id:2}})).status,403);
  const nonce='runtime_synthetic_nonce_0001',sent=await send(a,2,'只有双方可见 😀',nonce);check(sent.status,200);check(sent.body.message.sender_id,1);
  check((await send(a,2,'只有双方可见 😀',nonce)).body.message.id,sent.body.message.id);
  check((await send(a,3,'只有双方可见 😀',nonce)).status,409);
  check((await request('messages?peer=1',{token:c})).body.messages,[]);check((await request('conversations',{token:c})).body.conversations,[]);
  check((await request('messages',{token:c,method:'POST',body:{peer_id:2,sender_id:1,text:'伪装',client_id:'runtime_synthetic_nonce_0002'}})).status,400);
  check((await request('read',{token:b,method:'POST',body:{peer_id:1,last_id:sent.body.message.id}})).status,403);
  const received=await request('messages?peer=1',{token:b});check(received.body.messages.map(m=>m.text),['只有双方可见 😀']);
  check((await request('read',{token:b,method:'POST',body:{peer_id:1,last_id:sent.body.message.id}})).status,200);
  check((await request('conversations',{token:b})).body.conversations[0].unread,0);
  check((await request('block',{token:b,method:'POST',body:{peer_id:1,blocked:true}})).status,200);await pause(3100);
  check((await send(a,2,'应被屏蔽')).status,403);check((await request('blocks',{token:b})).body.users[0].id,1);
  check((await request('block',{token:b,method:'POST',body:{peer_id:1,blocked:false}})).status,200);
  check((await send(a,2,'第二条')).status,200);
  const forward=await request('messages?peer=1&after=0&limit=1',{token:b});check(forward.body.has_more,true);check(forward.body.messages[0].id,sent.body.message.id);
  const next=await request('messages?peer=1&after='+forward.body.cursor+'&limit=1',{token:b});check(next.body.messages[0].text,'第二条');check(next.body.has_more,false);
  check((await request('logout',{token:a,method:'POST'})).status,200);check((await request('me',{token:a})).status,401);
  console.log(JSON.stringify({local_only:true,runtime:'workerd',storage:'Durable Object SQLite',checks,public_messages_sent:0,website_requests_sent:0}));
}finally{
  if(child.pid){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else child.kill('SIGTERM');}
  closeSync(log);
}
