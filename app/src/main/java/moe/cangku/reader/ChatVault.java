package moe.cangku.reader;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.*;
import android.util.Base64;
import org.json.JSONObject;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

/** Device-encrypted service identity. Website passwords and cookies are never stored here. */
final class ChatVault {
    private final SharedPreferences prefs;
    private final String alias;
    ChatVault(Context context){this(context,"chatIdentity","cangku.chat.v1");}
    ChatVault(Context context,String name,String keyAlias){prefs=context.getSharedPreferences(name,Context.MODE_PRIVATE);alias=keyAlias;}
    private SecretKey key()throws Exception{
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);
        if(ks.containsAlias(alias))return (SecretKey)ks.getKey(alias,null);
        KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());return g.generateKey();
    }
    String address(long owner){return prefs.getString(owner+".server","");}
    String nickname(long owner){return prefs.getString(owner+".nickname","星屿旅人");}
    void address(long owner,String server,String name){prefs.edit().putString(owner+".server",server).putString(owner+".nickname",name).apply();}
    void save(long owner,String server,JSONObject session)throws Exception{
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key());c.updateAAD((owner+"|"+server).getBytes(StandardCharsets.UTF_8));
        String payload=Base64.encodeToString(c.doFinal(session.toString().getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);
        if(!prefs.edit().putString(owner+".payload",payload).putString(owner+".iv",Base64.encodeToString(c.getIV(),Base64.NO_WRAP)).commit())throw new java.io.IOException("无法保存聊天身份");
    }
    JSONObject load(long owner,String server){
        try{String p=prefs.getString(owner+".payload",null);if(p==null)return null;Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(prefs.getString(owner+".iv",""),Base64.NO_WRAP)));c.updateAAD((owner+"|"+server).getBytes(StandardCharsets.UTF_8));return new JSONObject(new String(c.doFinal(Base64.decode(p,Base64.NO_WRAP)),StandardCharsets.UTF_8));}catch(Exception e){clear(owner);return null;}
    }
    void clear(long owner){prefs.edit().remove(owner+".payload").remove(owner+".iv").apply();}
}
