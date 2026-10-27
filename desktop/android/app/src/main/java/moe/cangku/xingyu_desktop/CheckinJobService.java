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
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
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
    private static final String PREFS = "xingyu.checkin", COOKIE_KEY = "website.cookies";
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final ConcurrentHashMap<Integer, Work> running = new ConcurrentHashMap<>();
    private static final class Work {
        final int uid, jobId; final long epoch; final JobParameters parameters;
        volatile boolean stopped; volatile HttpURLConnection connection; volatile Future<?> future;
        String phase = "session"; int httpStatus;
        Work(int uid, long epoch, JobParameters parameters) {
            this.uid=uid; this.epoch=epoch; this.parameters=parameters; this.jobId=parameters.getJobId();
        }
        void stop() { stopped=true; if(connection!=null)connection.disconnect(); if(future!=null)future.cancel(true); }
    }
    static SharedPreferences prefs(Context c) { return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE); }
    static void configure(Context c, boolean enabled, int uid) {
        synchronized (LOCK) {
            SharedPreferences p=prefs(c);
            JobScheduler scheduler=c.getSystemService(JobScheduler.class);
            boolean same=p.getBoolean("enabled",false)==enabled && p.getInt("uid",0)==uid;
            if(!same) p.edit().putBoolean("enabled",enabled).putInt("uid",uid)
                .putLong("epoch",p.getLong("epoch",0)+1).remove("status").remove("time")
                .remove("retry."+CheckinPolicy.PERIODIC_JOB).remove("retry."+CheckinPolicy.INITIAL_JOB).apply();
            if(!enabled || uid<=0) {
                scheduler.cancel(CheckinPolicy.PERIODIC_JOB);scheduler.cancel(CheckinPolicy.INITIAL_JOB);return;
            }
            JobInfo existing=scheduler.getPendingJob(CheckinPolicy.PERIODIC_JOB);
            boolean migrate=p.getInt("schedule_version",0)!=CheckinPolicy.VERSION || existing==null || existing.getIntervalMillis()!=CheckinPolicy.PERIOD;
            if(same && !migrate) return;
            JobInfo periodic=new JobInfo.Builder(CheckinPolicy.PERIODIC_JOB,new ComponentName(c,CheckinJobService.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
                .setPeriodic(CheckinPolicy.PERIOD,CheckinPolicy.FLEX)
                .setBackoffCriteria(CheckinPolicy.BACKOFF,JobInfo.BACKOFF_POLICY_LINEAR).build();
            if(scheduler.schedule(periodic)!=JobScheduler.RESULT_SUCCESS) {
                p.edit().putBoolean("enabled",false).putString("status","schedule_failed").apply();
                throw new IllegalStateException("schedule");
            }
            p.edit().putInt("schedule_version",CheckinPolicy.VERSION).apply();
            // One initial attempt; normal application resumes do not recreate it.
            JobInfo initial=new JobInfo.Builder(CheckinPolicy.INITIAL_JOB,new ComponentName(c,CheckinJobService.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setMinimumLatency(0)
                .setBackoffCriteria(CheckinPolicy.BACKOFF,JobInfo.BACKOFF_POLICY_LINEAR).build();
            if(scheduler.schedule(initial)!=JobScheduler.RESULT_SUCCESS) p.edit().putString("status","waiting").apply();
        }
    }
    static Map<String,Object> status(Context c) {
        SharedPreferences p=prefs(c); Map<String,Object> out=new HashMap<>();
        String raw=p.getString("status","waiting"), time=p.getString("time","");
        String label="signed".equals(raw) ? (CheckinPolicy.today(time,Instant.now()) ? "今日已签到" : "上次后台签到成功，今日待确认")
            : "login_required".equals(raw) ? "需要重新登录"
            : "network".equals(raw) ? "网络暂不可用，等待系统重试"
            : "storage".equals(raw) ? "本机登录资料无法读取，请重新登录"
            : "schedule_failed".equals(raw) ? "系统暂时无法安排后台签到" : "等待系统调度";
        JobScheduler scheduler=c.getSystemService(JobScheduler.class);
        out.put("status",label);out.put("code",raw);out.put("time",time);out.put("uid",p.getInt("uid",0));
        try{java.util.List<Map<String,Object>> events=new java.util.ArrayList<>();org.json.JSONArray saved=new org.json.JSONArray(p.getString("events","[]"));for(int i=0;i<saved.length();i++){org.json.JSONObject event=saved.getJSONObject(i);if(event.optInt("uid")==p.getInt("uid",0)){Map<String,Object> item=new java.util.HashMap<>();for(String key:new String[]{"time","client","method"})item.put(key,event.optString(key));events.add(item);}}out.put("events",events);}catch(Exception ignored){}
        out.put("period_minutes",CheckinPolicy.PERIOD/60000);
        out.put("scheduled",scheduler.getPendingJob(CheckinPolicy.PERIODIC_JOB)!=null);
        out.put("phase",p.getString("phase",""));out.put("http_status",p.getInt("http_status",0));
        return out;
    }
    private boolean enabledFor(Work work) {
        SharedPreferences p=prefs(this);
        return p.getBoolean("enabled",false) && p.getInt("uid",0)==work.uid && p.getLong("epoch",0)==work.epoch;
    }
    private boolean active(Work work) {
        return !work.stopped && !Thread.currentThread().isInterrupted() && enabledFor(work);
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
    private JSONObject request(Work work, String path, boolean post, Map<String,HttpCookie> cookies) throws Exception {
        if (!active(work)) throw new InterruptedIOException();
        URL url = new URL("https://cangku.moe/api/v1/"+path);
        Proxy proxy = NetworkProxy.forUrl(this,url);
        HttpURLConnection connection = (HttpURLConnection)url.openConnection(proxy);
        work.connection = connection;
        if (!active(work)) { connection.disconnect(); throw new InterruptedIOException(); }
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
            if(code!=200 || work.httpStatus==0) work.httpStatus = code;
            if (code==401) throw new SecurityException();
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
        } finally { work.connection = null; connection.disconnect(); }
    }
    private JSONObject account(Work work, Map<String,HttpCookie> cookies) throws Exception {
        JSONObject user=request(work,"auth/me",false,cookies);
        if(user==null || user.optInt("id",0)<=0)throw new IOException();
        if(user.optInt("id",0)!=work.uid || user.optBoolean("is_banned") || user.optBoolean("should_verify_otp")) throw new SecurityException();
        return user;
    }
    private CheckinPolicy.Outcome runTask(Work work) {
        SharedPreferences p=prefs(this), vault=getSharedPreferences("flutter_secure_vault",MODE_PRIVATE);
        if(!active(work))return CheckinPolicy.Outcome.STOPPED;
        final String original=vault.getString(COOKIE_KEY,null);
        boolean performed=false;JSONObject eventToPublish=null;
        String status="network"; CheckinPolicy.Outcome outcome=CheckinPolicy.Outcome.TRANSIENT;
        try {
            if(original==null)throw new SecurityException();
            Map<String,HttpCookie> cookies=new LinkedHashMap<>();
            work.phase="session";
            JSONArray raw;
            try {raw=new JSONArray(decrypt(original));}
            catch(Exception error){status="storage";throw new SecurityException();}
            final Instant loaded=Instant.now();
            for(int i=0;i<raw.length();i++) for(HttpCookie cookie:HttpCookie.parse(raw.getJSONObject(i).getString("cookie"))) {
                String domain=cookie.getDomain();
                if((domain==null || domain.equals("cangku.moe") || domain.equals(".cangku.moe")) && !cookie.hasExpired()) cookies.put(cookie.getName(),cookie);
            }
            work.phase="account";
            JSONObject user=account(work,cookies);
            if(!active(work))return CheckinPolicy.Outcome.STOPPED;
            if(!user.optBoolean("is_signed") && user.optInt("is_signed",0)!=1) {
                synchronized(LOCK) {
                    if(!active(work) || !original.equals(vault.getString(COOKIE_KEY,null))) return CheckinPolicy.Outcome.TRANSIENT;
                }
                work.phase="signin";
                try {request(work,"user/signin",true,cookies);performed=true;} catch(Exception error){ /* Read authoritative state before any retry. */ }
                if(!active(work))return CheckinPolicy.Outcome.STOPPED;
                work.phase="verify";user=account(work,cookies);
            }
            if(user.optBoolean("is_signed") || user.optInt("is_signed",0)==1) {
                status="signed";outcome=CheckinPolicy.Outcome.SIGNED;
            }
            synchronized(LOCK) {
                if(active(work) && original.equals(vault.getString(COOKIE_KEY,null))) {
                    work.phase="storage";JSONArray saved=new JSONArray();
                    for(HttpCookie cookie:cookies.values()) if(!cookie.hasExpired()) {
                        String value=cookie.getName()+"="+cookie.getValue()+"; Path=/; Domain=cangku.moe; Secure";
                        if(cookie.getMaxAge()>=0) {
                            long remaining=cookie.getMaxAge()-Math.max(0,Instant.now().getEpochSecond()-loaded.getEpochSecond());
                            if(remaining<=0)continue;
                            value+="; Expires="+DateTimeFormatter.RFC_1123_DATE_TIME.format(Instant.now().plusSeconds(remaining).atZone(ZoneOffset.UTC));
                        }
                        saved.put(new JSONObject().put("cookie",value));
                    }
                    if(!vault.edit().putString(COOKIE_KEY,encrypt(saved.toString())).commit()) throw new IOException();
                }
            }
        } catch(SecurityException error) {
            if(!"storage".equals(status))status="login_required";outcome=CheckinPolicy.Outcome.LOGIN;
        } catch(Exception error) { /* Never persist session values, upstream bodies or exception messages. */ }
        synchronized(LOCK) {
            if(!active(work))return CheckinPolicy.Outcome.STOPPED;
            if(outcome==CheckinPolicy.Outcome.SIGNED&&performed){
                try{
                    JSONObject event=new JSONObject().put("uid",work.uid).put("time",Instant.now().toString()).put("client","android").put("method","background");
                    eventToPublish=event;
                    JSONArray old=new JSONArray(p.getString("events","[]")),events=new JSONArray();
                    for(int i=Math.max(0,old.length()-9);i<old.length();i++)events.put(old.get(i));events.put(event);p.edit().putString("events",events.toString()).commit();
                    NoticeBridge.show(this,new JSONObject().put("uid",work.uid).put("key","checkin:"+(Instant.now().toEpochMilli()/86400000L)).put("kind","checkin").put("title","签到成功").put("body","Android 客户端 · 后台自动签到"));
                }catch(Exception ignored){}
            }
            p.edit().putString("status",status).putString("time",Instant.now().toString())
                .putString("phase",work.phase).putInt("http_status",work.httpStatus).apply();
        }
        if(eventToPublish!=null&&active(work))CheckinReceiptBridge.publish(this,work.uid,eventToPublish,()->active(work));
        return outcome;
    }
    @Override public boolean onStartJob(JobParameters parameters) {
        final Work work;
        synchronized(LOCK) {
            SharedPreferences p=prefs(this);
            if(!p.getBoolean("enabled",false) || p.getInt("uid",0)<=0)return false;
            work=new Work(p.getInt("uid",0),p.getLong("epoch",0),parameters);
            if(running.putIfAbsent(work.jobId,work)!=null)return true;
        }
        work.future=executor.submit(()->{
            CheckinPolicy.Outcome outcome=CheckinPolicy.Outcome.TRANSIENT;
            try { outcome=runTask(work); }
            finally {
                boolean retry=false;
                synchronized(LOCK) {
                    if(active(work)) {
                        SharedPreferences p=prefs(this);String key="retry."+work.jobId;
                        int failures=outcome==CheckinPolicy.Outcome.TRANSIENT?p.getInt(key,0)+1:0;
                        retry=CheckinPolicy.retry(outcome,failures);
                        p.edit().putInt(key,retry?failures:0).apply();
                    }
                }
                running.remove(work.jobId,work);
                if(!work.stopped)jobFinished(parameters,retry);
            }
        });
        return true;
    }
    @Override public boolean onStopJob(JobParameters parameters) {
        Work work=running.remove(parameters.getJobId());
        if(work==null)return false;
        work.stop();return enabledFor(work);
    }
    @Override public void onDestroy() {
        for(Work work:running.values())work.stop();running.clear();executor.shutdownNow();super.onDestroy();
    }
}
