"""Compile Android source/resources. No installable APK, signing, or published release changes."""
import os,subprocess
from prepare_html import prepare
from prepare_qr import prepare as prepare_qr
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
SDK=Path(os.environ.get('ANDROID_HOME',ROOT/'.toolchain/android-sdk'))
OUT=ROOT/'app/build/source-check';OUT.mkdir(parents=True,exist_ok=True)
BT=SDK/'build-tools/35.0.0';GEN=OUT/'gen';GEN.mkdir(exist_ok=True)
def resource_run(arguments):
    def arg(value):
        if isinstance(value,Path):
            try:return value.relative_to(ROOT).as_posix()
            except ValueError:pass
        return str(value)
    subprocess.run([str(BT/'aapt2.exe')]+list(map(arg,arguments)),cwd=ROOT,check=True)
resource_run(['compile','--dir',ROOT/'app/src/main/res','-o',OUT/'resources.zip'])
resource_run(['link','-o',OUT/'resource-stubs.apk','--manifest',ROOT/'app/src/main/AndroidManifest.xml','-I',SDK/'platforms/android-35/android.jar','--java',GEN,'-R',OUT/'resources.zip','--auto-add-overlay'])
sources=sorted((ROOT/'app/src/main/java').rglob('*.java'))+sorted(GEN.rglob('*.java'))
args=OUT/'sources.args';args.write_text('\n'.join('"'+p.relative_to(ROOT).as_posix()+'"' for p in sources),encoding='utf-8')
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','--release','17','-classpath',os.pathsep.join([str(SDK/'platforms/android-35/android.jar'),str(prepare()),str(prepare_qr())]),'-d',str(OUT),'@'+str(args)],check=True,cwd=ROOT)
print('PASS Android source compilation; APKs, update metadata and deployments unchanged')
