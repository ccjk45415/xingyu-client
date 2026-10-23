"""Build Apple Silicon installers on macOS. Never publishes or changes update feeds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'desktop'
VERSION, BUILD = '0.1.1', '2'


def run(argv, **kwargs):
    return subprocess.run([str(v) for v in argv], cwd=APP, check=True, **kwargs)


def check_source():
    for name in ['DebugProfile', 'Release']:
        data = plistlib.loads((APP / f'macos/Runner/{name}.entitlements').read_bytes())
        assert data['com.apple.security.network.client'] is True
        assert data['com.apple.security.app-sandbox'] is False
    info = plistlib.loads((APP / 'macos/Runner/Info.plist').read_bytes())
    assert info['CFBundleExecutable'] == '$(EXECUTABLE_NAME)'
    config = (APP / 'macos/Runner/Configs/AppInfo.xcconfig').read_text()
    assert 'PRODUCT_BUNDLE_IDENTIFIER = moe.cangku.xingyu.macos' in config
    assert 'ARCHS = arm64' in config
    assert 'DEVELOPMENT_TEAM =\n' in config
    bridge = (APP / 'macos/Runner/MainFlutterWindow.swift').read_text(encoding='utf-8-sig')
    assert all(v in bridge for v in ['SecItemCopyMatching', 'SecItemUpdate', 'SecItemAdd', 'SecItemDelete',
                                    'image_clipboard', 'secure_storage', 'CFNetworkCopySystemProxySettings'])
    assert 'NSAllowsArbitraryLoads' not in info
    print('macOS source configuration checked; native compilation is not implied.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--skip-tests', action='store_true')
    parser.add_argument('--native-check', action='store_true')
    args = parser.parse_args()
    check_source()
    if args.check_only:
        return
    if sys.platform != 'darwin':
        raise SystemExit('macOS installers require a Mac with Xcode. No fake installer was produced.')
    if run(['uname', '-m'], capture_output=True, text=True).stdout.strip() != 'arm64':
        raise SystemExit('Use an Apple Silicon Mac / standard arm64 macOS runner for this test build.')
    flutter = shutil.which('flutter')
    if not flutter:
        raise SystemExit('Flutter SDK is not on PATH. Required Flutter >=3.47 / Dart >=3.13.')
    run(['xcodebuild', '-version'])
    if not shutil.which('pod'):
        raise SystemExit('Install CocoaPods before building; AVIF and native video plugins require it.')
    run([flutter, 'pub', 'get'])
    run([flutter, 'analyze', 'lib', 'test/macos_platform_test.dart', 'test/updates_test.dart'])
    if not args.skip_tests:
        run([flutter, 'test', '--no-pub', 'test/macos_platform_test.dart', 'test/core_test.dart', 'test/updates_test.dart'])
    run([flutter, 'build', 'macos', '--release', f'--build-name={VERSION}', f'--build-number={BUILD}'])
    bundle = APP / 'build/macos/Build/Products/Release/Xingyu.app'
    binary = bundle / 'Contents/MacOS/Xingyu'
    if not binary.is_file():
        raise SystemExit('Native Xingyu.app bundle is missing.')
    architectures = run(['lipo', '-archs', binary], capture_output=True, text=True).stdout.split()
    assert architectures == ['arm64'], architectures
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'moe.cangku.xingyu.macos'
    assert info['CFBundleShortVersionString'] == VERSION
    assert str(info['CFBundleVersion']) == BUILD
    resources = bundle / 'Contents/Resources'
    shutil.copy2(ROOT / 'docs/THIRD_PARTY_MEDIA.md', resources / 'THIRD_PARTY_MEDIA.md')
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE.xingyu.txt')
    # All nested native frameworks are signed by Xcode/Flutter; adding notices
    # only changes the outer bundle, so re-sign it without disabling verification.
    run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--entitlements',
         APP / 'macos/Runner/Release.entitlements', bundle])
    run(['codesign', '--verify', '--deep', '--strict', bundle])
    report = {'platform': 'macos-arm64', 'version': VERSION, 'build': int(BUILD),
              'signature': 'ad-hoc-local-test', 'apple_notarized': False, 'published': False}
    if args.native_check:
        result = run([binary, '--self-check', '--offline'], capture_output=True, text=True, timeout=60)
        native = next((json.loads(line) for line in result.stdout.splitlines()
                       if line.startswith('{') and 'macos_native_engine' in line), None)
        assert native and native['macos_native_engine'] == 'pass' and native['keychain_round_trip'] == 'pass'
        report['native_self_check'] = native
    out = ROOT / 'output'
    out.mkdir(exist_ok=True)
    package = out / f'Xingyu-macOS-{VERSION}-arm64.pkg'
    run(['pkgbuild', '--component', bundle, '--identifier', 'moe.cangku.xingyu.macos.installer',
         '--version', VERSION, '--install-location', '/Applications', '--ownership', 'recommended', package])
    image = out / f'Xingyu-macOS-{VERSION}-arm64.dmg'
    with tempfile.TemporaryDirectory(prefix='xingyu-macos-package-') as folder:
        stage = Path(folder)
        run(['ditto', bundle, stage / 'Xingyu.app'])
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (stage / '安装说明.txt').write_text(
            '星屿 macOS Apple Silicon\n\n拖动 Xingyu.app 到 Applications 安装。'
            '也可使用同版本 PKG 安装器。\n本包为本机测试签名，尚未做 Apple Developer ID 签名与公证；'
            '首次打开时 macOS 可能要求在“系统设置 → 隐私与安全性”确认。\n'
            '不需要关闭 Gatekeeper、关闭系统保护或提供 Apple ID 密码。\n', encoding='utf-8')
        run(['hdiutil', 'create', '-volname', '星屿', '-srcfolder', stage, '-format', 'UDZO', '-ov', image])
    hashes = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [package, image])
    (out / 'macOS-SHA256SUMS.txt').write_text(hashes, encoding='ascii')
    report['artifacts'] = [p.name for p in [package, image]]
    (out / 'macOS-build-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
