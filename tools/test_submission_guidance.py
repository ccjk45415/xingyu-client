"""Run actual Android guidance rules on JVM; cross-platform cases use synthetic IDs."""
import json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
OUT=ROOT/'app/build/submission-guidance-tests';OUT.mkdir(parents=True,exist_ok=True)
ASSET=ROOT/'app/src/main/assets/submission-guidance.json'
assert ASSET.read_bytes()==(ROOT/'desktop/assets/submission-guidance.json').read_bytes()
cp=os.pathsep.join(map(str,[OUT,ROOT/'.toolchain/test-deps/json-20240303.jar',ROOT/'.toolchain/html/jsoup-1.23.2.jar']))
src=ROOT/'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-cp',cp,'-d',str(OUT),*[str(src/(n+'.java')) for n in ['SubmissionGuidance','ReaderContent','UrlPolicy']],str(ROOT/'tests/SubmissionGuidanceTest.java')],check=True)
result=subprocess.run([str(JDK/'bin/java.exe'),'-Dfile.encoding=UTF-8','-ea','-cp',cp,'moe.cangku.reader.SubmissionGuidanceTest',str(ASSET),str(ROOT/'tests/fixtures/submission-guidance-cases.json'),str(OUT/'native-results.json')],check=True,capture_output=True,text=True,encoding='utf-8')
print(result.stdout.strip())
desktop=ROOT/'desktop/build/guidance-rules-results.json'
if desktop.is_file():
    assert json.loads(desktop.read_text(encoding='utf-8'))==json.loads((OUT/'native-results.json').read_text(encoding='utf-8')), 'Cross-platform guidance mismatch'
    print('PASS exact issue-code parity across native Android and Flutter')
