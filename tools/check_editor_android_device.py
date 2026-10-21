"""Optional real-device editor check in an isolated, Internet-disabled test APK.

Build the normal APK first. Does not install or change the user's real client.
"""
import os,subprocess,zipfile,shutil,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];SDK=ROOT/'.toolchain/android-sdk';BT=SDK/'build-tools/35.0.0';JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Java/jdk-17'));B=ROOT/'app/build/editor-device';B.mkdir(parents=True,exist_ok=True)
ADB=SDK/'platform-tools/adb.exe';PKG='moe.cangku.reader.editorcheck';ANDROID=SDK/'platforms/android-35/android.jar';APP=ROOT/'app/build/manual/classes.jar';QR=ROOT/'.toolchain/qr/core-3.5.4.jar'
def run(args,**kwargs):return subprocess.run([str(x) for x in args],check=True,capture_output=True,encoding='utf-8',errors='replace',**kwargs)
devices=[s.split()[0] for s in run([ADB,'devices']).stdout.splitlines() if s.endswith('\tdevice')]
if len(devices)!=1:raise SystemExit('Exactly one authorized Android device is required')
device=devices[0]
def adb(*args,**kwargs):return run([ADB,'-s',device,*args],**kwargs)
manifest=B/'AndroidManifest.xml';manifest.write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{PKG}"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="星屿编辑器独立测试" android:theme="@style/AppTheme" android:allowBackup="false"><activity android:name="moe.cangku.reader.MainActivity" android:exported="true" android:configChanges="orientation|screenSize|uiMode"/></application><instrumentation android:name="moe.cangku.reader.EditorInstrument" android:targetPackage="{PKG}"/></manifest>''',encoding='utf-8')
classes=B/'classes';classes.mkdir(exist_ok=True)
run([JDK/'bin/javac.exe','-encoding','UTF-8','--release','17','-cp',str(ANDROID)+os.pathsep+str(APP),'-d',classes,ROOT/'tests/EditorInstrument.java'])
jar=B/'instrument.jar'
with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as z:
    for p in classes.rglob('*.class'):z.write(p,p.relative_to(classes).as_posix())
apk=B/'unsigned.apk';run([BT/'aapt2.exe','link','-o',apk,'--manifest',manifest,'-I',ANDROID,'--custom-package','moe.cangku.reader','-R',ROOT/'app/build/manual/resources.zip','--auto-add-overlay'])
dex=B/'dex';dex.mkdir(exist_ok=True);run([JDK/'bin/java.exe','-cp',BT/'lib/d8.jar','com.android.tools.r8.D8','--lib',ANDROID,'--min-api','26','--output',dex,APP,QR,jar])
with zipfile.ZipFile(apk,'a',zipfile.ZIP_DEFLATED) as z:
    for p in dex.glob('*.dex'):z.write(p,p.name)
aligned=B/'aligned.apk';signed=B/'editor-check.apk';run([BT/'zipalign.exe','-f','-p','4',apk,aligned]);run([JDK/'bin/java.exe','-jar',BT/'lib/apksigner.jar','sign','--ks',ROOT/'.toolchain/keys/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',signed,aligned])
try:
    adb('install','--no-incremental','-r','-t',signed,timeout=30)
    outcome=adb('shell','am','instrument','-w',PKG+'/moe.cangku.reader.EditorInstrument',timeout=45).stdout
    if 'EDITOR_DEVICE_PASS' not in outcome:raise RuntimeError(outcome[-2000:])
    adb('pull',f'/sdcard/Android/data/{PKG}/files/editor-toolbar.png',ROOT/'evidence/editor-android-toolbar.png',timeout=15)
    report={'isolated_test_package':PKG,'internet_permission':False,'synthetic_data_only':True,'production_client_changed':False,'result':outcome.strip()}
    (ROOT/'evidence/editor-device-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(outcome.strip())
finally:
    try:adb('uninstall',PKG,timeout=20)
    except Exception:pass
