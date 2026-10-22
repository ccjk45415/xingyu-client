// Disposable local workerd + actual Durable Object SQLite. Does not contact production/site.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,openSync,readFileSync,closeSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(fileURLToPath(new URL('../..',import.meta.url))),cwd=join(root,'cloudflare-chat');
const task=mkdtempSync(join(root,'.toolchain','cf-follow-test-')),port=8795,origin='http://127.0.0.1:'+port;
const config={name:'xingyu-follow-isolated-test',main:join(cwd,'test/dm-runtime.mjs'),compatibility_date:'2026-10-20',durable_objects:{bindings:[{name:'DM',class_name:'TestDmHub'}]},migrations:[{tag:'local-v1',new_sqlite_classes:['TestDmHub']}]};
writeFileSync(join(task,'wrangler.json'),JSON.stringify(config));const log=openSync(join(task,'runtime.log'),'w');
const child=spawn(process.execPath,[join(cwd,'node_modules/wrangler/bin/wrangler.js'),'dev','--config',join(task,'wrangler.json'),'--local','--ip','127.0.0.1','--port',String(port),'--persist-to',join(task,'state')],{cwd,windowsHide:true,stdio:['ignore',log,log],env:{...process.env,CI:'true',WRANGLER_SEND_METRICS:'false',XDG_CONFIG_HOME:join(root,'.toolchain','cloudflare-auth')}});
const pause=ms=>new Promise(r=>setTimeout(r,ms));let checks=0;
async function request(path,{method='GET',token,body}={}){const r=await fetch(origin+'/dm/v1/'+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,body:await r.json()};}
function check(value,expected){assert.deepEqual(value,expected);checks++;}
async function session(id){const r=await request('session',{method:'POST',body:{site_cookie:'local-fake-site-session-'+id,expected_user_id:id}});check(r.status,200);return r.body.token;}
const send=(token,peer,text,nonce=crypto.randomUUID().replaceAll('-',''))=>request('messages',{token,method:'POST',body:{peer_id:peer,text,client_id:nonce}});
try{
 let ready=false;for(let i=0;i<100;i++){try{const r=await fetch(origin+'/health');if(r.ok&&(await r.json()).local_test){ready=true;break;}}catch{}await pause(200);}
 if(!ready)throw Error('Local workerd failed: '+readFileSync(join(task,'runtime.log'),'utf8').slice(-2000));
 const a=await session(1),b=await session(2),c=await session(3);
 const follow=(token,peer,following,extra={})=>request('follows',{token,method:'POST',body:{peer_id:peer,following,...extra}});
 check((await request('follows')).status,401);
 check((await follow(a,1,true)).status,400);
 check((await follow(a,2,true,{owner:3})).status,400);
 check((await follow(a,2,'true')).status,400);
 check((await follow(a,-1,true)).status,400);
 check((await follow(a,2,true)).status,200);
 check((await follow(a,2,true)).body.following_count,1);
 check((await request('follows/status?peer=2',{token:a})).body.following,true);
 check((await request('follows?kind=followers',{token:b})).body.users.map(x=>x.id),[1]);
 check((await request('follows?kind=following',{token:c})).body.users,[]);
 check((await request('follows?kind=following&owner=1',{token:c})).body.users,[]);
 check((await follow(b,1,true)).status,200);
 const mutual=(await request('follows?kind=followers',{token:a})).body.users[0];check(mutual.id,2);check(mutual.following,true);check(mutual.follows_you,true);
 // Authors need not enroll in this app before being followed. No supplied nickname is trusted.
 check((await follow(a,999,true)).status,200);
 const ids=(await request('follows/ids',{token:a})).body;check(ids.ids.includes(999),true);check(ids.following_count,2);check(ids.authors.find(x=>x.id===999).nickname,'UID 999');
 check((await request('follows?kind=invalid',{token:a})).status,400);check((await request('follows?page=0',{token:a})).status,400);
 check((await follow(a,2,false)).status,200);check((await follow(a,2,false)).body.following_count,1);
 check((await request('follows?kind=followers',{token:b})).body.total,0);
 check((await request('follows?kind=followers',{token:a})).body.total,1);
 // Existing session and DM read behavior stays operational.
 check((await request('me',{token:a})).body.user.id,1);
 check((await request('messages?peer=2',{token:a})).status,200);
 check((await request('logout',{token:c,method:'POST'})).status,200);
 check((await follow(c,1,true)).status,401);
 console.log(JSON.stringify({local_only:true,runtime:'workerd',storage:'actual Durable Object SQLite',checks,website_requests:0,production_mutations:0}));
}finally{
 if(child.pid){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else child.kill('SIGTERM');}closeSync(log);
}
