"""Read-only public sticker/website-contract check; never authenticates or uploads."""
import concurrent.futures
import hashlib
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = 'https://cangku.moe'
HEADERS = {'User-Agent': 'Mozilla/5.0 XingyuCommentContract/1', 'Referer': ORIGIN + '/'}


def get(path):
    request = urllib.request.Request(ORIGIN + path, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.status, response.headers.get_content_type(), response.read(3_000_000)


def main():
    _, _, html = get('/')
    page = html.decode('utf-8')
    script = next(path for path in re.findall(r'<script[^>]+src=["\x27]([^"\x27]+)', page)
                  if path.startswith('/assets/web/static/js/app.') and path.endswith('.js'))
    _, _, bundle = get(script)
    source = bundle.decode('utf-8')
    groups = [('cangku_1', 9, 'png'), ('new_paopao', 66, 'png'),
              ('paopao', 33, 'png'), ('qq', 92, 'gif'), ('aru', 122, 'png')]
    assert all(f'src:"{name}"' in source and f'length:{count}' in source for name, count, _ in groups)
    assert '"upload/image"' in source and 'e.append("image",t)' in source
    assert '"max-size":1024' in source and '(a+1)' in source

    def probe(value):
        name, count, ext = value
        rows = []
        for index in [1, count]:
            path = f'/images/stickers/{name}/{index}.{ext}'
            status, mime, data = get(path)
            assert status == 200 and mime == 'image/' + ext
            rows.append({'url': ORIGIN + path, 'status': status, 'mime': mime,
                         'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        return rows

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        resources = [row for group in pool.map(probe, groups) for row in group]
    _, _, options = get('/api/v1/option/list?' + urllib.parse.urlencode({'keys[0]': 'comment_trustedhost_whitelist'}))
    value = json.loads(options)
    assert value['code'] == 0
    report = {'read_only': True, 'comments_or_uploads_written': 0,
              'bundle': ORIGIN + script, 'sha256': hashlib.sha256(bundle).hexdigest(),
              'index': '1 through length', 'resource_probes': resources,
              'paste_upload': {'path': 'upload/image', 'multipart_field': 'image',
                               'params': {}, 'max_bytes': 1_048_576,
                               'comment_content': 'raw URL / raw sticker token'},
              'trustedhost_option': value['data']}
    retained = ROOT / 'evidence/site-app.js'
    if retained.exists():
        report['retained_bundle_matches'] = retained.read_bytes() == bundle
    (ROOT / 'evidence/comment-media-contract.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS public website bundle, sticker resources and comment upload contract; no writes')


if __name__ == '__main__':
    main()
