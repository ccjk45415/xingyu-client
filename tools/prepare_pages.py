"""Stage only public release assets and the small Pages ingress."""
import shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
target=ROOT/'.toolchain/pages-public';target.mkdir(parents=True,exist_ok=True)
shutil.copytree(ROOT/'cloudflare-chat/public',target,dirs_exist_ok=True)
shutil.copy2(ROOT/'cloudflare-entry/_worker.mjs',target/'_worker.js')
shutil.copy2(ROOT/'cloudflare-entry/_routes.json',target/'_routes.json')
print('Prepared public Pages ingress assets')
