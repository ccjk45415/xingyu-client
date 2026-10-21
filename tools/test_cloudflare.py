"""Protocol-3 local-only regressions, with a synthetic site verifier. Never deploys."""
import os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
node=shutil.which('node')
if not node:raise SystemExit('Node.js is required')
env=os.environ.copy();env['CHAT_TEST_PAGES']='1' if '--pages' in sys.argv else '0'
files=sorted(str(p.relative_to(ROOT/'cloudflare-chat')) for p in (ROOT/'cloudflare-chat/test').glob('*.test.mjs'))
subprocess.run([node,'--test',*files],cwd=ROOT/'cloudflare-chat',env=env,check=True)
subprocess.run([node,'test/verified-runtime.integration.mjs'],cwd=ROOT/'cloudflare-chat',env=env,check=True)
print('Protocol-3 local tests finished; no production writes or website requests')
