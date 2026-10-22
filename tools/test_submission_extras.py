"""Run actual production native RJ/proof helpers without Android or website writes."""
from pathlib import Path
import os,subprocess
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
OUT=ROOT/'app/build/submission-extras-tests';OUT.mkdir(parents=True,exist_ok=True)
CP=os.pathsep.join(map(str,[OUT,ROOT/'app/build/manual/classes']))
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-cp',CP,'-d',str(OUT),str(ROOT/'app/src/main/java/moe/cangku/reader/SubmissionExtras.java'),str(ROOT/'tests/SubmissionExtrasTest.java')],check=True)
r=subprocess.run([str(JDK/'bin/java.exe'),'-ea','-Dfile.encoding=UTF-8','-cp',CP,'moe.cangku.reader.SubmissionExtrasTest'],check=True,capture_output=True,text=True,encoding='utf-8');print(r.stdout.strip())
