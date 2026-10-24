package moe.cangku.xingyu_desktop;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import android.util.Base64;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.*;
import java.util.concurrent.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

/** System-scheduled work, independent from the Activity and Flutter engine. */
public final class CheckinJobService extends JobService {
    static final Object LOCK = new Object();
    private static final int JOB = 73104;
    private static final String PREFS = "xingyu.checkin", COOKIE_KEY = "website.cookies";
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile boolean stopped;
    private Future<?> task;
    static SharedPreferences prefs(Context c) { return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE); }
    static void configure(Context c, boolean enabled, int uid) {
        synchronized (LOCK) {
            SharedPreferences p = prefs(c);
            boolean same = p.getBoolean("enabled", false) == enabled && p.getInt("uid", 0) == uid;
            if (!same) p.edit().putBoolean("enabled", enabled).putInt("uid", uid).putLong("epoch", p.getLong("epoch", 0)+1).remove("status").remove("time").apply();
            JobScheduler scheduler = (JobScheduler)c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            if (!enabled || uid <= 0) { scheduler.cancel(JOB); return; }
            if (same && scheduler.getPendingJob(JOB) != null) return;
            JobInfo job = new JobInfo.Builder(JOB, new ComponentName(c, CheckinJobService.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
                .setPeriodic(3*60*60*1000L, 30*60*1000L)
                .setBackoffCriteria(30*60*1000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build();
            if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) {
                p.edit().putBoolean("enabled", false).apply();
                throw new IllegalStateException("schedule");
            }
        }
    }
    static Map<String,Object> status(Context c) {
        SharedPreferences p = prefs(c); Map<String,Object> out = new HashMap<>();
        String raw = p.getString("status", "waiting");
        String label = "signed".equals(raw) ? "今日已签到" : "login_required".equals(raw) ? "需要重新登录" : "network".equals(raw) ? "网络暂不可用，等待下次尝试" : "等待系统调度";
        out.put("status", label); out.put("time", p.getString("time", "")); return out;
    }
    private boolean active(int uid, long epoch) {
        SharedPreferences p = prefs(this);
        return !stopped && p.getBoolean("enabled", false) && p.getInt("uid", 0)==uid && p.getLong("epoch", 0)==epoch;
    }
    private String decrypt(String encoded) throws Exception {
        String[] parts = encoded.split(":", -1); if(parts.length!=2) throw new IOException();
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, store.getKey("xingyu.flutter.vault.v1", null), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
        cipher.updateAAD(COOKIE_KEY.getBytes(StandardCharsets.UTF_8));
        return new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
    }
    private String encrypt(String raw) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, store.getKey("xingyu.flutter.vault.v1", null));
        cipher.updateAAD(COOKIE_KEY.getBytes(StandardCharsets.UTF_8));
        return Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)+":"+Base64.encodeToString(cipher.doFinal(raw.getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP);
    }
    private JSONObject request(String path, boolean post, Map<String,HttpCookie> cookies) throws Exception {
        URL url = new URL("https://cangku.moe/api/v1/"+path);
        ConnectivityManager cm = (ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
        ProxyInfo info = cm == null ? null : cm.getDefaultProxy();
        Proxy proxy = info != null && info.getHost()!=null && info.getPort()>0 ? new Proxy(Proxy.Type.HTTP, new InetSocketAddress(info.getHost(),info.getPort())) : Proxy.NO_PROXY;
        HttpURLConnection connection = (HttpURLConnection)url.openConnection(proxy);
        connection.setConnectTimeout(15000); connection.setReadTimeout(15000); connection.setInstanceFollowRedirects(false);
        connection.setRequestMethod(post ? "POST" : "GET");
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("Origin", "https://cangku.moe");
        connection.setRequestProperty("Referer", "https://cangku.moe/");
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/125.0.0.0 Mobile Safari/537.36");
        connection.setRequestProperty("X-Requested-With", "XMLHttpRequest");
        StringBuilder header = new StringBuilder();
        for (HttpCookie cookie: cookies.values()) if(!cookie.hasExpired()) { if(header.length()>0)header.append("; "); header.append(cookie.getName()).append('=').append(cookie.getValue()); }
        connection.setRequestProperty("Cookie",header.toString());
        HttpCookie csrf = cookies.get("XSRF-TOKEN");
        if (csrf != null) connection.setRequestProperty("X-XSRF-TOKEN", URLDecoder.decode(csrf.getValue(), "UTF-8"));
        try {
            if (post) { connection.setRequestProperty("Content-Type", "application/json"); connection.setDoOutput(true); try(OutputStream out=connection.getOutputStream()){out.write("{}".getBytes(StandardCharsets.UTF_8));} }
            int code = connection.getResponseCode();
            if (code==401 || code==419 || (code>=300 && code<400)) throw new SecurityException();
            if (code!=200) throw new IOException();
            for (Map.Entry<String,List<String>> entry:connection.getHeaderFields().entrySet()) {
                if (entry.getKey()!=null && entry.getKey().equalsIgnoreCase("Set-Cookie")) for(String value:entry.getValue()) for(HttpCookie cookie:HttpCookie.parse(value)) {
                    String domain=cookie.getDomain();
                    if(domain==null || domain.equals("cangku.moe") || domain.equals(".cangku.moe")) cookies.put(cookie.getName(), cookie);
                }
            }
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            try(InputStream in=connection.getInputStream()) { byte[] block=new byte[4096]; int n; while((n=in.read(block))!=-1) { if(bytes.size()+n>262144)throw new IOException(); bytes.write(block,0,n); } }
            JSONObject payload = new JSONObject(bytes.toString("UTF-8"));
            if(payload.optInt("code", -1)!=0) throw new IOException();
            return payload.optJSONObject("data");
        } finally { connection.disconnect(); }
    }
    private JSONObject account(int uid, Map<String,HttpCookie> cookies) throws Exception {
        JSONObject user=request("auth/me", false, cookies);
        if(user==null || user.optInt("id",0)!=uid || user.optBoolean("is_banned") || user.optBoolean("should_verify_otp"))throw new SecurityException();
        return user;
    }
    private void runTask() {
        SharedPreferences p=prefs(this), vault=getSharedPreferences("flutter_secure_vault",MODE_PRIVATE);
        final int uid=p.getInt("uid",0); final long epoch=p.getLong("epoch",0);
        if(!active(uid,epoch))return;
        final String original=vault.getString(COOKIE_KEY,null);
        String status="network";
        try {
            if(original==null)throw new SecurityException();
            Map<String,HttpCookie> cookies=new LinkedHashMap<>();
            JSONArray raw=new JSONArray(decrypt(original));
            for(int i=0;i<raw.length();i++) for(HttpCookie cookie:HttpCookie.parse(raw.getJSONObject(i).getString("cookie"))) {
                String domain=cookie.getDomain(); if(domain==null || domain.equals("cangku.moe") || domain.equals(".cangku.moe"))cookies.put(cookie.getName(),cookie);
            }
            JSONObject user=account(uid,cookies);
            if(!active(uid,epoch))return;
            if(!user.optBoolean("is_signed") && user.optInt("is_signed",0)!=1) {
                try { request("user/signin",true,cookies); } catch(Exception error) { /* Reconcile before retrying. */ }
                user=account(uid,cookies);
            }
            if(user.optBoolean("is_signed") || user.optInt("is_signed",0)==1)status="signed";
            // Never overwrite cookies refreshed by the foreground account.
            synchronized(LOCK) {
                if(active(uid,epoch) && original.equals(vault.getString(COOKIE_KEY,null))) {
                    JSONArray saved=new JSONArray();
                    for(HttpCookie cookie:cookies.values()) if(!cookie.hasExpired()) {
                        String value=cookie.getName()+"="+cookie.getValue()+"; Path=/; Domain=cangku.moe; Secure";
                        if(cookie.getMaxAge()>=0) value+="; Max-Age="+cookie.getMaxAge();
                        saved.put(new JSONObject().put("cookie",value));
                    }
                    vault.edit().putString(COOKIE_KEY,encrypt(saved.toString())).commit();
                }
            }
        } catch(SecurityException error) { status="login_required"; }
        catch(Exception error) { /* Do not record cookies, upstream bodies or exception messages. */ }
        if(active(uid,epoch)) p.edit().putString("status",status).putString("time",java.time.Instant.now().toString()).apply();
    }
    @Override public boolean onStartJob(JobParameters parameters) {
        stopped=false;
        task=executor.submit(()->{ try { runTask(); } finally { if(!stopped)jobFinished(parameters,false); } });
        return true;
    }
    @Override public boolean onStopJob(JobParameters parameters) { stopped=true; if(task!=null)task.cancel(true); return true; }
    @Override public void onDestroy() { stopped=true; executor.shutdownNow(); super.onDestroy(); }
}
