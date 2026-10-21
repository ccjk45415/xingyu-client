import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createAnnouncementHub,validateBoard,validateDiscovery,DEFAULT_DISCOVERY} from '../src/announcements-core.mjs';
globalThis.WebSocketRequestResponsePair??=class {constructor(a,b){this.request=a;this.response=b;}};
const SECRET='a'.repeat(64);
function fixture(){
  const db=new DatabaseSync(':memory:'),events=[];const peer={readyState:1,send:raw=>events.push(JSON.parse(raw)),close(){this.readyState=3;}};
  const sql={exec(q,...args){const rows=db.prepare(q).all(...args);return {toArray:()=>rows};}};
  const ctx={storage:{sql,transactionSync(fn){db.exec('BEGIN');try{const v=fn();db.exec('COMMIT');return v;}catch(e){db.exec('ROLLBACK');throw e;}}},getWebSockets:()=>[peer],setWebSocketAutoResponse(value){assert.equal(value.request,'ping');},acceptWebSocket(){}};
  const Hub=createAnnouncementHub(class {}),hub=new Hub(ctx,{ANNOUNCEMENTS_ADMIN_KEY:SECRET});
  const request=async(path='',body=null,token=null)=>hub.fetch(new Request('https://local.invalid/announcements'+path,{method:body?'POST':'GET',headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined}));
  return {db,events,peer,hub,ctx,Hub,request};
}
const item={id:'notice-1',title:'新公告 😀',content:'第一行\n第二行 <不执行HTML>'};
test('public snapshot bypasses caches; unauthorized publishing never changes or broadcasts',async()=>{
  const f=fixture(),r=await f.request();assert.match(r.headers.get('Cache-Control'),/no-store/);assert.deepEqual((await r.json()).items,[]);
  for(const token of [null,'b'.repeat(64)])assert.equal((await f.request('/publish',{base_revision:0,items:[item]},token)).status,401);
  assert.equal(f.events.length,0);assert.equal((await (await f.request()).json()).revision,0);
});
test('publishing immediately broadcasts full content, survives cold reconstruction, and rejects stale writers',async()=>{
  const f=fixture();let r=await f.request('/publish',{base_revision:0,items:[item]},SECRET);assert.equal(r.status,200);assert.equal((await r.json()).revision,1);
  assert.equal(f.events.length,1);assert.equal(f.events[0].type,'announcements');assert.equal(f.events[0].data.items[0].content,item.content);
  const cold=new f.Hub(f.ctx,{ANNOUNCEMENTS_ADMIN_KEY:SECRET});assert.equal(cold.board().revision,1);assert.equal(cold.board().items[0].title,item.title);
  assert.equal((await f.request('/publish',{base_revision:0,items:[]},SECRET)).status,409);assert.equal(f.events.length,1);
  assert.equal((await f.request('/publish',{base_revision:1,items:[]},SECRET)).status,200);assert.deepEqual(f.events[1].data.items,[]);assert.equal(f.events[1].data.revision,2);
  const saved=JSON.stringify(f.db.prepare('SELECT * FROM announcement_board').all());assert.ok(!saved.includes(SECRET));
});
test('board validates unique IDs, Unicode length, control characters and explicit publication version',()=>{
  assert.equal(validateBoard({base_revision:0,items:[{...item,title:'😀'.repeat(80)}]}).items.length,1);
  for(const invalid of [{items:[item]}, {base_revision:-1,items:[]},{base_revision:0,items:[item,item]}, {base_revision:0,items:Array.from({length:11},(_,i)=>({...item,id:'a'+i}))},{base_revision:0,items:[{...item,title:'😀'.repeat(81)}]}, {base_revision:0,items:[{...item,content:'\u0000'}]}, {base_revision:0,items:[{...item,url:'https://elsewhere.invalid'}]}])assert.throws(()=>validateBoard(invalid));
});
test('read-only live clients cannot publish messages, and unconfigured admin secret fails closed',async()=>{
  const f=fixture();f.hub.webSocketMessage(f.peer,'replace the board');assert.equal(f.peer.readyState,3);assert.equal(f.hub.board().revision,0);
  const hub=new f.Hub(f.ctx,{});assert.equal((await hub.fetch(new Request('https://local.invalid/announcements/publish',{method:'POST'}))).status,503);
});

test('discovery shares the live envelope but keeps independent persistence and conflict versions',async()=>{
  const f=fixture();
  const read=async()=>await (await f.hub.fetch(new Request('https://local.invalid/discovery'))).json();
  const publish=async(data,token=SECRET)=>f.hub.fetch(new Request('https://local.invalid/discovery/publish',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(data)}));
  assert.deepEqual(await read(),DEFAULT_DISCOVERY);
  const data={base_revision:0,title:'发现 😀',content:'运营正文\n<只显示文字，不执行HTML>'};
  assert.equal((await publish(data,'b'.repeat(64))).status,401);
  assert.equal((await publish(data)).status,200);
  assert.equal(f.events[0].type,'announcements');
  assert.deepEqual(f.events[0].data.items,[]);
  assert.equal(f.events[0].data.revision,0);
  assert.equal(f.events[0].data.discovery.revision,1);
  assert.equal(f.events[0].data.discovery.content,data.content);
  assert.equal((await publish(data)).status,409);
  const cold=new f.Hub(f.ctx,{ANNOUNCEMENTS_ADMIN_KEY:SECRET});
  assert.deepEqual(cold.discovery(),await read());
  assert.equal((await f.request('/publish',{base_revision:0,items:[item]},SECRET)).status,200);
  assert.equal(cold.discovery().revision,1);
  assert.equal(f.events.at(-1).data.discovery.title,data.title);
  assert.deepEqual(f.events.at(-1).data.items,[item]);
  assert.equal((await f.request()).status,200);
});

test('discovery rejects extra fields, control characters, oversized Unicode and missing revision',()=>{
  const data={base_revision:0,title:'😀'.repeat(80),content:'公开纯文本'};
  assert.equal(validateDiscovery(data).title,data.title);
  for(const bad of [{...data,title:'😀'.repeat(81)},{...data,content:'a'.repeat(1501)},{...data,content:'\u0000'},{...data,base_revision:undefined},{...data,base_revision:0.2},{...data,items:[]}])assert.throws(()=>validateDiscovery(bad));
});
