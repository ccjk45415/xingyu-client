package moe.cangku.reader;

import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

/** Separate transport: no CookieManager, no website authentication, no cross-origin redirects. */
final class ChatClient {
    static class Failure extends IOException {
        final int status;
        Failure(int status,String message){super(message);this.status=status;}
    }
    final String origin;
    private volatile HttpURLConnection polling;
    ChatClient(String server){origin=ChatRules.server(server);if(origin.isEmpty())throw new IllegalArgumentException("请输入有效的 HTTPS 聊天室地址");}
    JSONObject request(String path,JSONObject body,String token,boolean poll)throws Exception{
        if(!path.startsWith("/")||path.startsWith("//")||path.contains("\\"))throw new IOException("无效聊天室路径");
        HttpURLConnection c=(HttpURLConnection)new URL(origin+path).openConnection();
        c.setUseCaches(false);c.setRequestProperty("Cache-Control","no-cache");
        c.setInstanceFollowRedirects(false);c.setConnectTimeout(12000);c.setReadTimeout(poll?32000:18000);
        c.setRequestMethod(body==null?"GET":"POST");c.setRequestProperty("Accept","application/json");c.setRequestProperty("User-Agent","XingyuChat/1");
        if(token!=null&&!token.isEmpty())c.setRequestProperty("Authorization","Bearer "+token);
        if(poll)polling=c;
        try{
            if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");try(OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}}
            int status=c.getResponseCode();if(status>=300&&status<400)throw new Failure(status,"聊天室地址发生跳转，请填写最终的 HTTPS 地址");
            JSONObject result;try{result=new JSONObject(ApiClient.read(status>=400?c.getErrorStream():c.getInputStream(),512*1024));}catch(JSONException e){throw new Failure(status,"这个地址没有返回聊天室数据，请检查服务端地址");}
            if(status>=400)throw new Failure(status,result.optString("error","聊天室暂时无法连接（"+status+"）"));return result;
        }finally{if(poll&&polling==c)polling=null;c.disconnect();}
    }
    void verify()throws Exception{JSONObject health=request("/health",null,null,false);if(!"xingyu-chat".equals(health.optString("service"))||health.optInt("protocol")!=3||health.optInt("channel_count")!=2)throw new IOException("聊天室服务尚未就绪，请稍后再试");}
    void cancelPoll(){HttpURLConnection c=polling;if(c!=null)ChatSocket.closeTransport(c::disconnect);}
}
