import test from 'node:test';
import assert from 'node:assert/strict';
import {submissionTaskInput,submissionTaskResult} from '../src/submission-tools.mjs';
const request=(task='command')=>({request_id:crypto.randomUUID(),task,title:'Original',instruction:'修正错别字',segments:[{id:'0',text:'作品介绍'}],sources:[{url:'https://example.com',text:'作者：Example'}]});
const output=()=>({edits:[],metadata:[],notes:[]});
test('task schema refuses foreign keys, duplicate ids and empty proofread sources',()=>{
 assert.equal(submissionTaskInput(request()).task,'command');
 for(const key of ['system','messages','tools','endpoint','model','uid'])assert.throws(()=>submissionTaskInput({...request(),[key]:'injection'}));
 assert.throws(()=>submissionTaskInput({...request(),segments:[{id:'0',text:'a'},{id:'0',text:'b'}]}));
 assert.throws(()=>submissionTaskInput({...request('proofread'),sources:[]}));
});
test('task results reject invented ids, HTML and checker rewrites',()=>{
 assert.throws(()=>submissionTaskResult({...output(),edits:[{id:'1',text:'bad'}]},request()));
 assert.throws(()=>submissionTaskResult({...output(),edits:[{id:'0',text:'<img src=x>'}]},request()));
 assert.throws(()=>submissionTaskResult({...output(),edits:[{id:'0',text:'rewrite'}]},request('preflight')));
 assert.throws(()=>submissionTaskResult({...output(),edits:[{id:'0',text:'rewrite',kind:'h2'}]},request('layout')));
 assert.equal(submissionTaskResult({...output(),edits:[{id:'0',text:'作品介绍',kind:'h2'}]},request('layout')).edits[0].kind,'h2');
});
test('metadata requires quoted evidence and result size stays within builtin budget',()=>{
 const value={label:'作者',value:'Example',source_id:0,evidence:'作者：Example'};
 assert.equal(submissionTaskResult({...output(),metadata:[value]},request('metadata')).metadata.length,1);
 assert.throws(()=>submissionTaskResult({...output(),metadata:[{...value,value:'Invented'}]},request('metadata')));
 assert.throws(()=>submissionTaskResult({...output(),notes:['a'.repeat(401)]},request()));
 assert.throws(()=>submissionTaskResult({...output(),edits:[{id:'0',text:'a'.repeat(2501)}]},request()));
});
