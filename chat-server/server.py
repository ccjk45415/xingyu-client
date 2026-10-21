"""Two independent chat channels. No website passwords, cookies or account IDs are used."""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
import secrets
import sqlite3
import time
from collections import defaultdict, deque
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse

CHANNELS = ({'id': '1', 'name': '频道一'}, {'id': '2', 'name': '频道二'})
MAX_TEXT = 1000
SESSION_SECONDS = 30 * 24 * 3600


def fail(status: int, message: str):
    raise HTTPException(status, detail=message)


def nickname(value):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= 24:
        fail(400, '聊天昵称需为1–24个字符')
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        fail(400, '昵称不能包含控制字符')
    return value.strip()


def channel_id(value):
    if value not in ('1', '2'):
        fail(404, '频道不存在')
    return value


class Store:
    def __init__(self, path):
        self.path = str(path)
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY, nickname TEXT NOT NULL,
                    token_hash TEXT UNIQUE NOT NULL, expires_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    channel TEXT NOT NULL CHECK(channel IN ('1','2')),
                    user_id TEXT NOT NULL REFERENCES users(id),
                    nickname TEXT NOT NULL, text TEXT NOT NULL,
                    client_id TEXT NOT NULL, created_at REAL NOT NULL,
                    UNIQUE(user_id, client_id)
                );
                CREATE INDEX IF NOT EXISTS messages_channel_cursor ON messages(channel, id);
                CREATE INDEX IF NOT EXISTS messages_user_time ON messages(user_id, created_at);
            ''')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            with db:
                yield db
        finally:
            db.close()

    def session(self, name):
        token = secrets.token_urlsafe(32)
        user = {'id': secrets.token_hex(8), 'nickname': name}
        expires = time.time() + SESSION_SECONDS
        with self.connect() as db:
            db.execute('INSERT INTO users VALUES (?,?,?,?)', (user['id'], name, hashlib.sha256(token.encode()).hexdigest(), expires))
        return {'token': token, 'user': user, 'expires_at': int(expires)}

    def user(self, token):
        if not token or len(token) > 128:
            fail(401, '聊天身份已过期，请重新连接')
        with self.connect() as db:
            row = db.execute('SELECT id,nickname,expires_at FROM users WHERE token_hash=? AND expires_at>?',
                             (hashlib.sha256(token.encode()).hexdigest(), time.time())).fetchone()
        if row is None:
            fail(401, '聊天身份已过期，请重新连接')
        return dict(row)

    @staticmethod
    def message(row):
        return {'id': row['id'], 'channel': row['channel'],
                'sender': {'id': row['user_id'], 'nickname': row['nickname']},
                'text': row['text'], 'client_id': row['client_id'],
                'created_at': datetime.fromtimestamp(row['created_at'], timezone.utc).isoformat(timespec='milliseconds')}

    def read(self, channel, after=None, before=None, limit=50):
        with self.connect() as db:
            if after is not None:
                rows = db.execute('SELECT * FROM messages WHERE channel=? AND id>? ORDER BY id LIMIT ?', (channel, after, limit)).fetchall()
            elif before is not None:
                rows = list(reversed(db.execute('SELECT * FROM messages WHERE channel=? AND id<? ORDER BY id DESC LIMIT ?', (channel, before, limit)).fetchall()))
            else:
                rows = list(reversed(db.execute('SELECT * FROM messages WHERE channel=? ORDER BY id DESC LIMIT ?', (channel, limit)).fetchall()))
            first, last = (rows[0]['id'], rows[-1]['id']) if rows else (0, after or 0)
            older = bool(first and db.execute('SELECT 1 FROM messages WHERE channel=? AND id<? LIMIT 1', (channel, first)).fetchone())
            newer = bool(last and db.execute('SELECT 1 FROM messages WHERE channel=? AND id>? LIMIT 1', (channel, last)).fetchone())
        return {'channel': channel, 'messages': [self.message(r) for r in rows],
                'cursor': last, 'has_older': older, 'has_newer': newer}

    def send(self, user, channel, text, client_id):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            existing = db.execute('SELECT * FROM messages WHERE user_id=? AND client_id=?', (user['id'], client_id)).fetchone()
            if existing is not None:
                if existing['channel'] != channel or existing['text'] != text:
                    fail(409, '重复发送标识与消息不一致，请重新发送')
                return self.message(existing)
            recent = db.execute('SELECT count(*) FROM messages WHERE user_id=? AND created_at>?', (user['id'], time.time() - 10)).fetchone()[0]
            if recent >= 8:
                fail(429, '发送过快，请稍后再试')
            cursor = db.execute('INSERT INTO messages(channel,user_id,nickname,text,client_id,created_at) VALUES (?,?,?,?,?,?)',
                                (channel, user['id'], user['nickname'], text, client_id, time.time()))
            row = db.execute('SELECT * FROM messages WHERE id=?', (cursor.lastrowid,)).fetchone()
            return self.message(row)


async def body(request, allowed):
    if request.headers.get('content-type', '').split(';')[0].strip() != 'application/json':
        fail(415, '请发送JSON数据')
    raw = bytearray()
    async for part in request.stream():
        raw.extend(part)
        if len(raw) > 16384:
            fail(413, '请求内容过大')
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        fail(400, '无效JSON')
    if not isinstance(value, dict) or set(value) - set(allowed):
        fail(400, '请求字段无效')
    return value


def create_app(db_path=None):
    store = Store(db_path or os.getenv('CHAT_DB', str(Path(__file__).parent / 'data' / 'chat.sqlite3')))
    app = FastAPI(title='星屿聊天室', docs_url=None, redoc_url=None, openapi_url=None)
    conditions = {c['id']: asyncio.Condition() for c in CHANNELS}
    registrations = defaultdict(deque)
    pending = defaultdict(int)

    @app.exception_handler(HTTPException)
    async def error(request, exc):
        return JSONResponse({'error': str(exc.detail)}, status_code=exc.status_code,
                            headers={'Cache-Control': 'no-store', **({'Retry-After': '3'} if exc.status_code == 429 else {})})

    @app.middleware('http')
    async def cache_headers(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response

    async def current(request):
        auth = request.headers.get('authorization', '')
        if not auth.startswith('Bearer '):
            fail(401, '请先连接聊天室')
        return await asyncio.to_thread(store.user, auth[7:])

    @app.get('/health')
    async def health():
        return {'service': 'xingyu-chat', 'protocol': 1, 'channel_count': 2}

    @app.post('/v1/session', status_code=201)
    async def session(request: Request):
        value = await body(request, ('nickname',))
        name = nickname(value.get('nickname'))
        ip = request.client.host if request.client else 'unknown'
        now = time.monotonic()
        if len(registrations) > 10000:
            for old in list(registrations):
                if not registrations[old] or registrations[old][-1] < now - 3600:
                    del registrations[old]
        queue = registrations[ip]
        while queue and queue[0] < now - 3600:
            queue.popleft()
        if len(queue) >= 240:
            fail(429, '此网络创建聊天身份过于频繁，请稍后再试')
        queue.append(now)
        return await asyncio.to_thread(store.session, name)

    @app.get('/v1/me')
    async def me(request: Request):
        user = await current(request)
        return {'user': {'id': user['id'], 'nickname': user['nickname']}, 'expires_at': int(user['expires_at'])}

    @app.get('/v1/channels')
    async def channels(request: Request):
        await current(request)
        return {'channels': list(CHANNELS)}

    @app.get('/v1/channels/{channel}/messages')
    async def messages(request: Request, channel: str,
                       after: int | None = Query(None, ge=0), before: int | None = Query(None, ge=1),
                       limit: int = Query(50, ge=1, le=100), wait: float = Query(0, ge=0, le=25)):
        channel_id(channel)
        user = await current(request)
        if after is not None and before is not None:
            fail(400, '不能同时指定前后游标')
        if wait and after is None:
            fail(400, '等待新消息必须指定after游标')
        if pending[user['id']] >= 8:
            fail(429, '同时连接数过多')
        pending[user['id']] += 1
        try:
            condition = conditions[channel]
            async with condition:
                result = await asyncio.to_thread(store.read, channel, after, before, limit)
                if not result['messages'] and wait:
                    deadline = asyncio.get_running_loop().time() + wait
                    while not result['messages']:
                        remaining = deadline - asyncio.get_running_loop().time()
                        if remaining <= 0:
                            break
                        try:
                            await asyncio.wait_for(condition.wait(), min(remaining, 1.0))
                        except TimeoutError:
                            if await request.is_disconnected():
                                break
                            continue
                        result = await asyncio.to_thread(store.read, channel, after, before, limit)
                return result
        finally:
            pending[user['id']] -= 1
            if not pending[user['id']]:
                del pending[user['id']]

    @app.post('/v1/channels/{channel}/messages', status_code=201)
    async def send(request: Request, channel: str):
        channel_id(channel)
        user = await current(request)
        value = await body(request, ('text', 'client_id'))
        text, client_id = value.get('text'), value.get('client_id')
        if not isinstance(text, str) or not 1 <= len(text.strip()) <= MAX_TEXT:
            fail(400, '消息需为1–1000个字符')
        if any(ord(c) < 32 and c not in '\n\t' for c in text) or '\x7f' in text:
            fail(400, '消息不能包含控制字符')
        if not isinstance(client_id, str) or not re.fullmatch(r'[A-Za-z0-9-]{16,64}', client_id):
            fail(400, '发送标识无效')
        message = await asyncio.to_thread(store.send, user, channel, text.strip(), client_id)
        async with conditions[channel]:
            conditions[channel].notify_all()
        return {'channel': channel, 'message': message}

    app.state.store = store
    return app
