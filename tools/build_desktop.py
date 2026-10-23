"""Build the Flutter Windows desktop bundle with installed VS, or a portable official SDK.

No admin installation, registry edits, website credentials, or Cloudflare deploys.
"""
import argparse,os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];APP=ROOT/'desktop'
alias=Path('C:/codex-tools/xingyu-desktop')
if os.name=='nt' and alias.is_dir() and alias.resolve()==APP.resolve():APP=alias
parser=argparse.ArgumentParser();parser.add_argument('--configure-only',action='store_true');args=parser.parse_args()
FLUTTER=Path(os.environ.get('FLUTTER_ROOT','C:/codex-tools/flutter'))
DART=FLUTTER/'bin/cache/dart-sdk/bin/dart.exe';SNAPSHOT=FLUTTER/'bin/cache/flutter_tools.snapshot'
if not DART.is_file():raise SystemExit('Install Flutter and set FLUTTER_ROOT first. See desktop/README.md')
def run(argv,**kwargs):
    print('RUN',str(argv[0]),' '.join(str(v) for v in argv[1:3]),flush=True)
    return subprocess.run([str(v).replace('\\','/') for v in argv],cwd=APP,**kwargs)
env=os.environ.copy();env['FLUTTER_ROOT']=str(FLUTTER);env['FLUTTER_SUPPRESS_ANALYTICS']='true';env['CI']='true'
env['VSLANG']='1033'
# Flutter writes ephemeral configuration and plugin symlinks before probing Visual Studio.
configured=run([DART,SNAPSHOT,'build','windows','--release','--config-only'],env=env)
portable=Path(os.environ.get('XINGYU_BUILD_TOOLS','C:/codex-tools'))
cmake=portable/'python-build/cmake/data/bin/cmake.exe';ninja=portable/'python-build/bin/ninja.exe'
vswhere=Path('C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe')
if not cmake.is_file() or not ninja.is_file():
    if configured.returncode:raise SystemExit(configured.returncode)
    if not args.configure_only:run([DART,SNAPSHOT,'build','windows','--release'],env=env,check=True)
    raise SystemExit(0)
vs=Path(subprocess.check_output([str(vswhere),'-latest','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip())
msvc=sorted((vs/'VC/Tools/MSVC').iterdir())[-1]
sdk=portable/'windows-sdk/microsoft.windows.sdk.cpp/c';libs=portable/'windows-sdk/microsoft.windows.sdk.cpp.x64/c'
sdkversion=sorted((sdk/'Include').iterdir())[-1].name
env['PATH']=';'.join([str(msvc/'bin/Hostx64/x64'),str(sdk/'bin'/sdkversion/'x64'),str(cmake.parent),str(ninja.parent),env['PATH']])
env['INCLUDE']=';'.join(str(p) for p in [msvc/'include',sdk/'Include'/sdkversion/'ucrt',sdk/'Include'/sdkversion/'shared',sdk/'Include'/sdkversion/'um',sdk/'Include'/sdkversion/'winrt',sdk/'Include'/sdkversion/'cppwinrt'])
env['LIB']=';'.join(str(p) for p in [msvc/'lib/x64',libs/'ucrt/x64',libs/'um/x64'])
env['WindowsSdkDir']=str(sdk)+os.sep;env['WindowsSDKVersion']=sdkversion+os.sep
build=APP/'build/windows/native-x64'
run([cmake,'-S',APP/'windows','-B',build,'-G','Ninja',f'-DCMAKE_MAKE_PROGRAM={ninja}',f'-DCMAKE_CXX_COMPILER={msvc / "bin/Hostx64/x64/cl.exe"}',f'-DCMAKE_RC_COMPILER={sdk / "bin" / sdkversion / "x64/rc.exe"}',f'-DCMAKE_MT={sdk / "bin" / sdkversion / "x64/mt.exe"}','-DCMAKE_BUILD_TYPE=Release','-DFLUTTER_TARGET_PLATFORM=windows-x64','-DCMAKE_POLICY_VERSION_MINIMUM=3.5'],env=env,check=True)
if args.configure_only:raise SystemExit(0)
# media_kit declares extracted import libraries as link inputs. Ninja must
# materialize these before it can construct the full native dependency graph.
if (build/'mpv-dev-x86_64-20230924-git-652a1dd.7z').is_file() and not (build/'libmpv/libmpv.dll.a').is_file():
    run([cmake,'--build',build,'--target','media_kit_libs_windows_video_LIBMPV_EXTRACT'],env=env,check=True)
if (build/'ANGLE.7z').is_file() and not (build/'ANGLE/libEGL.dll').is_file():
    run([cmake,'--build',build,'--target','media_kit_libs_windows_video_ANGLE_EXTRACT'],env=env,check=True)
run([cmake,'--build',build,'--target','flutter_assemble'],env=env,check=True)
# Ninja needs the import library to exist before constructing the full dependency graph.
# Restore the SDK artifacts explicitly when Flutter's ephemeral cache was invalidated.
ephemeral=APP/'windows/flutter/ephemeral'
engine=FLUTTER/'bin/cache/artifacts/engine/windows-x64-release'
for artifact in engine.iterdir():
    if artifact.is_file() and artifact.suffix in ['.dll','.lib','.exp','.h']:shutil.copy2(artifact,ephemeral/artifact.name)
icu=FLUTTER/'bin/cache/artifacts/engine/windows-x64/icudtl.dat'
shutil.copy2(icu,ephemeral/icu.name)
run([cmake,'--build',build,'--parallel','6'],env=env,check=True)
run([cmake,'--install',build,'--config','Release'],env=env,check=True)
bundle=build/'runner'
redist=sorted((vs/'VC/Redist/MSVC').glob('14.*'))[-1]/'x64/Microsoft.VC143.CRT'
for dll in redist.glob('*.dll'):shutil.copy2(dll,bundle/dll.name)
print('WINDOWS_BUNDLE_READY',bundle,flush=True)
