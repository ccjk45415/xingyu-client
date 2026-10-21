"""Project-local official Wrangler commands. OAuth credentials stay in .toolchain/."""
import os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NODE=shutil.which('node')
if not NODE:raise SystemExit('Node.js is required')
env=os.environ.copy()
env['PATH']=str(Path(NODE).parent)+os.pathsep+env.get('PATH','')
env['XDG_CONFIG_HOME']=str(ROOT/'.toolchain'/'cloudflare-auth')
env['npm_config_cache']=str(ROOT/'.toolchain'/'npm-cache')
env['WRANGLER_SEND_METRICS']='false'
env['CI']='true'
args=sys.argv[1:]
if not args:raise SystemExit('Usage: python tools/cloudflare.py install|login|whoami|dev|deploy|...')
if args[0]=='install':
    cmd=[NODE,str(ROOT/'.toolchain/npm/package/bin/npm-cli.js'),'install','--no-audit','--no-fund']
else:
    cmd=[NODE,str(ROOT/'cloudflare-chat/node_modules/wrangler/bin/wrangler.js')]+args
raise SystemExit(subprocess.call(cmd,cwd=ROOT/'cloudflare-chat',env=env))
