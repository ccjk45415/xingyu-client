"""Run production Android category rules on JVM, no website access."""
from pathlib import Path
import os,subprocess
ROOT=Path(__file__).resolve().parents[1];JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
OUT=ROOT/'app/build/browse-preferences-tests';OUT.mkdir(parents=True,exist_ok=True)
cp=os.pathsep.join(map(str,[OUT,ROOT/'.toolchain/test-deps/json-20240303.jar']))
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(OUT),str(ROOT/'app/src/main/java/moe/cangku/reader/CategoryRules.java'),str(ROOT/'app/src/main/java/moe/cangku/reader/FollowFeedRules.java'),str(ROOT/'tests/BrowsePreferencesTest.java')],check=True)
r=subprocess.run([str(JDK/'bin/java.exe'),'-ea','-Dfile.encoding=UTF-8','-cp',cp,'moe.cangku.reader.BrowsePreferencesTest'],capture_output=True,text=True,encoding='utf-8',check=True);print(r.stdout.strip())
