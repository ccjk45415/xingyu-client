"""Build a dependency-free native Android APK using the official SDK and JDK 17."""
import os, shutil, subprocess, sys, zipfile
from prepare_qr import prepare
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SDK=Path(os.environ.get('ANDROID_HOME',ROOT/'.toolchain'/'android-sdk'))
BUILD=ROOT/'app'/'build'/'manual'
OUT=ROOT/'output'
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
TOOLS=SDK/'build-tools'/'35.0.0'
ANDROID=SDK/'platforms'/'android-35'/'android.jar'
for p in [BUILD,OUT,BUILD/'gen',BUILD/'classes',BUILD/'dex']:p.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['JAVA_HOME']=str(JDK)
def run(args):
    print('RUN',Path(str(args[0])).name,' '.join(str(a) for a in args[1:3]),flush=True)
    def relative(arg):
        if isinstance(arg,Path):
            try:return arg.relative_to(ROOT).as_posix()
            except ValueError:pass
        return str(arg)
    subprocess.run([str(args[0])]+[relative(a) for a in args[1:]],check=True,cwd=ROOT,env=env)
def argfile(path,arguments):
    path.write_text('\n'.join('"'+a.relative_to(ROOT).as_posix()+'"' for a in arguments),encoding='utf-8')
    return '@'+path.relative_to(ROOT).as_posix()
if not ANDROID.exists():raise SystemExit('Run python tools/prepare_toolchain.py first')
qr=prepare()
run([TOOLS/'aapt2.exe','compile','--dir',ROOT/'app/src/main/res','-o',BUILD/'resources.zip'])
run([TOOLS/'aapt2.exe','link','-o',BUILD/'resources.apk','--manifest',ROOT/'app/src/main/AndroidManifest.xml','-I',ANDROID,'--java',BUILD/'gen','--min-sdk-version','26','--target-sdk-version','35','--version-code','8','--version-name','0.6.2','-R',BUILD/'resources.zip','-A',ROOT/'app/src/main/assets','--auto-add-overlay'])
sources=list((ROOT/'app/src/main/java').rglob('*.java'))+list((BUILD/'gen').rglob('*.java'))
run([JDK/'bin/javac.exe','-encoding','UTF-8','--release','17','-classpath',str(ANDROID)+os.pathsep+str(qr),'-d',BUILD/'classes',argfile(BUILD/'sources.args',sources)])
jar=BUILD/'classes.jar'
with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as z:
    for p in (BUILD/'classes').rglob('*.class'):z.write(p,p.relative_to(BUILD/'classes').as_posix())
run([JDK/'bin/java.exe','-cp',TOOLS/'lib/d8.jar','com.android.tools.r8.D8','--lib',ANDROID,'--min-api','26','--output',BUILD/'dex',jar,qr])
unsigned=BUILD/'unsigned.apk';shutil.copyfile(BUILD/'resources.apk',unsigned)
with zipfile.ZipFile(unsigned,'a',zipfile.ZIP_DEFLATED) as z:
    for p in (BUILD/'dex').glob('*.dex'):z.write(p,p.name)
aligned=BUILD/'aligned.apk'
run([TOOLS/'zipalign.exe','-f','-p','4',unsigned,aligned])
key=ROOT/'.toolchain'/'keys'/'debug.keystore';key.parent.mkdir(exist_ok=True,parents=True)
if not key.exists():
    run([JDK/'bin/keytool.exe','-genkeypair','-keystore',key,'-storepass','android','-keypass','android','-alias','androiddebugkey','-dname','CN=Android Debug,O=Android,C=US','-keyalg','RSA','-keysize','2048','-validity','10000','-noprompt'])
apk=OUT/'Cangku-Xingyu-0.6.2-debug.apk'
run([JDK/'bin/java.exe','-jar',TOOLS/'lib/apksigner.jar','sign','--ks',key,'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',apk,aligned])
run([JDK/'bin/java.exe','-jar',TOOLS/'lib/apksigner.jar','verify','--verbose',apk])
run([TOOLS/'aapt2.exe','dump','badging',apk])
print('APK_READY',apk,apk.stat().st_size,flush=True)
