package moe.cangku.xingyu_desktop;

import android.content.Context;
import android.util.Base64;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.time.Instant;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

/** Optional delivery of success metadata only; never forwards the website cookie. */
final class CheckinReceiptBridge {
    static String read(Context c,String key)throws Exception{
        String raw=c.getSharedPreferences("flutter_secure_vault",0).getString(key,null);if(raw==null)throw new IOException();
        String[] parts=raw.split(":",-1);if(parts.length!=2)throw new IOException();
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,store.getKey("xingyu.flutter.vault.v1",null),new GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)));cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
        return new String(cipher.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),StandardCharsets.UTF_8);
    }
    static String token(Context c,int uid)throws Exception{
        for(String key:new String[]{"checkin.cloud."+uid,"chat."+uid})try{
            JSONObject v=new JSONObject(read(c,key));int owner=key.startsWith("chat.")?(v.optJSONObject("user")==null?0:v.getJSONObject("user").optInt("id")):v.optInt("user_id");
            String token=v.optString("token");if(owner==uid&&token.matches("[a-f0-9]{64}")&&Instant.parse(v.getString("expires_at")).isAfter(Instant.now()))return token;
        }catch(Exception ignored){}
        throw new IOException();
    }
    static void publish(Context c,int uid,JSONObject event,java.util.function.BooleanSupplier active){
        HttpURLConnection conn=null;
        try{
            if(!active.getAsBoolean())return;
            String token=token(c,uid);
            URL url=new URL("https://xingyu-chat-ccjk45415.pages.dev/checkin/v1/events");
            conn=(HttpURLConnection)url.openConnection(NetworkProxy.forUrl(c,url));conn.setConnectTimeout(8000);conn.setReadTimeout(8000);conn.setInstanceFollowRedirects(false);conn.setRequestMethod("POST");conn.setDoOutput(true);
            conn.setRequestProperty("Authorization","Bearer "+token);conn.setRequestProperty("Content-Type","application/json");conn.setRequestProperty("Accept","application/json");
            JSONObject item=new JSONObject().put("time",event.getString("time")).put("client","android").put("method","background");
            byte[] bytes=new JSONObject().put("events",new JSONArray().put(item)).toString().getBytes(StandardCharsets.UTF_8);conn.setFixedLengthStreamingMode(bytes.length);
            if(!active.getAsBoolean())return;
            try(OutputStream out=conn.getOutputStream()){out.write(bytes);}conn.getResponseCode();
        }catch(Exception ignored){/* Durable local receipt is retried from Dart on next foreground. */}
        finally{if(conn!=null)conn.disconnect();}
    }
}
