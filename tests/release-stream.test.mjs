import {test} from 'node:test';
import assert from 'node:assert/strict';
import {releaseResponse} from '../cloudflare-entry/_worker.mjs';
const hash = 'a'.repeat(64);
const names = [`/release-chunks/${hash}/0.part`,`/release-chunks/${hash}/1.part`];
const index = {'client.zip':{size:6,sha256:hash,type:'application/zip',chunks:names}};
const request = (options={}) => new Request('https://example.test/releases/client.zip',options);
test('streams original bytes in order without forwarding cookies or redirects',async()=>{
  const calls=[];
  const env={ASSETS:{fetch:async r=>{calls.push(r);return new Response(new URL(r.url).pathname===names[0]?new Uint8Array([1,2,3]):new Uint8Array([4,5,6]));}}};
  const response=await releaseResponse(request({headers:{Cookie:'private',Authorization:'private'}}),env,index);
  assert.equal(response.status,200);
  assert.equal(response.headers.get('Content-Length'),'6');
  assert.equal(response.headers.get('Content-Disposition'),'attachment; filename="client.zip"');
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[1,2,3,4,5,6]);
  assert.equal(calls.length,2);
  for(const call of calls){assert.equal(call.headers.get('Cookie'),null);assert.equal(call.headers.get('Authorization'),null);}
});
test('HEAD, ETag and method handling do not fetch file chunks',async()=>{
  const env={ASSETS:{fetch:()=>{throw Error('Unexpected fetch');}}};
  assert.equal((await releaseResponse(request({method:'HEAD'}),env,index)).headers.get('Content-Length'),'6');
  assert.equal((await releaseResponse(request({headers:{'If-None-Match':`"${hash}"`}}),env,index)).status,304);
  assert.equal((await releaseResponse(request({method:'POST'}),env,index)).status,405);
});
test('missing chunks fail instead of sending an HTML page as an installer',async()=>{
  assert.equal((await releaseResponse(request(),{ASSETS:{fetch:async()=>new Response('missing',{status:404})}},index)).status,503);
});
test('unknown files and prototype keys stay outside release routing',async()=>{
  for(const name of ['not-found.zip','constructor','__proto__']){
    assert.equal(await releaseResponse(new Request('https://example.test/releases/'+name),{},index),null);
  }
});
