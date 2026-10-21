// This synthetic verifier exists only in this local test entry, never in the production Worker.
import {DurableObject} from 'cloudflare:workers';
import {createAiHub} from '../src/ai-core.mjs';
import worker from '../src/worker.js';import {createDmHub} from '../src/dm-core.mjs';
export {ChatHub,VerifiedChatHub,AnnouncementHub} from '../src/worker.js';
export class TestDmHub extends createDmHub(DurableObject,{verify:async(cookie,id)=>{
  const changed=cookie==='synthetic-uid:'+id+':updated';
  if(cookie!=='synthetic-uid:'+id&&!changed)throw Object.assign(new Error('fixture identity mismatch'),{status:403});
  return {id,nickname:(changed?'改名后的用户':'仓库用户')+id,avatar:'https://images.example/'+id+(changed?'-new':'')+'.jpg'};
}}){}
class OldAiBase extends DurableObject{constructor(ctx,env){super(ctx,env);ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS ai_runs(uid INTEGER,id TEXT,hash TEXT,state TEXT,result TEXT,created INTEGER,PRIMARY KEY(uid,id))");}}
export class TestAiDraftHub extends createAiHub(OldAiBase,{infer:async args=>JSON.parse(args.messages[1].content).segments?{response:{translations:JSON.parse(args.messages[1].content).segments}}:({response:JSON.stringify({type:'game',title:'本机测试作品',summary:'公开来源里的作品介绍。',metadata:[],sections:[],tags:['测试'],source_indices:[0]})})}){}
export default worker;
