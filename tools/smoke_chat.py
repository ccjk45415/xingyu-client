"""Start a temporary localhost service, exercise two real HTTP clients, then stop it."""
import concurrent.futures
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

root=Path(__file__).resolve().parents[1]
env=os.environ.copy()
env['PYTHONPATH']=os.pathsep.join([str(root/'.toolchain/chatdeps'),str(root/'chat-server')])
with socket.socket() as available:
    available.bind(('127.0.0.1',0));port=available.getsockname()[1]
base=f'http://127.0.0.1:{port}'
checks=[]
def request(path,payload=None,token=None):
    headers={'Accept':'application/json'}
    if payload is not None:headers['Content-Type']='application/json'
    if token:headers['Authorization']='Bearer '+token
    r=urllib.request.Request(base+path,headers=headers,data=None if payload is None else json.dumps(payload).encode())
    with urllib.request.urlopen(r,timeout=6) as response:return json.load(response)
def send(room,text,session,nonce=None):return request(f'/v1/channels/{room}/messages',{'text':text,'client_id':nonce or str(uuid.uuid4())},session['token'])
with tempfile.TemporaryDirectory(prefix='chat-smoke-',dir=root/'.toolchain') as temp:
    env['CHAT_DB']=str(Path(temp)/'chat.sqlite3')
    process=subprocess.Popen([sys.executable,'-m','uvicorn','server:create_app','--factory','--host','127.0.0.1','--port',str(port),'--workers','1','--no-access-log','--log-level','warning'],cwd=root/'chat-server',env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+12
        while True:
            try:health=request('/health');break
            except (OSError,ValueError):
                if process.poll() is not None:raise RuntimeError(process.stdout.read().decode(errors='replace'))
                if time.monotonic()>deadline:raise RuntimeError('Server startup timed out')
                time.sleep(.1)
        assert health['channel_count']==2;checks.append('live TCP health and protocol')
        a=request('/v1/session',{'nickname':'联调用户甲'});b=request('/v1/session',{'nickname':'联调用户乙'})
        assert a['user']['id']!=b['user']['id'];checks.append('two independent client identities')
        nonce=str(uuid.uuid4());first=send('1','仅频道一',a,nonce)
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            waiting=pool.submit(request,'/v1/channels/2/messages?after=0&wait=2',None,a['token'])
            time.sleep(.1);send('1','频道一第二条',b);time.sleep(.1)
            assert not waiting.done();checks.append('other channel does not wake long poll')
            send('2','仅频道二',b)
            assert [m['text'] for m in waiting.result(timeout=3)['messages']]==['仅频道二'];checks.append('real-time same-channel delivery')
        for person in (a,b):
            one=request('/v1/channels/1/messages',token=person['token']);two=request('/v1/channels/2/messages',token=person['token'])
            assert len(one['messages'])==2 and all(m['channel']=='1' for m in one['messages'])
            assert len(two['messages'])==1 and all(m['channel']=='2' for m in two['messages'])
        checks.append('both clients switch freely with isolated history')
        assert send('1','仅频道一',a,nonce)['message']['id']==first['message']['id'];checks.append('idempotent retry over HTTP')
        try:request('/v1/channels/1/messages')
        except urllib.error.HTTPError as e:assert e.code==401
        else:raise AssertionError('Unauthenticated request accepted')
        checks.append('unauthenticated requests rejected')
        print('PASS live HTTP smoke:',len(checks),'checks')
    finally:
        process.terminate()
        try:process.wait(timeout=6)
        except subprocess.TimeoutExpired:process.kill();process.wait(timeout=3)
        if process.stdout:process.stdout.close()
(root/'evidence/chat-validation.json').write_text(json.dumps({'transport':'HTTP on temporary 127.0.0.1 listener','checks':checks,'public_deployment':False,'android_device_test':False},ensure_ascii=False,indent=2),encoding='utf-8')
