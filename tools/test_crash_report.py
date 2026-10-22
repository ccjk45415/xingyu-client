from pathlib import Path
import os,subprocess
root=Path(__file__).resolve().parents[1];out=root/'app/build/crash-report-tests';out.mkdir(parents=True,exist_ok=True)
jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-d',str(out),str(root/'app/src/main/java/moe/cangku/reader/CrashReport.java'),str(root/'tests/CrashReportTest.java')],check=True)
subprocess.run([str(jdk/'bin/java.exe'),'-ea','-cp',str(out),'moe.cangku.reader.CrashReportTest'],check=True)
