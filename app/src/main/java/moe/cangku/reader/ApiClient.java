package moe.cangku.reader;

import android.content.Context;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class ApiClient {
    static final String UA="Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/125.0.0.0 Mobile Safari/537.36";
    final SessionStore sessions;
    private final CookieManager cookies;
    private long generation;
    static class ApiException extends IOException {
        final int status;
        ApiException(int s,String message){super(message);status=s;}
    }
    ApiClient(Context ctx){sessions=new SessionStore(ctx);cookies=new CookieManager(sessions,CookiePolicy.ACCEPT_ORIGINAL_SERVER);}
    synchronized void clear(){generation++;sessions.removeAll();}
    private synchronized long version(){return generation;}
    private synchronized Map<String,String> sessionHeaders(URI uri,long expected)throws Exception {
        if(expected!=generation)throw new IOException("账号已切换，请重试");
        Map<String,String> result=new LinkedHashMap<>();
        for(Map.Entry<String,List<String>> e:cookies.get(uri,Collections.emptyMap()).entrySet())result.put(e.getKey(),String.join("; ",e.getValue()));
        for(HttpCookie h:sessions.get(uri))if(h.getName().equals("XSRF-TOKEN"))result.put("X-XSRF-TOKEN",URLDecoder.decode(h.getValue(),"UTF-8"));
        return result;
    }
    JSONObject get(String path,Map<String,String> params)throws Exception{return request("GET",url(path,params),null,true);}
    JSONObject post(String path,JSONObject body)throws Exception{return request("POST",url(path,null),body,true);}
    void bootstrap()throws Exception{request("GET",UrlPolicy.ORIGIN+"/login",null,false);}
    /** Called only after the user enables private messaging and accepts identity verification. */
    JSONObject enablePrivateMessaging(long expectedUser)throws Exception{
        return verifyMessagingProfile(expectedUser,null);
    }
    JSONObject syncMessagingProfile(long expectedUser,String token)throws Exception{
        return verifyMessagingProfile(expectedUser,token);
    }
    private JSONObject verifyMessagingProfile(long expectedUser,String token)throws Exception{
        long requested=version();
        URI endpoint=URI.create(UrlPolicy.ORIGIN+"/api/v1/auth/me");
        List<String> values=cookies.get(endpoint,Collections.emptyMap()).get("Cookie");
        String cookie=values==null?"":String.join("; ",values);
        if(cookie.isEmpty()||expectedUser<=0)throw new IOException("请先重新登录官网账号");
        JSONObject payload=new JSONObject().put("site_cookie",cookie);if(token==null)payload.put("expected_user_id",expectedUser);
        JSONObject result=new ChatClient(ServiceEndpoint.origin()).request(token==null?"/dm/v1/session":"/dm/v1/profile/sync",payload,token,false);
        if(requested!=version())throw new IOException("账号已切换，请重新开通私信");
        if(result.getJSONObject("user").optLong("id")!=expectedUser)throw new IOException("私信身份验证不一致");
        return result;
    }
    JSONObject login(String account,String password,boolean remember)throws Exception {
        clear();bootstrap();
        JSONObject r=post("auth/login",new JSONObject().put("login",account).put("password",password).put("remember",remember).put("include","roles,permissions,meta"));
        JSONObject u=r.getJSONObject("data");
        if(u.optBoolean("should_verify_otp"))throw new ApiException(428,"该账号需要二次验证，请先在官网完成验证");
        sessions.setPersistent(remember);return u;
    }
    private String url(String path,Map<String,String> params)throws Exception {
        if(!path.matches("[a-zA-Z/]+"))throw new IOException("无效接口");
        StringBuilder s=new StringBuilder(UrlPolicy.ORIGIN+"/api/v1/"+path);
        if(params!=null&&!params.isEmpty()){
            s.append('?');for(Map.Entry<String,String> e:params.entrySet())s.append(URLEncoder.encode(e.getKey(),"UTF-8")).append('=').append(URLEncoder.encode(e.getValue(),"UTF-8")).append('&');
        }return s.toString();
    }
    static Map<String,String> params(String... pairs){Map<String,String> m=new LinkedHashMap<>();for(int i=0;i<pairs.length;i+=2)m.put(pairs[i],pairs[i+1]);return m;}
    private JSONObject request(String method,String value,JSONObject body,boolean json)throws Exception {
        if(!UrlPolicy.isSite(value))throw new IOException("接口地址无效");
        long requestGeneration=version();
        URI uri=URI.create(value);HttpURLConnection c=(HttpURLConnection)uri.toURL().openConnection();
        c.setInstanceFollowRedirects(false);c.setConnectTimeout(18000);c.setReadTimeout(25000);c.setRequestMethod(method);
        c.setRequestProperty("User-Agent",UA);c.setRequestProperty("Accept",json?"application/json":"text/html");
        c.setRequestProperty("Origin",UrlPolicy.ORIGIN);c.setRequestProperty("Referer",UrlPolicy.ORIGIN+"/");c.setRequestProperty("X-Requested-With","XMLHttpRequest");
        for(Map.Entry<String,String> e:sessionHeaders(uri,requestGeneration).entrySet())c.setRequestProperty(e.getKey(),e.getValue());
        if(body!=null){
            c.setRequestProperty("Content-Type","application/json; charset=utf-8");c.setDoOutput(true);
            if(requestGeneration!=version()){c.disconnect();throw new IOException("账号已切换，请重试");}
            try(OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}
        }
        try{
            int status=c.getResponseCode();
            synchronized(this){if(requestGeneration!=generation)throw new IOException("请求已取消");cookies.put(uri,c.getHeaderFields());}
            if(status==401||status==419||status==302||status==303)throw new ApiException(status,"登录已过期，请重新登录");
            InputStream stream=status>=400?c.getErrorStream():c.getInputStream();
            String raw=read(stream,6*1024*1024);
            if(!json){if(status>=400)throw new ApiException(status,"网站暂时无法连接（"+status+"）");return new JSONObject();}
            JSONObject result;
            try{result=new JSONObject(raw);}catch(JSONException e){throw new ApiException(status,"网站返回了非数据页面，请稍后重试或在官网检查访问状态");}
            if(status>=400||result.optInt("code",0)!=0)throw new ApiException(status,message(result.opt("message")));
            JSONObject data=result.optJSONObject("data");
            if(data!=null&&data.optBoolean("should_verify_otp"))throw new ApiException(428,"该账号需要在官网完成二次验证");
            synchronized(this){if(requestGeneration!=generation)throw new IOException("请求已取消");sessions.persistIfEnabled();}
            return result;
        }finally{c.disconnect();}
    }
    JSONObject upload(String path,String field,byte[] bytes,Map<String,String> fields)throws Exception {return upload(path,field,bytes,fields,"image/jpeg");}
    long sessionVersion(){return version();}
    JSONObject upload(String path,String field,byte[] bytes,Map<String,String> fields,String mediaType)throws Exception {return upload(path,field,bytes,fields,mediaType,-1);}
    JSONObject upload(String path,String field,byte[] bytes,Map<String,String> fields,String mediaType,long expectedVersion)throws Exception {
        String extension;switch(mediaType){case "image/jpeg":extension="jpg";break;case "image/png":extension="png";break;case "image/gif":extension="gif";break;case "image/webp":extension="webp";break;default:throw new IOException("图片格式不支持");}
        if(!field.matches("[a-zA-Z]+")||bytes.length>2*1024*1024)throw new IOException("图片不得超过 2MB");
        long requestGeneration=version();if(expectedVersion>=0&&requestGeneration!=expectedVersion)throw new IOException("账号已切换，已取消上传");URI uri=URI.create(url(path,null));
        HttpURLConnection c=(HttpURLConnection)uri.toURL().openConnection();
        String boundary="Cangku"+UUID.randomUUID().toString().replace("-","");
        c.setRequestMethod("POST");c.setDoOutput(true);c.setInstanceFollowRedirects(false);c.setConnectTimeout(18000);c.setReadTimeout(35000);
        c.setRequestProperty("User-Agent",UA);c.setRequestProperty("Accept","application/json");c.setRequestProperty("Origin",UrlPolicy.ORIGIN);c.setRequestProperty("Referer",UrlPolicy.ORIGIN+"/");
        c.setRequestProperty("X-Requested-With","XMLHttpRequest");c.setRequestProperty("Content-Type","multipart/form-data; boundary="+boundary);
        for(Map.Entry<String,String> e:sessionHeaders(uri,requestGeneration).entrySet())c.setRequestProperty(e.getKey(),e.getValue());
        try{
            if(requestGeneration!=version())throw new IOException("账号已切换，请重试");
            try(OutputStream out=c.getOutputStream()){
                if(fields!=null)for(Map.Entry<String,String> e:fields.entrySet()){
                    if(!e.getKey().matches("[a-zA-Z_]+"))throw new IOException("无效字段");
                    out.write(("--"+boundary+"\r\nContent-Disposition: form-data; name=\""+e.getKey()+"\"\r\n\r\n"+e.getValue()+"\r\n").getBytes(StandardCharsets.UTF_8));
                }
                out.write(("--"+boundary+"\r\nContent-Disposition: form-data; name=\""+field+"\"; filename=\"upload."+extension+"\"\r\nContent-Type: "+mediaType+"\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                out.write(bytes);out.write(("\r\n--"+boundary+"--\r\n").getBytes(StandardCharsets.UTF_8));
            }
            int status=c.getResponseCode();
            synchronized(this){if(requestGeneration!=generation)throw new IOException("请求已取消");cookies.put(uri,c.getHeaderFields());}
            if(status==401||status==419)throw new ApiException(status,"登录已过期，请重新登录");
            String raw=read(status>=400?c.getErrorStream():c.getInputStream(),2*1024*1024);
            JSONObject result;try{result=new JSONObject(raw);}catch(JSONException e){throw new ApiException(status,"上传服务暂不可用，请重试");}
            if(status>=400||result.optInt("code",0)!=0)throw new ApiException(status,message(result.opt("message")));
            synchronized(this){if(requestGeneration!=generation)throw new IOException("请求已取消");sessions.persistIfEnabled();}
            return result;
        }finally{c.disconnect();}
    }
    private String message(Object value){
        if(value instanceof JSONObject){JSONObject o=(JSONObject)value;Iterator<String> keys=o.keys();if(keys.hasNext()){Object x=o.opt(keys.next());if(x instanceof JSONArray)return ((JSONArray)x).optString(0,"请求失败");return String.valueOf(x);}}
        return value==null?"请求失败，请稍后重试":String.valueOf(value);
    }
    static String read(InputStream in,int limit)throws IOException {
        if(in==null)return "";try(InputStream stream=in;ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] b=new byte[8192];int n,total=0;while((n=stream.read(b))!=-1){total+=n;if(total>limit)throw new IOException("返回内容过大");out.write(b,0,n);}return out.toString("UTF-8");
        }
    }
}
