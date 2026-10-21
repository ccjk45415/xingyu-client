"""Compile exact native editor extra rules; synthetic fixture only, no site writes."""
import os, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
out=ROOT/'app/build/editor-extra-tests';out.mkdir(parents=True,exist_ok=True)
cp=os.pathsep.join(str(ROOT/p) for p in ['.toolchain/test-deps/json-20240303.jar','.toolchain/html/jsoup-1.23.2.jar'])
subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(out),str(ROOT/'app/src/main/java/moe/cangku/reader/EditorExtraRules.java'),str(ROOT/'tests/EditorExtraRulesTest.java')],check=True)
subprocess.run([str(jdk/'bin/java.exe'),'-Dfile.encoding=UTF-8','-ea','-cp',str(out)+os.pathsep+cp,'moe.cangku.reader.EditorExtraRulesTest'],check=True)
