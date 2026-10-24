package moe.cangku.xingyu_desktop;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.content.SharedPreferences;
import android.content.Intent;
import android.app.Activity;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.io.OutputStream;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public class MainActivity extends FlutterActivity {
    private static final String ALIAS = "xingyu.flutter.vault.v1";
    private MethodChannel.Result pendingNotification;
    private MethodChannel notificationChannel;
    private String pendingNotice;
    private MethodChannel.Result pendingExport;
    private byte[] exportBytes;
    private MethodChannel.Result pendingInstall;

    private void installVerifiedUpdate(MethodChannel.Result result) {
        if (!getPackageManager().canRequestPackageInstalls()) {
            pendingInstall = result;
            try {
                startActivityForResult(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:" + getPackageName())), 4102);
            } catch (Exception error) {
                pendingInstall = null;
                result.error("update", "请在系统设置中允许星屿安装应用后重试", null);
            }
            return;
        }
        try {
            android.net.Uri uri = android.net.Uri.parse("content://" + getPackageName() + ".updates/apk");
            Intent intent = new Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.setClipData(android.content.ClipData.newRawUri("星屿更新", uri));
            startActivity(intent);
            result.success(true);
        } catch (Exception error) { result.error("update", "无法打开系统安装程序，请重试", null); }
    }

    private static java.util.Set<String> signers(android.content.pm.PackageInfo info) throws Exception {
        android.content.pm.Signature[] signatures = android.os.Build.VERSION.SDK_INT >= 28
            ? (info.signingInfo == null ? null : info.signingInfo.getApkContentsSigners()) : info.signatures;
        if (signatures == null || signatures.length == 0) throw new IllegalArgumentException();
        java.util.Set<String> values = new java.util.HashSet<>();
        for (android.content.pm.Signature signature : signatures)
            values.add(Base64.encodeToString(signature.toByteArray(), Base64.NO_WRAP));
        return values;
    }

    private void verifyAndInstall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
        if (pendingInstall != null) { result.error("update", "请先完成当前安装授权", null); return; }
        new Thread(() -> {
            try {
                String path = call.argument("path"), expected = call.argument("sha256");
                Number code = call.argument("versionCode");
                if (path == null || expected == null || !expected.matches("[a-f0-9]{64}") || code == null)
                    throw new IllegalArgumentException();
                java.io.File source = new java.io.File(path).getCanonicalFile();
                String cache = getCacheDir().getCanonicalPath() + java.io.File.separator;
                if (!source.getPath().startsWith(cache) || !source.isFile() || source.length() > 160L * 1024 * 1024)
                    throw new IllegalArgumentException();
                java.io.File directory = new java.io.File(getCacheDir(), "updates");
                if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException();
                java.io.File apk = new java.io.File(directory, "verified.apk");
                java.nio.file.Files.copy(source.toPath(), apk.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
                try (java.io.InputStream stream = new java.io.FileInputStream(apk)) {
                    byte[] buffer = new byte[32768]; int count;
                    while ((count = stream.read(buffer)) != -1) digest.update(buffer, 0, count);
                }
                StringBuilder hash = new StringBuilder();
                for (byte b : digest.digest()) hash.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
                if (!hash.toString().equals(expected)) throw new IllegalArgumentException();
                android.content.pm.PackageManager pm = getPackageManager();
                int flags = android.os.Build.VERSION.SDK_INT >= 28
                    ? android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES : android.content.pm.PackageManager.GET_SIGNATURES;
                android.content.pm.PackageInfo candidate = pm.getPackageArchiveInfo(apk.getPath(), flags);
                android.content.pm.PackageInfo current = pm.getPackageInfo(getPackageName(), flags);
                long installed = android.os.Build.VERSION.SDK_INT >= 28 ? current.getLongVersionCode() : current.versionCode;
                long offered = candidate == null ? 0 : (android.os.Build.VERSION.SDK_INT >= 28 ? candidate.getLongVersionCode() : candidate.versionCode);
                if (candidate == null || !getPackageName().equals(candidate.packageName) || offered != code.longValue()
                    || offered <= installed || !signers(candidate).equals(signers(current))) throw new IllegalArgumentException();
                runOnUiThread(() -> installVerifiedUpdate(result));
            } catch (Exception error) { runOnUiThread(() -> result.error("update", "安装包版本、签名或完整性校验失败，未安装更新", null)); }
        }, "xingyu-update-check").start();
    }
    private SecretKey vaultKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return (SecretKey) store.getKey(ALIAS, null);
    }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        final SharedPreferences prefs = getSharedPreferences("flutter_secure_vault", MODE_PRIVATE);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "moe.cangku.xingyu/secure_storage")
            .setMethodCallHandler((call, result) -> {
              synchronized (CheckinJobService.LOCK) {
                try {
                    String key = call.argument("key");
                    if (key == null || !key.matches("[A-Za-z0-9_.-]{1,160}")) throw new IllegalArgumentException();
                    if (call.method.equals("delete")) {
                        if (!prefs.edit().remove(key).commit()) throw new IllegalStateException();
                        result.success(null);
                    } else if (call.method.equals("write")) {
                        String value = call.argument("value");
                        if (value == null || value.length() > 2 * 1024 * 1024) throw new IllegalArgumentException();
                        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                        cipher.init(Cipher.ENCRYPT_MODE, vaultKey());
                        cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
                        String encoded = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + ":" +
                            Base64.encodeToString(cipher.doFinal(value.getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP);
                        if (!prefs.edit().putString(key, encoded).commit()) throw new IllegalStateException();
                        result.success(null);
                    } else if (call.method.equals("read")) {
                        String encoded = prefs.getString(key, null);
                        if (encoded == null) { result.success(null); return; }
                        String[] parts = encoded.split(":", -1);
                        if (parts.length != 2) throw new IllegalStateException();
                        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                        cipher.init(Cipher.DECRYPT_MODE, vaultKey(), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
                        cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
                        result.success(new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8));
                    } else result.notImplemented();
                } catch (Exception error) {
                    // Never expose stored values, tokens, or provider keys to logs/errors.
                    result.error("secure_storage", "无法读取或保存本机加密资料", null);
                }
              }
            });
        pendingNotice=getIntent().getStringExtra(NoticeBridge.EXTRA);
        notificationChannel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "moe.cangku.xingyu/notifications");
        notificationChannel.setMethodCallHandler((call,result)->{
            try {
                if(call.method.equals("status")) result.success(NoticeBridge.status(this));
                else if(call.method.equals("request")) {
                    NoticeBridge.channels(this);
                    if(android.os.Build.VERSION.SDK_INT>=33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        if(pendingNotification!=null) {result.success(false);return;}
                        pendingNotification=result;
                        requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},NoticeBridge.PERMISSION);
                    } else result.success(NoticeBridge.granted(this));
                } else if(call.method.equals("settings")) {NoticeBridge.settings(this);result.success(null);}
                else if(call.method.equals("configure")) {
                    Integer uid=call.argument("uid"); String origin=call.argument("origin");
                    java.util.Map<?,?> preferences=call.argument("preferences");
                    NoticeBridge.configure(this,uid==null?0:uid,Boolean.TRUE.equals(call.argument("enabled")),origin==null?"":origin,new org.json.JSONObject(preferences==null?new HashMap<>():preferences));
                    synchronized(NoticeBridge.LOCK) {
                        java.util.Map<?,?> cursors=call.argument("cursors");
                        if(cursors!=null && !NoticeBridge.prefs(this).contains("cursors")) NoticeBridge.prefs(this).edit().putString("cursors",new org.json.JSONObject(cursors).toString()).commit();
                    }
                    result.success(null);
                } else if(call.method.equals("show")) {NoticeBridge.show(this,new org.json.JSONObject((java.util.Map<?,?>)call.arguments));result.success(null);}
                else if(call.method.equals("takeOpen")) {
                    result.success(pendingNotice==null?null:noticeMap(new org.json.JSONObject(pendingNotice)));
                    pendingNotice=null;getIntent().removeExtra(NoticeBridge.EXTRA);
                } else result.notImplemented();
            } catch(Exception e) {result.error("notification","系统通知暂不可用，请检查权限与后台设置",null);}
        });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "moe.cangku.xingyu/platform")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("configureCheckinBackground")) {
                    try {
                        Integer uid = call.argument("uid");
                        CheckinJobService.configure(this, Boolean.TRUE.equals(call.argument("enabled")), uid == null ? 0 : uid);
                        result.success(null);
                    } catch(Exception error) { result.error("checkin", "系统暂时无法安排后台签到", null); }
                } else if (call.method.equals("checkinBackgroundStatus")) {
                    result.success(CheckinJobService.status(this));
                } else if (call.method.equals("proxy")) {
                    ConnectivityManager cm = (ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
                    ProxyInfo proxy = cm == null ? null : cm.getDefaultProxy();
                    Map<String, Object> value = new HashMap<>();
                    if (proxy != null && proxy.getHost() != null) {
                        value.put("host", proxy.getHost()); value.put("port", proxy.getPort());
                    }
                    result.success(value);
                } else if (call.method.equals("installUpdate")) {
                    verifyAndInstall(call, result);
                } else if (call.method.equals("saveHtml")) {
                    String content = call.argument("content");
                    if (pendingExport != null || content == null || content.length() > 2 * 1024 * 1024) {
                        result.error("export", "请等待当前导出完成，或缩短文章", null); return;
                    }
                    pendingExport = result;
                    exportBytes = content.getBytes(StandardCharsets.UTF_8);
                    Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("text/html");
                    intent.putExtra(Intent.EXTRA_TITLE, "星屿投稿.html");
                    try { startActivityForResult(intent, 4101); }
                    catch (Exception error) { pendingExport = null; exportBytes = null; result.error("export", "无法打开系统文件保存器", null); }
                } else result.notImplemented();
            });
    }
    @Override protected void onActivityResult(int request, int code, Intent data) {
        super.onActivityResult(request, code, data);
        if (request == 4102 && pendingInstall != null) {
            MethodChannel.Result result = pendingInstall; pendingInstall = null;
            if (getPackageManager().canRequestPackageInstalls()) installVerifiedUpdate(result);
            else result.error("update", "未获得安装权限，更新文件已下载，可授权后重试", null);
            return;
        }
        if (request != 4101 || pendingExport == null) return;
        MethodChannel.Result result = pendingExport;
        byte[] bytes = exportBytes;
        pendingExport = null; exportBytes = null;
        if (code != Activity.RESULT_OK || data == null || data.getData() == null) { result.success(false); return; }
        try (OutputStream stream = getContentResolver().openOutputStream(data.getData(), "wt")) {
            if (stream == null) throw new IllegalStateException();
            stream.write(bytes); stream.flush(); result.success(true);
        } catch (Exception error) { result.error("export", "文件保存失败，请更换保存位置", null); }
    }
    private static Map<String,Object> noticeMap(org.json.JSONObject obj) throws org.json.JSONException {
        Map<String,Object> result=new HashMap<>();java.util.Iterator<String> keys=obj.keys();
        while(keys.hasNext()){String key=keys.next();result.put(key,obj.get(key));}return result;
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(request,permissions,results);
        if(request==NoticeBridge.PERMISSION && pendingNotification!=null) {
            MethodChannel.Result result=pendingNotification;pendingNotification=null;result.success(NoticeBridge.granted(this));
        }
    }
    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);setIntent(intent);pendingNotice=intent.getStringExtra(NoticeBridge.EXTRA);
        if(pendingNotice!=null && notificationChannel!=null) notificationChannel.invokeMethod("opened",null);
    }

}
