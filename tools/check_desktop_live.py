"""Run authorized read-only Flutter contract checks; credentials only through stdin/child memory."""
import os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];APP=ROOT/'desktop'
alias=Path('C:/codex-tools/xingyu-desktop')
if alias.is_dir() and alias.resolve()==APP:APP=alias
env=os.environ.copy();env['XINGYU_TEST_AI']='1' if '--ai' in sys.argv else '0';env['XINGYU_TEST_ACCOUNT']=sys.stdin.readline().strip();env['XINGYU_TEST_PASSWORD']=sys.stdin.readline().strip()
if not env['XINGYU_TEST_ACCOUNT'] or not env['XINGYU_TEST_PASSWORD']:raise SystemExit('Credentials required on stdin')
sdk=Path(os.environ.get('FLUTTER_ROOT','C:/codex-tools/flutter'))
result=subprocess.run([str(sdk/'bin/cache/dart-sdk/bin/dart.exe'),str(sdk/'bin/cache/flutter_tools.snapshot'),'test','test/live_contract_test.dart','--reporter','expanded'],cwd=APP,env=env)
env['XINGYU_TEST_ACCOUNT']=env['XINGYU_TEST_PASSWORD']=''
raise SystemExit(result.returncode)
