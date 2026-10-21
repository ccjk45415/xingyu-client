"""Offline checks for Android website comment/media serialization and upload boundaries."""
import json, os, subprocess
from pathlib import Path
from prepare_html import prepare
ROOT=Path(__file__).resolve().parents[1]
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'))
OUT=ROOT/'app/build/comment-media-tests'; OUT.mkdir(parents=True,exist_ok=True)
JAR=prepare()
SRC=ROOT/'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','-cp',str(JAR),'-d',str(OUT)]+[str(SRC/(name+'.java')) for name in ['CommentMedia','CommentImageRules','ReaderContent','UrlPolicy']]+[str(ROOT/'tests/CommentMediaTest.java')],check=True)
result=subprocess.run([str(JDK/'bin/java.exe'),'-ea','-cp',os.pathsep.join([str(OUT),str(JAR)]),'CommentMediaTest'],capture_output=True,encoding='utf-8',errors='replace')
print(result.stdout.strip()); print(result.stderr.strip()) if result.stderr else None
result.check_returncode()
(ROOT/'evidence/comment-media-android-validation.json').write_text(json.dumps({'result':result.stdout.strip(),'actual_sources':['CommentMedia.java','CommentImageRules.java'],'no_website_writes':True,'android_full_ui_device_verified':False,'image_upload_http_verified':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
