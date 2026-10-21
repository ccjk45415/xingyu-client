package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.net.Uri;
import android.os.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** Daily opt-in APK download, strict same-origin URL/hash/package/version/signature verification. */
final class AppUpdates {
    private final MainActivity host;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService executor=Executors.newSingleThreadExecutor();
    private final SharedPreferences prefs;
    private volatile boolean closed,busy;
    AppUpdates(MainActivity h){host=h;prefs=h.getSharedPreferences("updates",Context.MODE_PRIVATE);}
    void autoCheck(){if(System.currentTimeMillis()-prefs.getLong("attempt",0)>=86400000)check(false);}
    private boolean alive(){return !closed&&!host.isFinishing()&&!host.isDestroyed();}
    void check(boolean manual){
        if(busy){if(manual)host.toast("正在检查更新，请稍等");return;}busy=true;prefs.edit().putLong("attempt",System.currentTimeMillis()).apply();if(manual)host.toast("正在检查更新…");
        executor.execute(()->{try{
            JSONObject info=new ChatClient(ServiceEndpoint.origin()).request("/updates/android",null,null,false);
            if(!host.getPackageName().equals(info.optString("package")))throw new IOException("更新信息不匹配");
            long current=version(host.getPackageManager().getPackageInfo(host.getPackageName(),0));boolean newer=info.optBoolean("available")&&info.optLong("versionCode")>current;
            if(newer)validateMetadata(info);
            main.post(()->{busy=false;if(!alive())return;if(!newer){if(manual)host.toast("当前已是最新版本");return;}
                if(!manual&&prefs.getLong("ignored",0)==info.optLong("versionCode"))return;
                new AlertDialog.Builder(host).setTitle("发现新版本 "+info.optString("versionName")).setMessage(info.optString("notes","体验新版星屿")+"\n\n安装包约 "+Math.max(1,info.optLong("size")/1024)+" KB，点击后开始下载。").setNegativeButton("稍后",(d,w)->prefs.edit().putLong("ignored",info.optLong("versionCode")).apply()).setPositiveButton("下载更新",(d,w)->download(info)).show();
            });
        }catch(Exception e){main.post(()->{busy=false;if(manual&&alive())host.toast("检查更新失败，请稍后重试");});}});
    }
    private URL validateMetadata(JSONObject info)throws Exception{
        URI origin=URI.create(ServiceEndpoint.origin()),uri=new URI(info.getString("url"));
        if(!"https".equals(uri.getScheme())||!Objects.equals(origin.getHost(),uri.getHost())||uri.getPort()!=-1||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null||!uri.getRawPath().matches("/releases/[a-zA-Z0-9._-]+\\.apk"))throw new IOException("更新地址无效");
        if(!info.getString("sha256").matches("[a-f0-9]{64}")||info.getLong("size")<1||info.getLong("size")>24*1024*1024||info.getInt("minSdk")>Build.VERSION.SDK_INT)throw new IOException("此更新不适合当前设备");return uri.toURL();
    }
    private void download(JSONObject info){
        if(busy)return;busy=true;ProgressDialog progress=new ProgressDialog(host);progress.setTitle("正在下载更新");progress.setMessage("完成后将校验安装包");progress.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL);progress.setMax(100);progress.setCancelable(false);progress.show();
        executor.execute(()->{File part=null;try{
            URL url=validateMetadata(info);File dir=new File(host.getCacheDir(),"updates");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建下载目录");part=new File(dir,"download.part");File verified=new File(dir,"verified.apk");
            HttpURLConnection c=(HttpURLConnection)url.openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(12000);c.setReadTimeout(20000);c.setRequestProperty("Accept-Encoding","identity");
            long total=0,expected=info.getLong("size");MessageDigest digest=MessageDigest.getInstance("SHA-256");
            try{
                if(c.getResponseCode()!=200)throw new IOException("下载地址暂时不可用");
                try(InputStream in=c.getInputStream();OutputStream out=new FileOutputStream(part)){byte[] buffer=new byte[32768];int n,last=-1;while((n=in.read(buffer))!=-1){if(closed)throw new IOException("下载已取消");total+=n;if(total>expected)throw new IOException("安装包大小不匹配");digest.update(buffer,0,n);out.write(buffer,0,n);int value=(int)(total*100/expected);if(value!=last){last=value;main.post(()->{if(alive())progress.setProgress(value);});}}}
            }finally{c.disconnect();}
            if(total!=expected||!hex(digest.digest()).equals(info.getString("sha256")))throw new IOException("安装包校验失败，请重试");
            PackageManager pm=host.getPackageManager();int flags=Build.VERSION.SDK_INT>=28?PackageManager.GET_SIGNING_CERTIFICATES:PackageManager.GET_SIGNATURES;
            PackageInfo archive=pm.getPackageArchiveInfo(part.getAbsolutePath(),flags),installed=pm.getPackageInfo(host.getPackageName(),flags);
            if(archive==null||!host.getPackageName().equals(archive.packageName)||version(archive)!=info.getLong("versionCode")||version(archive)<=version(installed)||!signers(archive).equals(signers(installed)))throw new IOException("安装包版本或签名不匹配");
            if(verified.exists()&&!verified.delete())throw new IOException("无法替换更新文件");if(!part.renameTo(verified))throw new IOException("无法保存更新文件");
            main.post(()->{busy=false;if(!alive())return;progress.dismiss();install();});
        }catch(Exception e){if(part!=null)part.delete();final String message=e.getMessage();main.post(()->{busy=false;if(alive()){progress.dismiss();host.toast(message==null?"下载失败，请重试":message);}});}});
    }
    private void install(){
        if(!host.getPackageManager().canRequestPackageInstalls()){
            new AlertDialog.Builder(host).setTitle("允许安装更新").setMessage("请在系统设置中允许星屿安装应用，返回后点击“继续安装”。").setNegativeButton("稍后",null).setPositiveButton("打开设置",(d,w)->{try{host.startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+host.getPackageName())));main.postDelayed(()->{if(alive())new AlertDialog.Builder(host).setTitle("更新已下载").setMessage("设置完成后可继续安装。").setNegativeButton("稍后",null).setPositiveButton("继续安装",(a,b)->install()).show();},800);}catch(Exception e){host.toast("无法打开系统设置");}}).show();return;
        }
        try{Uri uri=Uri.parse("content://"+host.getPackageName()+".updates/apk");Intent i=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);i.setClipData(ClipData.newRawUri("星屿更新",uri));host.startActivity(i);}catch(Exception e){host.toast("无法打开系统安装程序，请稍后重试");}
    }
    private long version(PackageInfo p){return Build.VERSION.SDK_INT>=28?p.getLongVersionCode():p.versionCode;}
    private Set<String> signers(PackageInfo p)throws Exception{Signature[] signatures=Build.VERSION.SDK_INT>=28?(p.signingInfo==null?null:p.signingInfo.getApkContentsSigners()):p.signatures;if(signatures==null||signatures.length==0)throw new IOException("安装包签名缺失");Set<String> set=new HashSet<>();for(Signature s:signatures)set.add(hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));return set;}
    private String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte x:b)s.append(String.format(Locale.ROOT,"%02x",x&255));return s.toString();}
    void close(){closed=true;executor.shutdownNow();}
}
