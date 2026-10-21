// This synthetic verifier exists only in this local test entry, never in the production Worker.
import {DurableObject} from 'cloudflare:workers';
import worker from '../src/worker.js';import {createDmHub} from '../src/dm-core.mjs';
export {ChatHub,VerifiedChatHub,AnnouncementHub} from '../src/worker.js';
export class TestDmHub extends createDmHub(DurableObject,{verify:async(cookie,id)=>{
  const changed=cookie==='synthetic-uid:'+id+':updated';
  if(cookie!=='synthetic-uid:'+id&&!changed)throw Object.assign(new Error('fixture identity mismatch'),{status:403});
  return {id,nickname:(changed?'改名后的用户':'仓库用户')+id,avatar:'https://images.example/'+id+(changed?'-new':'')+'.jpg'};
}}){}
export default worker;
