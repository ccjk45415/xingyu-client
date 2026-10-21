// Disposable local production Worker + actual DO + live subscribers. Never deploys or contacts production.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,openSync,readFileSync,closeSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import WebSocket from 'ws';
const root=resolve(fileURLToPath(new URL('../..',import.meta.url))),cwd=join(root,'cloudflare-chat'),origin='http://127.0.0.1:8793',secret='c'.repeat(64);
const task=mkdtempSync(join(root,'.toolchain','ann-test-')),config=JSON.parse(readFileSync(join(cwd,'wrangler.jsonc'),'utf8'));
config.name='xingyu-announcements-local-test';config.main=join(cwd,'src/worker.js');config.assets.directory=join(cwd,'public');config.vars={ANNOUNCEMENTS_ADMIN_KEY:secret};delete config.$schema;
writeFileSync(join(task,'wrangler.json'),JSON.stringify(config));const log=openSync(join(task,'runtime.log'),'w');
const child=spawn(process.execPath,[join(cwd,'node_modules/wrangler/bin/wrangler.js'),'dev','--config',join(task,'wrangler.json'),'--local','--ip','127.0.0.1','--port','8793','--persist-to',join(task,'state')],{cwd,windowsHide:true,stdio:['ignore',log,log],env:{...process.env,CI:'true',WRANGLER_SEND_METRICS:'false',XDG_CONFIG_HOME:join(root,'.toolchain','cloudflare-auth')}});
const pause=ms=>new Promise(r=>setTimeout(r,ms));let checks=0;const sockets=[];
function check(a,b){assert.deepEqual(a,b);checks++;}
async function request(path='',body=null,token=null){const r=await fetch(origin+'/announcements'+path,{method:body?'POST':'GET',headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined});return {status:r.status,body:await r.json(),headers:r.headers};}
async function until(fn){for(let i=0;i<100;i++){const value=fn();if(value)return value;await pause(20);}throw Error('No live announcement event');}
async function connect(){const ws=new WebSocket(origin.replace('http:','ws:')+'/announcements/live');sockets.push(ws);ws.events=[];ws.on('message',raw=>ws.events.push(raw.toString()==='pong'?'pong':JSON.parse(raw.toString())));await new Promise((yes,no)=>{ws.once('open',yes);ws.once('error',no);});await until(()=>ws.events.length);return ws;}
try{
  let ready=false;for(let i=0;i<100;i++){if(child.exitCode!==null)break;try{if((await fetch(origin+'/health')).ok){ready=true;break;}}catch{}await pause(200);}
  if(!ready)throw Error('Local Worker failed: '+readFileSync(join(task,'runtime.log'),'utf8').slice(-2500));
  const first=await request();check(first.body.revision,0);check(first.body.items,[]);check(first.headers.get('Cache-Control').includes('no-store'),true);
  const a=await connect(),b=await connect();check(a.events[0].data.revision,0);check(b.events[0].data.items,[]);
  const post={base_revision:0,items:[{id:'local-notice',title:'本机公告',content:'立即推送，无需更新APP 😀'}]};
  check((await request('/publish',post)).status,401);check((await request('/publish',post,'d'.repeat(64))).status,401);check(a.events.length,1);
  const before=Date.now();check((await request('/publish',post,secret)).status,200);await until(()=>a.events.length===2&&b.events.length===2);
  check(a.events[1].data.items,post.items);check(b.events[1].data.revision,1);check(Date.now()-before<2000,true);
  check((await request()).body.items,post.items);check((await request('/publish',post,secret)).status,409);
  const later=await connect();check(later.events[0].data.revision,1);check(later.events[0].data.items,post.items);
  a.send('ping');await until(()=>a.events.includes('pong'));check(a.events.at(-1),'pong');
  check((await request('/publish',{base_revision:1,items:[]},secret)).status,200);await until(()=>b.events.length===3);check(b.events[2].data.items,[]);
  // Discovery changes travel on the SAME subscribers without replacing old clients' items.
  const discovery={base_revision:0,title:'本机发现',content:'远程修改发现，不发布客户端'};
  const publishDiscovery=()=>fetch(origin+'/discovery/publish',{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify(discovery)});
  check((await publishDiscovery()).status,200);await until(()=>a.events.length===5&&b.events.length===4);
  check(b.events.at(-1).type,'announcements');check(b.events.at(-1).data.items,[]);check(b.events.at(-1).data.revision,2);check(b.events.at(-1).data.discovery.title,discovery.title);
  check((await (await fetch(origin+'/discovery')).json()).revision,1);check((await publishDiscovery()).status,409);
  check((await request()).body.discovery.content,discovery.content);
  const discoveryReconnect=await connect();check(discoveryReconnect.events[0].data.discovery.content,discovery.content);
  const jdk=process.env.JAVA_HOME||'C:/Program Files/Java/jdk-17',classes=join(task,'classes');
  const compile=spawnSync(join(jdk,'bin/javac.exe'),['-encoding','UTF-8','-d',classes,join(root,'app/src/main/java/moe/cangku/reader/ChatRules.java'),join(root,'app/src/main/java/moe/cangku/reader/ChatSocket.java'),join(root,'tests/AnnouncementWireTest.java')],{windowsHide:true,stdio:'inherit'});assert.equal(compile.status,0);
  const jvm=spawn(join(jdk,'bin/java.exe'),['-ea','-cp',classes,'moe.cangku.reader.AnnouncementWireTest',origin,secret],{windowsHide:true,stdio:'inherit'});assert.equal(await new Promise(r=>jvm.once('exit',r)),0);checks++;
  console.log(JSON.stringify({local_only:true,runtime:'workerd',checks,live_subscribers:4,discovery_shared_connection:true,publications_to_production:0,client_release_changes:0}));
}finally{
  for(const ws of sockets)ws.terminate();
  if(child.pid){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else child.kill('SIGTERM');}closeSync(log);
}
