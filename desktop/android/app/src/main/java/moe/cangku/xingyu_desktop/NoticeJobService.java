package moe.cangku.xingyu_desktop;

import android.app.job.*;
import android.content.*;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import android.util.Base64;
import android.text.Html;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.*;
import java.util.concurrent.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

/** Bounded read-only work. Uses the same on-device Keystore as Flutter. */
public final class NoticeJobService extends JobService {
    private final ExecutorService executor=Executors.newSingleThreadExecutor();
    private volatile boolean stopped;
    private volatile HttpURLConnection connection;
    private Future<?> task;
    private int owner;
    private long epoch;
    private JSONObject options;
    private boolean active() {
        SharedPreferences p=NoticeBridge.prefs(this);
        return !stopped && !Thread.currentThread().isInterrupted() && p.getBoolean("enabled",false)
            && p.getInt("uid",0)==owner && p.getLong("epoch",0)==epoch;
    }
    private String secret(String key) throws Exception {
        String raw=getSharedPreferences("flutter_secure_vault",MODE_PRIVATE).getString(key,null);
        if(raw==null) throw new SecurityException();
        String[] parts=raw.split(":",-1); if(parts.length!=2)throw new SecurityException();
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,store.getKey("xingyu.flutter.vault.v1",null),new GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)));
        cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
        return new String(cipher.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),StandardCharsets.UTF_8);
    }
    private JSONObject get(String base,String path,String auth,boolean website) throws Exception {
        if(!active())throw new InterruptedException();
        URI uri=new URI(base);
        if(!"https".equals(uri.getScheme()) || uri.getHost()==null || uri.getUserInfo()!=null || uri.getPort()!=-1 || (uri.getPath()!=null && !uri.getPath().isEmpty()))throw new SecurityException();
        ConnectivityManager manager=getSystemService(ConnectivityManager.class);
        ProxyInfo info=manager==null?null:manager.getDefaultProxy();
        Proxy proxy=info!=null && info.getHost()!=null && info.getPort()>0?new Proxy(Proxy.Type.HTTP,new InetSocketAddress(info.getHost(),info.getPort())):Proxy.NO_PROXY;
        HttpURLConnection conn=(HttpURLConnection)new URL(base+path).openConnection(proxy);connection=conn;
        conn.setConnectTimeout(12000);conn.setReadTimeout(12000);conn.setInstanceFollowRedirects(false);
        conn.setRequestProperty("Accept","application/json");
        conn.setRequestProperty("User-Agent","Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/125.0.0.0 Mobile Safari/537.36");
        if(website) {
            conn.setRequestProperty("Cookie",auth);conn.setRequestProperty("Referer","https://cangku.moe/");
            conn.setRequestProperty("X-Requested-With","XMLHttpRequest");
        } else conn.setRequestProperty("Authorization","Bearer "+auth);
        try {
            int code=conn.getResponseCode();
            if(code==401 || code==419 || code>=300 && code<400)throw new SecurityException();
            if(code!=200)throw new IOException();
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            try(InputStream in=conn.getInputStream()) {byte[] block=new byte[4096];int n;while((n=in.read(block))!=-1){if(bytes.size()+n>512*1024)throw new IOException();bytes.write(block,0,n);}}
            JSONObject payload=new JSONObject(bytes.toString("UTF-8"));
            if(website && payload.optInt("code",-1)!=0)throw new IOException();
            return payload;
        } finally {conn.disconnect();if(connection==conn)connection=null;}
    }
    private void deliver(String key,String kind,String title,String body,int target,String channel) throws Exception {
        synchronized(NoticeBridge.LOCK) {
            if(!active() || !options.optBoolean(kind,true))return;
            NoticeBridge.show(this,new JSONObject().put("uid",owner).put("key",key).put("kind",kind)
                .put("title",title).put("body",plain(body)).put("target",target).put("channel",channel));
        }
    }
    private static String plain(String raw) {
        String text=Html.fromHtml(raw,Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+"," ").trim();
        return text.length()>160?text.substring(0,160):text;
    }
    private void site(String action,String cookies,JSONObject state) throws Exception {
        JSONObject response=get("https://cangku.moe","/api/v1/user/notification?action="+action+"&page=1&per_page=30&include=user%2Ccauser%2Csubject&with%5B0%5D=user&with%5B1%5D=causer&with%5B2%5D=subject",cookies,true);
        JSONArray list=response.optJSONArray("data");if(list==null)throw new IOException();
        Set<String> seen=new LinkedHashSet<>();JSONArray previous=state.optJSONArray(action);
        if(previous!=null)for(int i=0;i<previous.length();i++)seen.add(previous.optString(i));
        for(int i=list.length()-1;i>=0;i--) {
            JSONObject row=list.getJSONObject(i);String id=row.optString("id");if(id.isEmpty())continue;
            if(previous!=null && !seen.contains(id) && row.isNull("read_at")) {
                JSONObject user=row.optJSONObject("user"),subject=row.optJSONObject("subject"),causer=row.optJSONObject("causer");
                boolean post="post".equals(row.optString("subject_type"));
                String kind="vote".equals(action)?"like":post?"postReply":"commentReply";
                deliver(action+":"+id,kind,(user==null?"仓库用户":user.optString("nickname","仓库用户"))+("vote".equals(action)?"赞了":"回复了")+"你的"+(post?"帖子":"评论"),causer==null?"":causer.optString("content"),subject==null?0:subject.optInt(post?"id":"post_id"),"");
            }
            seen.add(id);
        }
        JSONArray saved=new JSONArray();int skip=Math.max(0,seen.size()-200);for(String id:seen)if(skip-->0){}else saved.put(id);state.put(action,saved);
    }
    private void dm(String origin,String token,JSONObject state) throws Exception {
        JSONArray list=get(origin,"/dm/v1/conversations",token,false).optJSONArray("conversations");if(list==null)throw new IOException();
        JSONObject seen=state.optJSONObject("dm");boolean first=seen==null;if(first)seen=new JSONObject();
        for(int i=list.length()-1;i>=0;i--) {
            JSONObject row=list.getJSONObject(i),peer=row.optJSONObject("peer"),message=row.optJSONObject("last_message");
            if(peer==null || message==null)continue;
            int id=message.optInt("id"),peerId=peer.optInt("id");String key=String.valueOf(peerId);
            if(!first && id>seen.optInt(key) && row.optInt("unread")>0 && message.optInt("sender_id")!=owner)
                deliver("dm:"+id,"dm",peer.optString("nickname","仓库用户")+" 发来私信",message.optString("text","[图片]"),peerId,"");
            seen.put(key,Math.max(id,seen.optInt(key)));
        }
        while(seen.length()>200)seen.remove(seen.keys().next());state.put("dm",seen);
    }
    private void chat(String origin,String token,String channel,JSONObject state) throws Exception {
        String key="chat:"+channel;boolean first=!state.has(key);long after=state.optLong(key),before=state.optLong(key+":before"),newest=state.optLong(key+":newest",after);
        for(int page=0;page<(first?1:3);page++) {
            JSONObject response=get(origin,"/v1/channels/"+channel+"/messages?limit=30"+(first?"":"&after="+after+(before>0?"&before="+before:"")),token,false);
            JSONArray list=response.optJSONArray("messages");if(list==null)throw new IOException();long oldest=Long.MAX_VALUE;
            for(int i=0;i<list.length();i++) {
                JSONObject m=list.getJSONObject(i),sender=m.optJSONObject("sender");long id=m.optLong("id");oldest=Math.min(oldest,id);newest=Math.max(newest,id);
                if(first || id<=after || sender==null || sender.optInt("id")==owner)continue;
                boolean mention=false;JSONArray mentions=m.optJSONArray("mentions");
                if(mentions!=null)for(int j=0;j<mentions.length();j++)if(mentions.getJSONObject(j).optInt("id")==owner)mention=true;
                JSONObject reply=m.optJSONObject("reply_to"),replySender=reply==null?null:reply.optJSONObject("sender");
                if(mention || replySender!=null && replySender.optInt("id")==owner)
                    deliver(key+":"+id,"chatMention",sender.optString("nickname","仓库用户")+(mention?" 艾特了你":" 回复了你"),m.optString("text","[图片]"),0,channel);
            }
            if(first || !response.optBoolean("has_older") || list.length()<30 || oldest<=after+1) {
                state.put(key,newest);state.remove(key+":before");state.remove(key+":newest");return;
            }
            before=oldest;
        }
        state.put(key+":before",before).put(key+":newest",newest);
    }
    private void runTask() {
        SharedPreferences p=NoticeBridge.prefs(this);owner=p.getInt("uid",0);epoch=p.getLong("epoch",0);
        if(!active() || !NoticeBridge.granted(this))return;
        String status="ok";
        try {
            options=new JSONObject(p.getString("preferences","{}"));
            JSONObject state=new JSONObject(p.getString("cursors","{}"));
            StringBuilder cookies=new StringBuilder();
            JSONArray saved=new JSONArray(secret("website.cookies"));
            for(int i=0;i<saved.length();i++)for(HttpCookie cookie:HttpCookie.parse(saved.getJSONObject(i).getString("cookie"))) {
                String domain=cookie.getDomain();if(!cookie.hasExpired() && (domain==null || domain.equals("cangku.moe") || domain.equals(".cangku.moe"))) {if(cookies.length()>0)cookies.append("; ");cookies.append(cookie.getName()).append('=').append(cookie.getValue());}
            }
            JSONObject user=get("https://cangku.moe","/api/v1/auth/me",cookies.toString(),true).optJSONObject("data");
            if(user==null || user.optInt("id")!=owner)throw new SecurityException();
            for(String action:new String[]{"reply","vote"})if(action.equals("reply")?(options.optBoolean("postReply",true)||options.optBoolean("commentReply",true)):options.optBoolean("like",true)) {
                try{site(action,cookies.toString(),state);}catch(Exception e){status="partial";}
            }
            try {
                JSONObject identity=new JSONObject(secret("chat."+owner));JSONObject profile=identity.optJSONObject("user");
                if(profile==null || profile.optInt("id")!=owner || !java.time.Instant.parse(identity.getString("expires_at")).isAfter(java.time.Instant.now()))throw new SecurityException();
                String origin=p.getString("origin",""),token=identity.getString("token");
                if(options.optBoolean("dm",true))try{dm(origin,token,state);}catch(Exception e){status="partial";}
                if(options.optBoolean("chatMention",true))for(String channel:new String[]{"1","2"})try{chat(origin,token,channel,state);}catch(Exception e){status="partial";}
            }catch(Exception e){status="partial";}
            synchronized(NoticeBridge.LOCK) {if(active())p.edit().putString("cursors",state.toString()).commit();}
        }catch(SecurityException e){status="login_required";}
        catch(Exception e){status="network";}
        if(active())p.edit().putString("status",status).putString("lastCheck",java.time.Instant.now().toString()).apply();
    }
    @Override public boolean onStartJob(JobParameters params) {
        stopped=false;task=executor.submit(()->{try{runTask();}finally{if(!stopped)jobFinished(params,false);}});return true;
    }
    @Override public boolean onStopJob(JobParameters params) {
        stopped=true;if(task!=null)task.cancel(true);HttpURLConnection conn=connection;if(conn!=null)conn.disconnect();return true;
    }
    @Override public void onDestroy(){stopped=true;executor.shutdownNow();super.onDestroy();}
}
