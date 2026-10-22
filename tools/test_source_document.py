"""Actual production DOM and translation helpers on JVM; no Android HTML shim or AI calls."""
import subprocess,os,json,hashlib,urllib.request,sys
from pathlib import Path
from prepare_html import prepare
ROOT=Path(__file__).resolve().parents[1];jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
jar=ROOT/'.toolchain/test-deps/json-20240303.jar';jar.parent.mkdir(exist_ok=True,parents=True)
if not jar.is_file():jar.write_bytes(urllib.request.urlopen('https://repo.maven.apache.org/maven2/org/json/json/20240303/json-20240303.jar',timeout=30).read())
assert hashlib.sha256(jar.read_bytes()).hexdigest()=='3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed'
out=ROOT/'app/build/source-document-tests';out.mkdir(exist_ok=True,parents=True)
cp=os.pathsep.join(map(str,[out,ROOT/'app/build/manual/classes',jar,prepare(),ROOT/'.toolchain/android-sdk/platforms/android-35/android.jar']))
subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(out),str(ROOT/'app/src/main/java/moe/cangku/reader/SourceTranslation.java'),str(ROOT/'app/src/main/java/moe/cangku/reader/SourceDocument.java'),str(ROOT/'tests/SourceDocumentTest.java')],check=True)
result=subprocess.run([str(jdk/'bin/java.exe'),'-Dfile.encoding=UTF-8','-ea','-cp',cp,'moe.cangku.reader.SourceDocumentTest',str(ROOT/'tests/fixtures/source-introduction.html')],check=True,capture_output=True,text=True,encoding='utf-8');print(result.stdout.strip())
(ROOT/'evidence/ai-source-document-native.json').write_text(json.dumps({'helpers':'exact production SourceDocument + SourceTranslation','result':result.stdout.strip(),'synthetic_fixture':True,'real_ai_calls':0,'device_ui_tested':False},indent=2)+'\n',encoding='utf-8')
if '--live' in sys.argv:
    subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(out),str(ROOT/'tests/SourceDocumentLiveTest.java')],check=True)
    live=subprocess.run([str(jdk/'bin/java.exe'),'-Dfile.encoding=UTF-8','-ea','-cp',cp,'moe.cangku.reader.SourceDocumentLiveTest'],capture_output=True,text=True,encoding='utf-8',timeout=70)
    if live.returncode: print(live.stderr.strip());raise SystemExit(live.returncode)
    print(live.stdout.strip())
    (ROOT/'evidence/ai-source-document-native-live.json').write_text(json.dumps({'transport':'production Android AiClient.source + SourceDocument on JVM; pinned JSON-java substitutes org.json','source_id':'RJ01726046','result':live.stdout.strip(),'real_ai_calls':0,'device_ui_tested':False},indent=2)+'\n',encoding='utf-8')
