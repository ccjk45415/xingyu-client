"""Package public source or check the 0.13.6 staged delivery; never publishes.

This tool does structural path exclusion and hash checks. It deliberately does
not read local credentials; live credential-value scanning remains a separate
private publication check.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output'
VERSION = '0.13.6'
SOURCE = OUT / f'Cangku-Xingyu-{VERSION}-source.zip'
PREFIX = 'Cangku-Xingyu/'
PUBLIC = ROOT / 'cloudflare-chat/public'
SKIP_DIRS = {
    '.toolchain', '.git', '.dart_tool', '.wrangler', '.secrets', '.codex',
    '.codex-remote-attachments', 'node_modules', 'build', '__pycache__', '.idea',
    'ephemeral', '.gradle', '.cxx', '.kotlin', '.externalNativeBuild',
    '.symlinks', 'Pods', 'xcuserdata', '.swiftpm', 'output', 'release-chunks',
    'releases',
}
PRIVATE_NAMES = {
    'default.toml', 'credentials-v2.json', 'local.properties', 'key.properties',
    '.flutter-plugins-dependencies', 'GeneratedPluginRegistrant.java',
}
PRIVATE_SUFFIXES = {'.jks', '.keystore', '.sqlite', '.sqlite3', '.db', '.db3',
                    '.pem', '.p12', '.pfx', '.key', '.log', '.iml', '.pyc'}


def safe_path(name, *, source=False):
    path = PurePosixPath(name.replace('\\', '/'))
    assert not path.is_absolute() and '..' not in path.parts and ':' not in name, 'Invalid archive path'
    blocked = set(path.parts) & SKIP_DIRS
    # AGP embeds this public version metadata in every APK; it is not a
    # workspace build directory. Keep source delivery exclusions unchanged.
    if not source and path.as_posix() == 'META-INF/com/android/build/gradle/app-metadata.properties':
        blocked.discard('build')
    assert not blocked, 'Private/cache directory in archive'
    filename = path.name
    assert filename not in PRIVATE_NAMES, 'Private/generated file in archive'
    assert not filename.startswith(('.env', '.dev.vars', '.secrets')), 'Private environment file in archive'
    assert path.suffix.lower() not in PRIVATE_SUFFIXES, 'Private/cache suffix in archive'
    assert not filename.endswith(('.sqlite-wal', '.sqlite-shm', '.sqlite3-wal', '.sqlite3-shm')), 'Database sidecar in archive'
    if source:
        assert path.suffix.lower() not in {'.apk', '.pkg', '.dmg', '.part'}, 'Installer included in source'


def eligible(path):
    relative = path.relative_to(ROOT)
    if path.is_symlink() or set(relative.parts) & SKIP_DIRS:
        return False
    try:
        safe_path(relative.as_posix(), source=True)
    except AssertionError:
        return False
    return path.is_file()


def source_files():
    selected = set()
    # Explicit roots only: local auth, browser profiles, outputs and attachments
    # can never become part of this traversal.
    for name in ['.gitignore', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
                 'CHANGELOG.md', 'build.gradle', 'settings.gradle',
                 'gradle.properties', 'announcements.example.json',
                 'discovery.example.json', 'app/build.gradle']:
        path = ROOT / name
        if eligible(path):
            selected.add(path)
    for name in ['docs', 'tests', 'tools', 'app/src', '.github', 'desktop',
                 'cloudflare-chat/src', 'cloudflare-chat/test']:
        folder = ROOT / name
        if not folder.exists():
            continue
        for base, dirs, files in os.walk(folder, followlinks=False):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not (Path(base)/d).is_symlink()]
            for filename in files:
                path = Path(base) / filename
                if eligible(path):
                    selected.add(path)
    for name in ['chat-server', 'cloudflare-entry']:
        for path in (ROOT / name).iterdir():
            if eligible(path):
                selected.add(path)
    for name in ['package.json', 'package-lock.json', 'wrangler.jsonc', 'README.md']:
        path = ROOT / 'cloudflare-chat' / name
        if eligible(path):
            selected.add(path)
    # Public update schemas/configuration are source data, not binary bundles.
    for base, dirs, files in os.walk(PUBLIC, followlinks=False):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            path = Path(base) / filename
            if eligible(path) and path.suffix.lower() not in {'.zip', '.apk', '.pkg', '.dmg', '.part'}:
                selected.add(path)
    return sorted(selected)


def inspect_archive(path, *, source=False):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Corrupt archive'
        names = archive.namelist()
        for name in names:
            safe_path(name, source=source)
        if source:
            for required in ['LICENSE', 'desktop/pubspec.yaml', 'desktop/pubspec.lock',
                             'desktop/lib/pages/dynamic_templates.dart',
                             'desktop/lib/core/dynamic_template_store.dart',
                             'desktop/lib/pages/quick_feed.dart',
                             'cloudflare-chat/src/dynamic-template-ai.mjs',
                             'docs/RELEASE-0.13.6.md']:
                assert PREFIX + required in names, required
            assert all(name.startswith(PREFIX) for name in names)
        return len(names)


def package_source():
    OUT.mkdir(exist_ok=True)
    files = source_files()
    assert files, 'Source roots are missing'
    with zipfile.ZipFile(SOURCE, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            archive.write(path, PREFIX + path.relative_to(ROOT).as_posix())
    members = inspect_archive(SOURCE, source=True)
    report = record(SOURCE) | {'source_files': members, 'private_paths_excluded': True,
                               'credential_values_scanned': False, 'published': False}
    (ROOT / f'evidence/release-{VERSION}-source.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))


def record(path):
    return {'file': path.name, 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def check(args):
    staged = json.loads((ROOT / f'evidence/release-{VERSION}-staged.json').read_text('utf-8'))
    notes = (ROOT / f'docs/RELEASE-{VERSION}.md').read_text('utf-8').strip()
    assert notes.startswith('本次为测试更新，尚未进行用户实机测试。遇到问题请反馈。')
    assert 'GitHub Issues' in notes and '客户端版本和诊断信息' in notes
    expected = {
        'android': ('Cangku-Xingyu-0.13.6-arm64.apk', '0.13.6', 43),
        'windows': ('Xingyu-Windows-0.7.5-x64.zip', '0.7.5', 33),
        'macos': ('Xingyu-macOS-0.3.5-arm64.pkg', '0.3.5', 10),
    }
    packages = staged['packages']
    assert {p['file'] for p in packages} == {v[0] for v in expected.values()} | {'Xingyu-macOS-0.3.5-arm64.dmg'}
    index = json.loads((ROOT/'cloudflare-entry/release-index.mjs').read_text('utf-8').split('export default ', 1)[1].strip().rstrip(';'))
    for platform, (name, version, build) in expected.items():
        value = json.loads((PUBLIC/f'updates/{platform}.json').read_text('utf-8'))
        assert (value['versionName'], value['versionCode'], value['notes']) == (version, build, notes)
        item = next(p for p in packages if p['file'] == name)
        assert value['url'].endswith('/releases/'+name)
        assert value['size'] == item['bytes'] and value['sha256'] == item['sha256']
    for item in packages:
        path = OUT / item['file']
        assert record(path) == {key: item[key] for key in ['file', 'bytes', 'sha256']}
        if item['file'] in index:
            meta = index[item['file']]
            assert meta['size'] == item['bytes'] and meta['sha256'] == item['sha256']
            digest = hashlib.sha256()
            length = 0
            for chunk in meta['chunks']:
                data = (PUBLIC/chunk.lstrip('/')).read_bytes()
                digest.update(data)
                length += len(data)
            assert length == item['bytes'] and digest.hexdigest() == item['sha256']
        else:
            assert (PUBLIC/'releases'/item['file']).read_bytes() == path.read_bytes()
        if zipfile.is_zipfile(path):
            inspect_archive(path)
        if item['file'].endswith('.zip'):
            with zipfile.ZipFile(path) as archive:
                prefix = 'Xingyu-Windows-0.7.5/'
                value = json.loads(archive.read(prefix+'VERSION.json'))
                assert value['versionName'] == '0.7.5' and value['versionCode'] == 33
                for name in ['Xingyu.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll',
                             'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']:
                    assert prefix+name in archive.namelist(), name
                assert any('sqlite' in name.lower() and name.endswith('.dll') for name in archive.namelist())
    inspect_archive(SOURCE, source=True)
    packages = [*packages, record(SOURCE)]
    sums = ''.join(p['sha256']+'  '+p['file']+'\n' for p in packages)
    (OUT/f'Release-{VERSION}-SHA256SUMS.txt').write_text(sums, encoding='ascii')
    if args.copy_date:
        destination = (ROOT / args.copy_date).resolve()
        assert destination.is_relative_to(OUT.resolve()), 'Delivery copy must stay inside output'
        destination.mkdir(parents=True, exist_ok=True)
        for item in packages:
            shutil.copy2(OUT/item['file'], destination/item['file'])
        shutil.copy2(OUT/f'Release-{VERSION}-SHA256SUMS.txt', destination/f'Release-{VERSION}-SHA256SUMS.txt')
        shutil.copy2(ROOT/f'docs/RELEASE-{VERSION}.md', destination/f'更新说明-{VERSION}.md')
    report = {'stage': 'pre_publication', 'status': 'pass', 'published': False,
              'test_update_warning_present': True, 'packages': packages,
              'chunk_reconstruction_verified': True, 'source_private_paths_excluded': True,
              'credential_values_scanned': False, 'source_commit': args.source_commit,
              'patch_track': 'template-20261101'}
    (ROOT/f'evidence/release-{VERSION}-assets.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('source')
    verify = sub.add_parser('check')
    verify.add_argument('--source-commit', default='')
    verify.add_argument('--copy-date', default='output/2026年10月24日')
    args = parser.parse_args()
    if args.command == 'source':
        package_source()
    else:
        check(args)


if __name__ == '__main__':
    main()
