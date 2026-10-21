"""Pure production Android DNS policy regression; no network or device modification."""
import os,subprocess,json,sys,hashlib,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
out=ROOT/'app/build/source-tests';out.mkdir(parents=True,exist_ok=True)
subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-d',str(out),str(ROOT/'app/src/main/java/moe/cangku/reader/SourceNetworkRules.java'),str(ROOT/'tests/SourceNetworkTest.java')],check=True)
r=subprocess.run([str(jdk/'bin/java.exe'),'-ea','-cp',str(out),'moe.cangku.reader.SourceNetworkTest'],check=True,capture_output=True,text=True)
print(r.stdout.strip())
(ROOT/'evidence/ai-source-network-native.json').write_text(json.dumps({'policy':'exact Android SourceNetworkRules on JVM','result':r.stdout.strip(),'device_or_proxy_settings_modified':False},indent=2)+'\n',encoding='utf-8')
if '--live' in sys.argv:
    # Test dependency only: Android supplies its own org.json implementation at runtime.
    jar=ROOT/'.toolchain/test-deps/json-20240303.jar';jar.parent.mkdir(exist_ok=True,parents=True)
    expected='3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed'
    if not jar.is_file():jar.write_bytes(urllib.request.urlopen('https://repo.maven.apache.org/maven2/org/json/json/20240303/json-20240303.jar',timeout=30).read())
    assert hashlib.sha256(jar.read_bytes()).hexdigest()==expected
    android=ROOT/'.toolchain/android-sdk/platforms/android-35/android.jar';classes=ROOT/'app/build/manual/classes'
    assert (classes/'moe/cangku/reader/SourceNetworkRules.class').is_file(),'Build the updated Android APK first'
    cp=os.pathsep.join(map(str,[out,classes,jar,android]))
    subprocess.run([str(jdk/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(out),str(ROOT/'tests/SourceGuardLiveTest.java')],check=True)
    live=subprocess.run([str(jdk/'bin/java.exe'),'-ea','-cp',cp,'moe.cangku.reader.SourceGuardLiveTest'],check=True,capture_output=True,text=True,timeout=65)
    print(live.stdout.strip())
    (ROOT/'evidence/ai-source-network-native-live.json').write_text(json.dumps({'transport':'exact Android AiClient.checkSourceHost on JVM, Android platform org.json substituted with pinned JSON-java test jar','result':live.stdout.strip(),'device_ui_tested':False,'ai_generations':0,'credentials_sent':False},indent=2)+'\n',encoding='utf-8')
