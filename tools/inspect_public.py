import hashlib, json, re, urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
request = urllib.request.Request('https://cangku.moe/login', headers={'User-Agent': 'Mozilla/5.0'})
html = urllib.request.urlopen(request, timeout=30).read().decode()
scripts = re.findall(r'<script[^>]*>([\s\S]*?)</script>', html)
for script in scripts:
    if 'Config' in script:
        print(script[:18000])
print('APP_SHA256', hashlib.sha256((root/'evidence/site-app.js').read_bytes()).hexdigest())
