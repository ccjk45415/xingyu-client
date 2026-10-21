import {test} from 'node:test';import assert from 'node:assert/strict';import {DatabaseSync} from 'node:sqlite';import {readFileSync} from 'node:fs';
import {createDmHub} from '../src/dm-core.mjs';import {jpegSize,MEDIA_LIMITS} from '../src/media.mjs';
const PHOTO=new Uint8Array(readFileSync(new URL('./fixtures/chat-test.jpg',import.meta.url)));
function fixture(){
  const db=new DatabaseSync(':memory:');let now=Date.UTC(2026,9,21),alarm=null;
  const sql={exec(q,...args){const rows=db.prepare(q).all(...args);return {toArray:()=>rows};}};
  const ctx={storage:{sql,transactionSync(fn){db.exec('BEGIN');try{const r=fn();db.exec('COMMIT');return r;}catch(e){db.exec('ROLLBACK');throw e;}},getAlarm:async()=>alarm,setAlarm:async n=>{alarm=n;}}};
  const Hub=createDmHub(class {},{clock:()=>now,verify:async(_,id)=>({id,nickname:'作者'+id,avatar:'https://images.example/'+id+'.jpg'})}),hub=new Hub(ctx,{});
  async function req(path,{token,body,bytes,method,upload='upload_'+crypto.randomUUID().replaceAll('-','')}={}){return hub.fetch(new Request('https://local.invalid'+path,{method:method||(body||bytes?'POST':'GET'),headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),...(bytes?{'Content-Type':'image/jpeg','X-Upload-ID':upload}:{})},body:body?JSON.stringify(body):bytes}));}
  const session=async id=>(await (await req('/dm/v1/session',{body:{site_cookie:'synthetic-'+id,expected_user_id:id}})).json()).token;
  return {db,hub,req,session,advance:t=>now+=t};
}
test('JPEG size, byte signature and metadata boundaries reject non-images and location metadata',()=>{
  assert.deepEqual(jpegSize(PHOTO),{width:32,height:24});assert.throws(()=>jpegSize(new TextEncoder().encode('<svg onload=evil>')));
  const oversized=PHOTO.slice();const sof=oversized.findIndex((b,i)=>b===255&&[192,193,194].includes(oversized[i+1]));assert.ok(sof>0);oversized[sof+5]=0x7f;oversized[sof+6]=0xff;assert.throws(()=>jpegSize(oversized));
  const exif=new Uint8Array(PHOTO.length+6);exif.set(PHOTO.slice(0,2));exif.set([255,225,0,4,0,0],2);exif.set(PHOTO.slice(2),8);assert.throws(()=>jpegSize(exif));
});
test('private attachment stays sender-only until sent, then only both parties can read; sender spoof and image reuse fail',async()=>{
  const f=fixture(),a=await f.session(1),b=await f.session(2),c=await f.session(3),upload='a_valid_upload_nonce_0001';
  const send=async(peer,image_id,client_id='a_valid_message_nonce_0001')=>f.req('/dm/v1/messages',{token:a,body:{peer_id:peer,text:'',image_id,client_id}});
  const post=await f.req('/media/v1/images?scope=dm&target=2',{token:a,bytes:PHOTO,upload});assert.equal(post.status,200);const image=(await post.json()).image;
  assert.equal((await f.req('/media/v1/images/'+image.id,{token:b})).status,403);assert.equal((await send(2,image.id)).status,200);assert.equal((await send(2,image.id)).status,200);
  const received=await f.req('/media/v1/images/'+image.id,{token:b});assert.equal(received.status,200);assert.match(received.headers.get('Cache-Control'),/no-store/);assert.deepEqual(new Uint8Array(await received.arrayBuffer()),PHOTO);
  assert.equal((await f.req('/media/v1/images/'+image.id,{token:c})).status,403);assert.equal((await f.req('/media/v1/images/'+image.id)).status,401);f.advance(3100);assert.equal((await send(3,image.id,'a_valid_message_nonce_0002')).status,403);
  f.advance(3100);assert.equal((await send(2,image.id,'a_valid_message_nonce_0003')).status,409);
  const history=await (await f.req('/dm/v1/messages?peer=1',{token:b})).json();assert.equal(history.messages[0].image.id,image.id);assert.equal(history.messages[0].text,'');
});
test('upload retries bind bytes and target; size, quota, expiration and garbage cleanup are bounded',async()=>{
  const f=fixture(),a=await f.session(1);await f.session(2);const upload='upload_retry_nonce_0001';
  const r=await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:PHOTO,upload}),id=(await r.json()).image.id;
  assert.equal((await (await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:PHOTO,upload})).json()).image.id,id);
  assert.equal((await f.req('/media/v1/images?scope=chat&target=2',{token:a,bytes:PHOTO,upload})).status,409);
  assert.equal((await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:new Uint8Array(MEDIA_LIMITS.bytes+1)})).status,413);
  assert.equal((await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:new TextEncoder().encode('<html>bad</html>')})).status,400);
  f.advance(3600001);assert.equal((await f.req('/media/v1/images/'+id,{token:a})).status,404);await f.hub.alarm();assert.equal(f.db.prepare('SELECT COUNT(*) n FROM dm_media').get().n,0);
  for(let i=1;i<MEDIA_LIMITS.user_day;i++)assert.equal((await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:PHOTO})).status,200);
  assert.equal((await f.req('/media/v1/images?scope=chat&target=1',{token:a,bytes:PHOTO})).status,429);
});
