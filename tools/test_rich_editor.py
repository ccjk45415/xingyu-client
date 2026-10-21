"""Offline JVM checks of actual native lossless rich editor and website templates."""
import os, subprocess, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
JDK = Path(os.environ.get('JAVA_HOME', 'C:/Program Files/Java/jdk-17'))
OUT = ROOT / 'app/build/rich-editor-tests'
OUT.mkdir(parents=True, exist_ok=True)
JAR = ROOT / '.toolchain/html/jsoup-1.23.2.jar'
SRC = ROOT / 'app/src/main/java/moe/cangku/reader'
subprocess.run([str(JDK / 'bin/javac.exe'), '-encoding', 'UTF-8', '-cp', str(JAR), '-d', str(OUT)] + [str(SRC / (name + '.java')) for name in ['RichEditorDocument', 'NativePrintPagination', 'EditorTemplates', 'ReaderContent', 'UrlPolicy']] + [str(ROOT / 'tests/RichEditorDocumentTest.java')], check=True)
result = subprocess.run([str(JDK / 'bin/java.exe'), '-ea', '-cp', os.pathsep.join([str(OUT), str(JAR)]), 'RichEditorDocumentTest'], capture_output=True, check=True, encoding='utf-8')
print(result.stdout.strip())
(ROOT / 'evidence/editor-android-rich-validation.json').write_text(json.dumps({'actual_source': 'RichEditorDocument + EditorTemplates + NativePrintPagination', 'result': result.stdout.strip(), 'local_only': True, 'website_writes': 0, 'full_android_device_ui_verified': False}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
