import {test} from 'node:test';
import assert from 'node:assert/strict';
import {nickname,text,nonceOK,dayStart,limitReason,roomOK} from '../src/policy.mjs';
test('names and plain text boundaries',()=>{assert.equal(nickname(' 星屿 '),'星屿');assert.throws(()=>nickname('\n'));assert.throws(()=>nickname('a\nb'));assert.throws(()=>nickname('x'.repeat(25)));assert.equal(text('🎈'.repeat(300)).length,600);assert.throws(()=>text('🎈'.repeat(301)));assert.throws(()=>text('\u0000test'));});
test('exactly two channels and idempotency keys',()=>{assert.ok(roomOK('1')&&roomOK('2'));assert.ok(!roomOK('3'));assert.ok(nonceOK('97b77f1e-742b-4806-ae81-c0fdf674a1e1'));assert.ok(!nonceOK('short'));});
test('daily quotas match Cloudflare window at Shanghai 08:00',()=>{const t=Date.parse('2026-10-20T00:00:00Z');assert.equal(dayStart(t),t);assert.equal(dayStart(t-1),t-86400000);});
test('limits apply across rooms by identity and global count',()=>{const now=100000;assert.equal(limitReason({},now),'');for(const input of [{last:99000},{minute:15},{user:200},{all:10000}])assert.ok(limitReason(input,now));});
