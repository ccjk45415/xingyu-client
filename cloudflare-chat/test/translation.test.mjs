import test from 'node:test';import assert from 'node:assert/strict';
import {translationInput,translationPlan,translatedSegments,translatedDraft} from '../src/translation.mjs';
import {sourceUrl,draft} from '../src/ai-core.mjs';
const input=()=>({request_id:crypto.randomUUID(),type:'auto',sources:[{url:'https://example.com/work',title:'原作タイトル',cover:'',blocks:[{kind:'h3',text:'紹介'},{kind:'p',text:'A small island.\nFind all three keys.'},{kind:'image',url:'https://cdn.example.com/panel.jpg',alt:'画像の日本語'},{kind:'p',text:'No time limit.'}]}],material:''});
test('v2 preserves exact block and image order with only translation fields, no drafting metadata required',()=>{
 const b=translationInput(input(),sourceUrl),p=translationPlan(b),values=new Map();
 for(const chunk of p.chunks)for(const [id,text] of translatedSegments({translations:chunk.map(v=>({id:v.id,text:v.text}))},chunk))values.set(id,text);
 const out=translatedDraft(b,p,values);assert.equal(out.blocks[2].url,'https://cdn.example.com/panel.jpg');assert.equal(out.blocks[2].alt,'画像の日本語');assert.deepEqual(out.blocks.map(v=>v.kind),['h3','p','image','p']);assert.equal(out.blocks[1].text,'A small island.\nFind all three keys.');assert.deepEqual(out.tags,[]);
});
test('long introductions split losslessly at surrogate boundaries and never silently truncate',()=>{
 const v=input(),original='A'.repeat(799)+'😀'+'文'.repeat(1800);v.sources[0].blocks=[{kind:'p',text:original}];const b=translationInput(v,sourceUrl),p=translationPlan(b),values=new Map();for(const c of p.chunks)for(const v of c)values.set(v.id,v.text);
 assert.equal(translatedDraft(b,p,values).blocks[0].text,original);assert.ok(p.chunks.length>1);
 v.sources[0].blocks=[{kind:'p',text:'文'.repeat(8000)}];assert.throws(()=>translationPlan(translationInput(v,sourceUrl)),/不会被截断/);
});
test('duplicate/missing/foreign translation IDs are rejected and dictionary translations normalize safely',()=>{
 const expected=[{id:'0',text:'a'},{id:'1',text:'b'}];assert.equal(translatedSegments({translations:{0:'甲',1:'乙'}},expected).get('1'),'乙');
 for(const translations of [[],[{id:'0',text:'甲'}],[{id:'0',text:'甲'},{id:'0',text:'乙'}],[{id:'0',text:'甲'},{id:'x',text:'乙'}]])assert.throws(()=>translatedSegments({translations},expected));
});
test('images are source data only, malicious task fields and non-HTTPS pictures are refused',()=>{
 for(const key of ['model','messages','system','tools'])assert.throws(()=>translationInput({...input(),[key]:'override'},sourceUrl));
 const b=input();b.sources[0].blocks.push({kind:'image',url:'javascript:bad()'});assert.throws(()=>translationInput(b,sourceUrl));
});
test('legacy optional metadata objects/null arrays no longer trigger AI draft field error',()=>{
 const old={type:'game',title:'A',summary:'介绍',metadata:{developer:'Example'},sections:null,tags:null,source_indices:[0]};const out=draft(old,{sources:[{url:'https://example.com/work',cover:''}]});assert.deepEqual(out.metadata,[{label:'developer',value:'Example'}]);assert.deepEqual(out.tags,[]);
});
