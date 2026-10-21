package moe.cangku.reader;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.net.CookieStore;
import java.net.HttpCookie;
import java.net.URI;
import java.security.KeyStore;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Expiry-aware private cookie jar, encrypted by a device-bound Android Keystore key. */
final class SessionStore implements CookieStore {
    private static final String ALIAS="cangku.session.v1";
    private final SharedPreferences prefs;
    private final Map<String,Entry> entries=new LinkedHashMap<>();
    private boolean persistent;
    private static class Entry {
        HttpCookie cookie; long until;
        Entry(HttpCookie c,long u){cookie=c;until=u;}
    }
    SessionStore(Context ctx) {
        prefs=ctx.getSharedPreferences("session",Context.MODE_PRIVATE);
        restore();
    }
    private String key(HttpCookie c){return c.getName()+"|"+c.getDomain()+"|"+c.getPath();}
    @Override public synchronized void add(URI uri,HttpCookie c) {
        if(uri==null || !UrlPolicy.isSite(uri.toString()))return;
        if(c.getDomain()==null)c.setDomain(uri.getHost());
        String domain=c.getDomain().replaceFirst("^\\.","");
        if(!"cangku.moe".equalsIgnoreCase(domain))return;
        if(c.getPath()==null)c.setPath("/");
        if(c.getMaxAge()==0){entries.remove(key(c));return;}
        long age=c.getMaxAge();
        long until=age<0 ? Long.MAX_VALUE : System.currentTimeMillis()+Math.min(age,31536000L)*1000;
        entries.put(key(c),new Entry(c,until));
    }
    @Override public synchronized List<HttpCookie> get(URI uri) {
        if(!UrlPolicy.isSite(uri.toString()))return Collections.emptyList();
        prune();
        List<HttpCookie> out=new ArrayList<>();
        String path=uri.getPath().isEmpty()?"/":uri.getPath();
        for(Entry e:entries.values()){
            String p=e.cookie.getPath();
            if(path.equals(p)||path.startsWith(p.endsWith("/")?p:p+"/"))out.add(e.cookie);
        }
        return out;
    }
    @Override public synchronized List<HttpCookie> getCookies(){prune();List<HttpCookie> out=new ArrayList<>();for(Entry e:entries.values())out.add(e.cookie);return out;}
    @Override public List<URI> getURIs(){return Collections.singletonList(URI.create(UrlPolicy.ORIGIN));}
    @Override public synchronized boolean remove(URI uri,HttpCookie c){return entries.remove(key(c))!=null;}
    @Override public synchronized boolean removeAll(){entries.clear();prefs.edit().clear().commit();persistent=false;return true;}
    private void prune(){entries.values().removeIf(e->e.until<=System.currentTimeMillis()||e.cookie.hasExpired());}
    synchronized boolean hasSession(){prune();return !entries.isEmpty();}
    synchronized void setPersistent(boolean value)throws Exception{persistent=value;if(value)save();else prefs.edit().clear().commit();}
    synchronized void persistIfEnabled()throws Exception{if(persistent)save();}
    private SecretKey secret()throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);
        if(ks.containsAlias(ALIAS))return (SecretKey)ks.getKey(ALIAS,null);
        KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return g.generateKey();
    }
    private void save()throws Exception {
        prune();JSONArray a=new JSONArray();
        for(Entry e:entries.values())a.put(new JSONObject().put("name",e.cookie.getName()).put("value",e.cookie.getValue())
                .put("domain",e.cookie.getDomain()).put("path",e.cookie.getPath()).put("version",e.cookie.getVersion()).put("secure",e.cookie.getSecure()).put("httpOnly",e.cookie.isHttpOnly()).put("until",e.until));
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,secret());
        byte[] bytes=cipher.doFinal(a.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
        if(!prefs.edit().putString("iv",Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP)).putString("payload",Base64.encodeToString(bytes,Base64.NO_WRAP)).commit())throw new java.io.IOException("无法保存登录状态");
    }
    private void restore(){
        try{
            String p=prefs.getString("payload",null);if(p==null)return;
            Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,secret(),new GCMParameterSpec(128,Base64.decode(prefs.getString("iv",""),Base64.NO_WRAP)));
            JSONArray a=new JSONArray(new String(c.doFinal(Base64.decode(p,Base64.NO_WRAP)),java.nio.charset.StandardCharsets.UTF_8));
            for(int i=0;i<a.length();i++){
                JSONObject o=a.getJSONObject(i);long until=o.getLong("until");if(until<=System.currentTimeMillis())continue;
                HttpCookie h=new HttpCookie(o.getString("name"),o.getString("value"));h.setVersion(o.optInt("version",0));h.setDomain(o.getString("domain"));h.setPath(o.getString("path"));h.setSecure(o.getBoolean("secure"));h.setHttpOnly(o.optBoolean("httpOnly"));
                if(until!=Long.MAX_VALUE)h.setMaxAge(Math.max(1,(until-System.currentTimeMillis())/1000));
                entries.put(key(h),new Entry(h,until));
            }
            persistent=true;
        }catch(Exception e){entries.clear();prefs.edit().clear().commit();}
    }
}
