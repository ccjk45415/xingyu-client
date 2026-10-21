import {test} from 'node:test';import assert from 'node:assert/strict';
import ingress from '../../cloudflare-entry/_worker.mjs';
test('Pages ingress preserves authenticated API and upgrade requests through internal binding',async()=>{
  for(const path of ['/health','/v1/session','/ws?channel=2','/dm/v1/session','/dm/v1/messages?peer=42','/announcements','/announcements/live','/announcements/publish','/media/v1/images?scope=chat&target=1','/media/v1/images/abcdef']){
    const request=new Request('https://example.pages.dev'+path,{headers:{Authorization:'Bearer synthetic',Upgrade:'websocket'}});let seen;
    const response=await ingress.fetch(request,{CHAT_SERVICE:{fetch:r=>{seen=r;return new Response('service');}},ASSETS:{fetch:()=>{throw Error('unexpected asset request');}}});
    assert.equal(await response.text(),'service');assert.equal(seen,request);assert.equal(seen.headers.get('Authorization'),'Bearer synthetic');
  }
});
test('Pages version route reads local static manifest without contacting external hostname',async()=>{
  let path;const r=await ingress.fetch(new Request('https://example.pages.dev/updates/android'),{ASSETS:{fetch:request=>{path=new URL(request.url).pathname;return new Response('{}');}}});assert.equal(path,'/updates/android.json');assert.equal(await r.text(),'{}');
});
