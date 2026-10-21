"""JVM tests for URL boundaries and the site's custom download shortcodes."""
import os, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
OUT=ROOT/'app/build/core-tests';OUT.mkdir(parents=True,exist_ok=True)
src=ROOT/'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-d',str(OUT),str(src/'UrlPolicy.java'),str(src/'ReaderContent.java'),str(src/'AuthoringRules.java'),str(src/'ChatRules.java'),str(src/'SocialRules.java'),str(ROOT/'tests/CoreTest.java'),str(ROOT/'tests/SocialTest.java')],check=True)
subprocess.run([str(JDK/'bin/java.exe'),'-ea','-cp',str(OUT),'CoreTest'],check=True)

subprocess.run([str(JDK/'bin/java.exe'),'-ea','-cp',str(OUT),'SocialTest'],check=True)
