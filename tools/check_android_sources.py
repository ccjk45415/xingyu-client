"""Compile Android source only. Does not create/sign an APK or touch published release files."""
import os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
SDK=Path(os.environ.get('ANDROID_HOME',ROOT/'.toolchain/android-sdk'))
OUT=ROOT/'app/build/source-check';OUT.mkdir(parents=True,exist_ok=True)
sources=sorted((ROOT/'app/src/main/java').rglob('*.java'))
args=OUT/'sources.args';args.write_text('\n'.join('"'+p.relative_to(ROOT).as_posix()+'"' for p in sources),encoding='utf-8')
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','--release','17','-classpath',str(SDK/'platforms/android-35/android.jar'),'-d',str(OUT),'@'+str(args)],check=True,cwd=ROOT)
print('PASS Android source compilation; APKs, update metadata and deployments unchanged')
