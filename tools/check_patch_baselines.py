"""Offline command-contract checks. Never invokes Shorebird, git or a build."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import types
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def invoke(script, arguments, fixture):
    commands = []
    fake_builder = types.ModuleType('build_flutter_android')
    fake_builder.ROOT = fixture
    fake_builder.TOOL = fixture / 'toolchain'

    def prepare():
        fake_builder.STAGE.mkdir(parents=True, exist_ok=True)
        return {}

    fake_builder.prepare = prepare

    def git_fixture(command, **kwargs):
        if 'ls-tree' in command:
            return 'desktop/android/app/build.gradle.kts\n'
        if 'show' in command:
            return b'// isolated original native baseline\n'
        raise AssertionError('Unexpected external command')

    def capture(command, **kwargs):
        commands.append((command, kwargs))
        return types.SimpleNamespace(returncode=0, stdout='No issues detected.\n')

    with patch.dict(sys.modules, {'build_flutter_android': fake_builder}), \
            patch.object(sys, 'argv', [script, *arguments]), \
            patch.dict(os.environ, {'RUNNER_TEMP': str(fixture / 'runner')}, clear=False), \
            patch.object(subprocess, 'check_output', git_fixture), \
            patch.object(subprocess, 'run', capture), \
            contextlib.redirect_stdout(io.StringIO()):
        namespace = runpy.run_path(str(ROOT / 'tools' / script), run_name='__main__')
    return commands, namespace, fake_builder


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix='xingyu-patch-contract-') as folder:
        fixture = Path(folder)
        (fixture / '.git').mkdir()
        for release, track, revision, has_defines in [
            ('0.13.6+43', 'template-20261101', '01aea2ee0626578b6b30ebbb2605f195833464fa', True),
            ('0.13.5+41', 'qa-20261027', '7dbbfb1fc6d89d11974ff5a770610d0937d27206', True),
            ('0.13.2+38', 'staging', '7dbbfb1fc6d89d11974ff5a770610d0937d27206', True),
            ('0.13.1+37', 'staging', '7dbbfb1fc6d89d11974ff5a770610d0937d27206', False),
        ]:
            commands, namespace, builder = invoke('run_android_patch.py', ['--release-version', release, '--dry-run'], fixture)
            assert len(commands) == 1
            command = commands[0][0]
            name, build = release.split('+')
            assert f'--release-version={release}' in command
            assert f'--build-name={name}' in command and f'--build-number={build}' in command
            assert f'--track={track}' in command and f'--dart-define=XINGYU_PATCH_TRACK={track}' in command
            assert '--dart-define=XINGYU_ANDROID_TEST=true' in command and '--dry-run' in command
            assert command[-2:] == ['--', '--target-platform=android-arm64']
            assert (f'--dart-define=XINGYU_ANDROID_VERSION={name}' in command) is has_defines
            assert str(builder.FLUTTER).endswith(revision)
            native = builder.STAGE / 'android/app/build.gradle.kts'
            assert native.read_bytes() == b'// isolated original native baseline\n'
            count += 1
        try:
            invoke('run_android_patch.py', ['--release-version', '0.13.3+39', '--dry-run'], fixture)
        except SystemExit as error:
            assert 'No trusted installed native baseline' in str(error)
        else:
            raise AssertionError('An unrecorded native baseline must fail closed')
        count += 1
        for platform, variants in {
            'windows': [('0.7.5+33','template-20261101',True), ('0.7.4+31','qa-20261027',True), ('0.7.1+28','staging',False)],
            'macos': [('0.3.5+10','template-20261101',True), ('0.3.4+9','qa-20261027',True), ('0.3.1+6','staging',False)],
        }.items():
            for release, track, has_defines in variants:
                commands, _, _ = invoke('run_desktop_patch.py', [platform, '--release-version', release, '--dry-run'], fixture)
                assert len(commands) == 1
                command = commands[0][0]
                name, build = release.split('+')
                assert f'--release-version={release}' in command
                assert f'--track={track}' in command and f'--dart-define=XINGYU_PATCH_TRACK={track}' in command
                assert '--dart-define=XINGYU_REQUIRE_CODE_PUSH=true' in command and '--dry-run' in command
                assert (f'--dart-define=XINGYU_{platform.upper()}_VERSION={name}' in command) is has_defines
                assert f'--build-number={build}' in command
                count += 1
        default, _, _ = invoke('run_android_patch.py', ['--dry-run'], fixture)
        assert '--release-version=0.13.6+43' in default[0][0]
        for platform, release in [('windows', '0.7.5+33'), ('macos', '0.3.5+10')]:
            default, _, _ = invoke('run_desktop_patch.py', [platform, '--dry-run'], fixture)
            assert f'--release-version={release}' in default[0][0]
        count += 3
    print(f'{count} offline patch command contracts passed; no external command was executed.')


if __name__ == '__main__':
    main()
