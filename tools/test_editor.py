"""Offline tests of actual Android editing rules; no account or network writes."""
import os,subprocess,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'));OUT=ROOT/'app/build/editor-tests';OUT.mkdir(parents=True,exist_ok=True)
src=ROOT/'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-d',str(OUT)]+[str(src/(name+'.java')) for name in ['EditorBuffer','EditorStyles','AuthoringRules','ReaderContent','UrlPolicy']]+[str(ROOT/'tests/EditorToolsTest.java')],check=True)
r=subprocess.run([str(JDK/'bin/java.exe'),'-ea','-cp',str(OUT),'EditorToolsTest'],check=True,capture_output=True,text=True)
print(r.stdout.strip());(ROOT/'evidence/editor-android-validation.json').write_text(json.dumps({'actual_source':'EditorBuffer + EditorStyles','result':r.stdout.strip(),'local_only':True,'website_writes':0},indent=2)+'\n',encoding='utf-8')
