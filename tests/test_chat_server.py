import asyncio
import tempfile
import unittest
import uuid
from pathlib import Path

import httpx
from server import create_app


class ChatTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='xingyu-chat-test-')
        self.database = Path(self.temp.name) / 'chat.sqlite3'
        self.app = create_app(self.database)
        self.http = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url='http://test')
        self.a = (await self.http.post('/v1/session', json={'nickname': '用户甲'})).json()
        self.b = (await self.http.post('/v1/session', json={'nickname': '用户乙'})).json()

    async def asyncTearDown(self):
        await self.http.aclose()
        self.temp.cleanup()

    def auth(self, who=None):
        return {'Authorization': 'Bearer ' + (who or self.a)['token']}

    async def send(self, channel, text, who=None, nonce=None):
        return await self.http.post(f'/v1/channels/{channel}/messages', headers=self.auth(who),
                                    json={'text': text, 'client_id': nonce or str(uuid.uuid4())})

    async def read(self, channel, who=None, **query):
        r = await self.http.get(f'/v1/channels/{channel}/messages', headers=self.auth(who), params=query)
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    async def test_exactly_two_channels(self):
        response = await self.http.get('/v1/channels', headers=self.auth())
        self.assertEqual(response.json()['channels'], [{'id': '1', 'name': '频道一'}, {'id': '2', 'name': '频道二'}])
        self.assertEqual((await self.send('3', '不存在的频道')).status_code, 404)

    async def test_two_people_can_switch_without_cross_channel_messages(self):
        self.assertEqual((await self.send('1', '仅频道一可见', self.a)).status_code, 201)
        self.assertEqual((await self.send('2', '仅频道二可见', self.b)).status_code, 201)
        for who in (self.a, self.b):
            one, two = await self.read('1', who), await self.read('2', who)
            self.assertEqual([m['text'] for m in one['messages']], ['仅频道一可见'])
            self.assertEqual([m['text'] for m in two['messages']], ['仅频道二可见'])
            self.assertTrue(all(m['channel'] == '1' for m in one['messages']))
            self.assertTrue(all(m['channel'] == '2' for m in two['messages']))

    async def test_long_poll_only_wakes_for_its_own_channel(self):
        pending = asyncio.create_task(self.read('1', self.b, after=0, wait=2))
        await asyncio.sleep(.05)
        await self.send('2', '频道二消息')
        await asyncio.sleep(.08)
        self.assertFalse(pending.done(), '另一频道不能唤醒/污染频道一的消息流')
        await self.send('1', '频道一新消息')
        data = await asyncio.wait_for(pending, 1)
        self.assertEqual([m['text'] for m in data['messages']], ['频道一新消息'])

    async def test_retry_is_idempotent_and_cannot_move_between_rooms(self):
        nonce = str(uuid.uuid4())
        first = await self.send('1', '一次发送', nonce=nonce)
        retry = await self.send('1', '一次发送', nonce=nonce)
        self.assertEqual(first.json()['message']['id'], retry.json()['message']['id'])
        self.assertEqual(len((await self.read('1'))['messages']), 1)
        self.assertEqual((await self.send('2', '一次发送', nonce=nonce)).status_code, 409)
        self.assertEqual((await self.send('1', '内容变化', nonce=nonce)).status_code, 409)

    async def test_concurrent_retry_creates_only_one_message(self):
        nonce = str(uuid.uuid4())
        responses = await asyncio.gather(self.send('1', '并发重试', nonce=nonce), self.send('1', '并发重试', nonce=nonce))
        self.assertEqual([r.status_code for r in responses], [201, 201])
        self.assertEqual(responses[0].json()['message']['id'], responses[1].json()['message']['id'])
        self.assertEqual(len((await self.read('1'))['messages']), 1)

    async def test_history_and_incremental_cursors_are_channel_scoped(self):
        a = (await self.send('1', '一A')).json()['message']['id']
        await self.send('2', '二A')
        b = (await self.send('1', '一B')).json()['message']['id']
        await self.send('2', '二B')
        c = (await self.send('1', '一C')).json()['message']['id']
        latest = await self.read('1', limit=1)
        self.assertEqual([m['id'] for m in latest['messages']], [c])
        self.assertTrue(latest['has_older'])
        older = await self.read('1', before=c)
        self.assertEqual([m['id'] for m in older['messages']], [a, b])
        incremental = await self.read('1', after=a, limit=1)
        self.assertEqual([m['id'] for m in incremental['messages']], [b])
        self.assertTrue(incremental['has_newer'])
        self.assertEqual([m['id'] for m in (await self.read('1', after=0))['messages']], [a, b, c])

    async def test_cannot_forge_sender_or_use_website_cookie_as_chat_auth(self):
        unauthorized = await self.http.get('/v1/channels/1/messages', headers={'Cookie': 'website_session=not-a-chat-token'})
        self.assertEqual(unauthorized.status_code, 401)
        forged = await self.http.post('/v1/channels/1/messages', headers=self.auth(self.b),
                                      json={'text': '伪造', 'client_id': str(uuid.uuid4()), 'user_id': self.a['user']['id']})
        self.assertEqual(forged.status_code, 400)
        real = (await self.send('1', '正常消息', self.b)).json()['message']
        self.assertEqual(real['sender'], self.b['user'])

    async def test_expired_identity_is_rejected(self):
        with self.app.state.store.connect() as db:
            db.execute('UPDATE users SET expires_at=0 WHERE id=?', (self.a['user']['id'],))
        self.assertEqual((await self.http.get('/v1/me', headers=self.auth())).status_code, 401)

    async def test_messages_and_sessions_survive_server_restart(self):
        await self.send('2', '持久消息')
        restarted = create_app(self.database)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=restarted), base_url='http://test') as other:
            me = await other.get('/v1/me', headers=self.auth())
            self.assertEqual(me.json()['user'], self.a['user'])
            history = await other.get('/v1/channels/2/messages', headers=self.auth(self.b))
            self.assertEqual(history.json()['messages'][0]['text'], '持久消息')

    async def test_validation_plain_text_and_size(self):
        for text in ('', '  ', 'a' * 1001, '\x00bad'):
            self.assertEqual((await self.send('1', text)).status_code, 400)
        literal = '<b>普通文本</b> & "引号"'
        self.assertEqual((await self.send('1', literal)).json()['message']['text'], literal)
        big = await self.http.post('/v1/channels/1/messages', headers={**self.auth(), 'Content-Type': 'application/json'}, content=b' ' * 17000)
        self.assertEqual(big.status_code, 413)
        both = await self.http.get('/v1/channels/1/messages', headers=self.auth(), params={'before': 9, 'after': 0})
        self.assertEqual(both.status_code, 400)

    async def test_rate_limit_does_not_break_safe_retry(self):
        first_nonce = str(uuid.uuid4())
        for i in range(8):
            self.assertEqual((await self.send('1', '消息' + str(i), nonce=first_nonce if i == 0 else None)).status_code, 201)
        self.assertEqual((await self.send('2', '过快')).status_code, 429)
        self.assertEqual((await self.send('1', '消息0', nonce=first_nonce)).status_code, 201)

    async def test_no_message_timeout_returns_same_room_and_cursor(self):
        empty = await self.read('2', after=0, wait=.05)
        self.assertEqual(empty['channel'], '2')
        self.assertEqual(empty['messages'], [])
        self.assertEqual(empty['cursor'], 0)


if __name__ == '__main__':
    unittest.main()
