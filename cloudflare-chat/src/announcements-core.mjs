const encoder=new TextEncoder();
export const EMPTY_BOARD=Object.freeze({schema:1,revision:0,updated_at:null,items:[]});
export const DEFAULT_DISCOVERY=Object.freeze({schema:1,revision:0,updated_at:null,title:'今天，也有新的心动。',content:'探索灵感 / 珍藏热爱 / 自在阅读'});
export function validateDiscovery(input){
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['title','content','base_revision'].includes(k)))fail('发现格式无效');
  if(!Number.isSafeInteger(input.base_revision)||input.base_revision<0)fail('缺少有效的发现版本');
  const result={base_revision:input.base_revision};
  for(const [key,max] of [['title',80],['content',1500]]){
    if(typeof input[key]!=='string'||!input[key].trim()||[...input[key]].length>max||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u.test(input[key]))fail('发现标题或正文无效');
    result[key]=input[key].trim();
  }
  return result;
}
const headers={'Cache-Control':'no-store, no-cache, max-age=0, must-revalidate','X-Content-Type-Options':'nosniff'};
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
const json=(value,status=200)=>Response.json(value,{status,headers});
export function validateBoard(input){
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['items','base_revision'].includes(k)))fail('公告格式无效');
  if(!Number.isSafeInteger(input.base_revision)||input.base_revision<0)fail('缺少有效的公告版本');
  if(!Array.isArray(input.items)||input.items.length>10)fail('最多保留10条公告');
  const seen=new Set();
  const items=input.items.map(item=>{
    if(!item||typeof item!=='object'||Array.isArray(item)||Object.keys(item).some(k=>!['id','title','content'].includes(k)))fail('公告字段无效');
    if(typeof item.id!=='string'||!/^[a-zA-Z0-9_-]{1,64}$/.test(item.id)||seen.has(item.id))fail('公告ID重复或无效');seen.add(item.id);
    for(const [key,max] of [['title',80],['content',5000]])if(typeof item[key]!=='string'||!item[key].trim()||[...item[key]].length>max||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u.test(item[key]))fail('公告标题或正文无效');
    return {id:item.id,title:item.title.trim(),content:item.content.trim()};
  });return {items,base_revision:input.base_revision};
}
async function authorized(req,secret){
  if(typeof secret!=='string'||!/^[a-f0-9]{64}$/.test(secret))fail('公告发布尚未配置',503);
  const value=req.headers.get('Authorization')||'';if(!/^Bearer [a-f0-9]{64}$/.test(value))fail('无公告发布权限',401);
  const hash=async s=>new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(s)));
  const [a,b]=await Promise.all([hash(value.slice(7)),hash(secret)]);let different=0;for(let i=0;i<a.length;i++)different|=a[i]^b[i];if(different)fail('无公告发布权限',401);
}
async function body(req){
  if(!req.headers.get('Content-Type')?.startsWith('application/json'))fail('请求应为JSON');
  const reader=req.body?.getReader();if(!reader)fail('请求为空');let size=0,chunks=[];
  for(;;){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>220000){await reader.cancel();fail('公告内容过大',413);}chunks.push(part.value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{fail('公告JSON无效');}
}
/** Public, hibernating announcement stream; only the separately held admin secret can publish. */
export function createAnnouncementHub(Base){return class extends Base{
  constructor(ctx,env){
    super(ctx,env);this.ctx=ctx;this.env=env;this.sql=ctx.storage.sql;
    this.sql.exec('CREATE TABLE IF NOT EXISTS announcement_board(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,body TEXT NOT NULL)');
    this.sql.exec('INSERT OR IGNORE INTO announcement_board(id,revision,body) VALUES(1,0,?)',JSON.stringify(EMPTY_BOARD));
    this.sql.exec('CREATE TABLE IF NOT EXISTS discovery_board(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,body TEXT NOT NULL)');
    this.sql.exec('INSERT OR IGNORE INTO discovery_board(id,revision,body) VALUES(1,0,?)',JSON.stringify(DEFAULT_DISCOVERY));
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping','pong'));
  }
  board(){return JSON.parse(this.sql.exec('SELECT body FROM announcement_board WHERE id=1').toArray()[0].body);}
  discovery(){return JSON.parse(this.sql.exec('SELECT body FROM discovery_board WHERE id=1').toArray()[0].body);}
  snapshot(){return {...this.board(),discovery:this.discovery()};}
  // Additive envelope keeps old clients reading their original items and reuses one socket.
  event(board=this.board()){return JSON.stringify({type:'announcements',data:{...board,discovery:this.discovery()}});}
  broadcast(){const event=this.event();for(const peer of this.ctx.getWebSockets()){try{if(peer.readyState===1)peer.send(event);}catch{try{peer.close(1011,'请重新连接');}catch{}}}}
  async fetch(req){try{
    const path=new URL(req.url).pathname;
    if(path==='/announcements'&&req.method==='GET')return json(this.snapshot());
    if(path==='/discovery'&&req.method==='GET')return json(this.discovery());
    if(path==='/announcements/live'&&req.method==='GET'){
      if(req.headers.get('Upgrade')?.toLowerCase()!=='websocket')fail('需要WebSocket连接',426);
      if(this.ctx.getWebSockets().filter(s=>s.readyState===1).length>=1500)fail('公告实时连接繁忙，请稍后重试',503);
      const pair=new WebSocketPair(),client=pair[0],server=pair[1];this.ctx.acceptWebSocket(server);server.send(this.event(this.board()));
      return new Response(null,{status:101,webSocket:client});
    }
    if(path==='/discovery/publish'&&req.method==='POST'){
      await authorized(req,this.env.ANNOUNCEMENTS_ADMIN_KEY);const input=validateDiscovery(await body(req));let next;
      this.ctx.storage.transactionSync(()=>{
        const current=this.discovery();if(current.revision!==input.base_revision)fail('发现已被其他发布操作修改，请重新读取后再发布',409);
        next={schema:1,revision:current.revision+1,updated_at:new Date().toISOString(),title:input.title,content:input.content};
        this.sql.exec('UPDATE discovery_board SET revision=?,body=? WHERE id=1',next.revision,JSON.stringify(next));
      });this.broadcast();return json({ok:true,revision:next.revision});
    }
    if(path==='/announcements/publish'&&req.method==='POST'){
      await authorized(req,this.env.ANNOUNCEMENTS_ADMIN_KEY);const input=validateBoard(await body(req));let board;
      this.ctx.storage.transactionSync(()=>{
        const current=this.board();if(current.revision!==input.base_revision)fail('公告已被其他发布操作修改，请重新读取后再发布',409);
        board={schema:1,revision:current.revision+1,updated_at:new Date().toISOString(),items:input.items};
        this.sql.exec('UPDATE announcement_board SET revision=?,body=? WHERE id=1',board.revision,JSON.stringify(board));
      });
      this.broadcast();
      return json({ok:true,revision:board.revision});
    }
    fail('接口不存在',404);
  }catch(e){return json({error:e.status?e.message:'公告服务暂时不可用'},e.status||503);}}
  webSocketMessage(ws,raw){if(raw==='ping'){try{ws.send('pong');}catch{}}else try{ws.close(1008,'公告连接仅用于接收');}catch{}}
  webSocketClose(ws,code){try{ws.close(code===1005?1000:code);}catch{}}
  webSocketError(ws){try{ws.close(1011,'请重新连接');}catch{}}
};}
