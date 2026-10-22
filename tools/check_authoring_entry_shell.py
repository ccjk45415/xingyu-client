"""Run real Android editor construction without installing or changing the client."""
import os,subprocess,zipfile,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'.toolchain/android-sdk';BT=SDK/'build-tools/35.0.0';JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
B=ROOT/'app/build/authoring-entry';B.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--apk',default='output/Cangku-Xingyu-0.9.9-debug.apk');args=parser.parse_args();apk=ROOT/args.apk
ANDROID=SDK/'platforms/android-35/android.jar';APP=ROOT/'app/build/manual/classes.jar'
def run(args,**kw):return subprocess.run(list(map(str,args)),capture_output=True,text=True,encoding='utf-8',errors='replace',check=True,**kw)
classes=B/'classes';classes.mkdir(exist_ok=True)
run([JDK/'bin/javac.exe','-encoding','UTF-8','--release','17','-cp',str(ANDROID)+os.pathsep+str(APP),'-d',classes,ROOT/'tests/AuthoringEntryShell.java'])
jar=B/'probe.jar'
with zipfile.ZipFile(jar,'w') as z:
    for p in classes.rglob('*.class'):z.write(p,p.relative_to(classes).as_posix())
dex=B/'dex';dex.mkdir(exist_ok=True)
run([JDK/'bin/java.exe','-cp',BT/'lib/d8.jar','com.android.tools.r8.D8','--lib',ANDROID,'--min-api','26','--output',dex,jar,APP,ROOT/'.toolchain/html/jsoup-1.23.2.jar',ROOT/'.toolchain/qr/core-3.5.4.jar'])
packed=B/'probe-dex.jar'
with zipfile.ZipFile(packed,'w') as z:
    for p in dex.glob('*.dex'):z.write(p,p.name)
adb=SDK/'platform-tools/adb.exe';remote='/data/local/tmp/xingyu-authoring-entry-probe.jar';resources='/data/local/tmp/xingyu-authoring-entry-resources.apk'
run([adb,'push',packed,remote],timeout=15)
try:
    run([adb,'push',apk,resources],timeout=15)
    result=subprocess.run([str(adb),'shell',f'CLASSPATH={remote} app_process /system/bin moe.cangku.reader.AuthoringEntryShell {resources}'],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=25)
finally:
    run([adb,'shell','rm','-f',remote,resources],timeout=10)
(B/'result.log').write_text(result.stdout+result.stderr,encoding='utf-8')
print(result.stdout[-7000:]);print(result.stderr[-2000:])
if 'AUTHORING_ENTRY_PASS' not in result.stdout:raise SystemExit('Editor entry failed; see result.log')
