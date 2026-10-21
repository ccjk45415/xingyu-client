"""Test exact Java decoder offline and generate cross-language fixtures."""
import os,subprocess,json
from pathlib import Path
from prepare_qr import prepare
ROOT=Path(__file__).resolve().parents[1];JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
out=ROOT/'app/build/qr-tests';out.mkdir(parents=True,exist_ok=True);jar=prepare();src=ROOT/'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-cp',str(jar),'-d',str(out)]+[str(src/(n+'.java')) for n in ['QrDecoder','ReaderContent','EditorHints','UrlPolicy']]+[str(ROOT/'tests/QrTest.java')],check=True)
r=subprocess.run([str(JDK/'bin/java.exe'),'-ea','-cp',str(out)+os.pathsep+str(jar),'QrTest',str(ROOT/'tests/fixtures')],check=True,capture_output=True,text=True)
print(r.stdout.strip())
(ROOT/'evidence/qr-android-validation.json').write_text(json.dumps({'decoder':'exact Android QrDecoder on JVM','result':r.stdout.strip(),'offline':True,'real_messages_or_posts_created':False},indent=2)+'\n',encoding='utf-8')
