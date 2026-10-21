package moe.cangku.reader;

import android.text.Html;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.*;
import java.util.*;
import java.util.regex.*;

/** Isolated native transport: never attaches website cookies to public pages or an AI provider. */
final class AiClient {
    static final class Failure extends IOException {final int status;Failure(int s,String m){super(m);status=s;}}
    static final String[] TYPES={"auto","game","comic","asmr","animation","other"};
    static final String[] TYPE_NAMES={"自动识别","游戏","漫画 / 同人志","ASMR / 音声","动画","其他作品"};
    static final String PROMPT=SourceTranslation.PROMPT;
    private volatile HttpURLConnection connection;
    volatile boolean closed;
    void close(){closed=true;HttpURLConnection c=connection;if(c!=null)new Thread(c::disconnect,"ai-cancel").start();}
    static URL endpoint(String raw)throws Exception{
        URI u=new URI(raw.trim());if(!"https".equals(u.getScheme())||u.getHost()==null||u.getRawUserInfo()!=null||u.getRawQuery()!=null||u.getRawFragment()!=null)throw new IOException("API地址须为不含账号、查询参数的HTTPS地址");String path=u.getPath().replaceAll("/+$","");if(!path.endsWith("/chat/completions"))path+=path.isEmpty()?"/v1/chat/completions":"/chat/completions";return new URI("https",null,u.getHost(),u.getPort(),path,null,null).toURL();
    }
    static URL sourceUrl(String raw)throws Exception{
        URI u=new URI(raw.trim());String host=u.getHost();if(!"https".equals(u.getScheme())||host==null||u.getRawUserInfo()!=null||u.getPort()!=-1&&u.getPort()!=443||!host.contains(".")||host.contains(":")||host.matches("[0-9.]+")||host.matches("(?i).*(^|\\.)(local|localhost|internal|test|invalid)$"))throw new IOException("请使用公开HTTPS作品链接");return new URI("https",null,host,u.getPort(),u.getPath(),u.getQuery(),null).toURL();
    }
    static boolean publicAddress(InetAddress ip){return SourceNetworkRules.publicAddress(ip);}
    private final Map<String,Long> publicDns=new HashMap<>();
    private void checkSourceHost(String host)throws Exception{
        InetAddress[] ips=InetAddress.getAllByName(host);
        if(!SourceNetworkRules.needsPublicConfirmation(ips))return;
        if(publicDns.getOrDefault(host,0L)>System.currentTimeMillis())return;
        // Confirm only the domain through fixed HTTPS resolvers. Continue through the user's
        // original hostname/proxy with normal certificate and hostname validation intact.
        for(String resolver:new String[]{"https://dns.google/resolve","https://cloudflare-dns.com/dns-query"}){
            HttpURLConnection c=null;
            try{
                URL url=new URL(resolver+"?name="+URLEncoder.encode(host,"UTF-8")+"&type=A"+(resolver.contains("dns.google")?"&edns_client_subnet=0.0.0.0%2F0":""));
                c=open(url,null,null,12000);c.setRequestProperty("Accept","application/dns-json");
                if(c.getResponseCode()!=200)continue;
                JSONObject answer=new JSONObject(ApiClient.read(c.getInputStream(),16384));JSONArray questions=answer.optJSONArray("Question"),records=answer.optJSONArray("Answer");
                if(answer.optInt("Status",-1)!=0||answer.optBoolean("TC")||questions==null||questions.length()!=1||!questions.getJSONObject(0).optString("name").replaceFirst("\\.$","").equalsIgnoreCase(host.replaceFirst("\\.$",""))||questions.getJSONObject(0).optInt("type")!=1||records==null||records.length()>32)break;
                boolean found=false,valid=true;
                for(int i=0;i<records.length();i++){JSONObject record=records.getJSONObject(i);int type=record.optInt("type");if(type!=1&&type!=28)continue;String ip=record.optString("data");if(!ip.matches(type==1?"[0-9.]+":"[0-9a-fA-F:]+")||!publicAddress(InetAddress.getByName(ip))){valid=false;break;}found=true;}
                if(found&&valid){if(closed)throw new IOException("已取消");publicDns.put(host,System.currentTimeMillis()+60000);return;}break;
            }catch(Exception error){if(closed)throw new IOException("已取消");}
            finally{if(c!=null){c.disconnect();if(connection==c)connection=null;}}
        }
        throw new IOException("当前代理DNS无法确认公开网页，请重试或粘贴作品介绍；无需关闭代理");
    }
    private HttpURLConnection open(URL url,JSONObject body,String token,int timeout)throws Exception{
        if(closed)throw new IOException("已取消");HttpURLConnection c=(HttpURLConnection)url.openConnection();connection=c;c.setUseCaches(false);c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(timeout);c.setRequestProperty("User-Agent","Xingyu-AI/1");c.setRequestProperty("Accept",body==null?"application/json,text/html":"application/json");
        if(token!=null&&!token.isEmpty())c.setRequestProperty("Authorization","Bearer "+token);
        if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");try(OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}}
        return c;
    }
    JSONObject json(URL url,JSONObject body,String token,boolean builtin)throws Exception{
        HttpURLConnection c=open(url,body,token,builtin&&url.getPath().equals("/ai/v2/draft")?240000:120000);try{int status=c.getResponseCode();if(status>=300){String error="服务返回 "+status+"，请检查地址、权限、额度及模型（不跟随跳转）";if(builtin&&status>=400)try{error=new JSONObject(ApiClient.read(c.getErrorStream(),32768)).optString("error",error);}catch(Exception ignored){}throw new Failure(status,error);}
            try{return new JSONObject(ApiClient.read(c.getInputStream(),4*1024*1024));}catch(JSONException e){throw new IOException("服务没有返回JSON，请检查接口地址");}
        }finally{c.disconnect();if(connection==c)connection=null;}
    }
    static String pageText(String raw){String plain=raw.replaceAll("(?is)<(script|style|nav|header|footer|noscript|iframe|form)\\b[^>]*>.*?</\\1\\s*>","");return (meta(raw,"og:title")+"\n"+meta(raw,"og:description")+"\n"+meta(raw,"description")+"\n"+Html.fromHtml(plain,Html.FROM_HTML_MODE_COMPACT).toString()).replaceAll("[ \\t\\r]+"," ").replaceAll("\\n\\s*\\n+","\n").trim();}
    private static String meta(String raw,String name){Matcher m=Pattern.compile("(?is)<meta\\b[^>]*>").matcher(raw);while(m.find()){String tag=m.group();if(tag.matches("(?is).*?(?:property|name)\\s*=\\s*['\"]"+Pattern.quote(name)+"['\"].*")){Matcher content=Pattern.compile("(?is)content\\s*=\\s*(['\"])(.*?)\\1").matcher(tag);if(content.find())return Html.fromHtml(content.group(2),Html.FROM_HTML_MODE_LEGACY).toString();}}return "";}
    JSONObject source(String raw)throws Exception{
        URL url=sourceUrl(SourceDocument.desktopUrl(raw));Matcher steam=Pattern.compile("^/app/(\\d+)").matcher(url.getPath());
        if(url.getHost().equals("store.steampowered.com")&&steam.find())try{String id=steam.group(1);JSONObject d=json(new URL("https://store.steampowered.com/api/appdetails?appids="+id+"&l=schinese"),null,null,false).getJSONObject(id).getJSONObject("data");JSONObject source=SourceDocument.parse(d.optString("detailed_description"),url.toString());source.put("title",d.optString("name")).put("cover",d.optString("header_image"));return source;}catch(Exception e){if(closed)throw e;}
        for(int i=0;i<4;i++){
            checkSourceHost(url.getHost());
            HttpURLConnection c=open(url,null,null,25000);try{int code=c.getResponseCode();if(code>=300&&code<400){String to=c.getHeaderField("Location");if(to==null)throw new IOException("来源跳转无效");url=sourceUrl(new URL(url,to).toString());continue;}
                String ct=c.getContentType();if(code!=200||ct==null||!ct.matches("(?is)(text/html|application/xhtml\\+xml|text/plain).*"))throw new IOException("网页无法直接提取，请粘贴公开作品介绍");
                ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){if(out.size()+n>1024*1024)throw new IOException("网页过大，请粘贴作品介绍");out.write(buf,0,n);}}
                Charset charset=StandardCharsets.UTF_8;Matcher cm=Pattern.compile("(?i)charset=([a-zA-Z0-9_-]+)").matcher(ct);if(cm.find())try{charset=Charset.forName(cm.group(1));}catch(Exception ignored){}
                String html=new String(out.toByteArray(),charset);return SourceDocument.parse(html,url.toString());
            }finally{c.disconnect();if(connection==c)connection=null;}
        }throw new IOException("来源跳转过多，请粘贴作品介绍");
    }
    JSONObject custom(String address,String key,String model,JSONObject material)throws Exception{
        if(model.trim().isEmpty())throw new IOException("请填写模型名称");JSONArray sources=new JSONArray(material.getJSONArray("sources").toString());if(!material.optString("material").trim().isEmpty())sources.getJSONObject(0).getJSONArray("blocks").put(new JSONObject().put("kind","p").put("text",material.getString("material")));
        SourceTranslation.Plan plan=new SourceTranslation.Plan(sources);Map<String,String> values=new HashMap<>();
        for(JSONArray chunk:plan.chunks){JSONObject request=new JSONObject().put("model",model.trim()).put("stream",false).put("messages",new JSONArray().put(new JSONObject().put("role","system").put("content",SourceTranslation.PROMPT)).put(new JSONObject().put("role","user").put("content",new JSONObject().put("segments",chunk).toString())));JSONObject result=json(endpoint(address),request,key.trim(),false);JSONArray choices=result.optJSONArray("choices");if(choices==null||choices.length()==0)throw new IOException("接口未返回翻译结果");values.putAll(SourceTranslation.translations(choices.getJSONObject(0).getJSONObject("message").getString("content"),chunk));int total=0;for(String text:values.values())total+=text.length();if(total>900000)throw new IOException("译文超出编辑器容量，原文已保留");}
        return plan.assemble(sources,material.optString("type","auto"),values);
    }
    static JSONObject validate(JSONObject d,JSONArray sources,boolean service)throws Exception{
        if(d.optJSONArray("blocks")!=null){JSONArray blocks=d.getJSONArray("blocks");if(!(d.opt("title") instanceof String)||d.optJSONArray("sources")==null)throw new IOException("译文结构错误");for(int i=0;i<blocks.length();i++){JSONObject v=blocks.getJSONObject(i);if(v.optString("kind").equals("image"))sourceUrl(v.getString("url"));else if(!Arrays.asList("p","h2","h3","li","quote").contains(v.optString("kind"))||!(v.opt("text") instanceof String))throw new IOException("译文段落错误");}for(int i=0;i<d.getJSONArray("sources").length();i++)sourceUrl(d.getJSONArray("sources").getJSONObject(i).getString("url"));return d;}
        if(d.has("error")||!Arrays.asList(TYPES).subList(1,TYPES.length).contains(d.optString("type"))||!(d.opt("title") instanceof String)||d.getString("title").trim().isEmpty()||!(d.opt("summary") instanceof String))throw new IOException("未获得有效作品草稿");
        JSONArray metadata=d.getJSONArray("metadata"),sections=d.getJSONArray("sections"),tags=d.getJSONArray("tags");for(int i=0;i<metadata.length();i++){JSONObject v=metadata.getJSONObject(i);if(!(v.get("label") instanceof String)||!(v.get("value") instanceof String))throw new IOException("草稿信息格式错误");}for(int i=0;i<sections.length();i++){JSONObject v=sections.getJSONObject(i);if(!(v.get("heading") instanceof String)||!(v.get("text") instanceof String))throw new IOException("草稿正文格式错误");}for(int i=0;i<tags.length();i++)if(!(tags.get(i) instanceof String))throw new IOException("标签格式错误");
        JSONArray selected=new JSONArray();if(service)selected=d.getJSONArray("sources");else{JSONArray indices=d.getJSONArray("source_indices");HashSet<Integer> seen=new HashSet<>();for(int i=0;i<indices.length();i++){Object v=indices.get(i);if(!(v instanceof Integer)||((Integer)v)<0||((Integer)v)>=sources.length())throw new IOException("草稿来源关联无效");if(seen.add((Integer)v))selected.put(sources.getJSONObject((Integer)v));}}
        if(selected.length()==0)throw new IOException("草稿没有来源");JSONArray clean=new JSONArray();for(int i=0;i<selected.length();i++){JSONObject s=selected.getJSONObject(i);String url=sourceUrl(s.getString("url")).toString(),cover=s.optString("cover");if(!cover.isEmpty())cover=sourceUrl(cover).toString();clean.put(new JSONObject().put("url",url).put("cover",cover));}d.put("sources",clean);return d;
    }
    private static String paragraphs(String s){StringBuilder out=new StringBuilder();for(String line:s.split("\\n+"))if(!line.trim().isEmpty())out.append("<p>").append(ReaderContent.escape(line)).append("</p>\n");return out.toString();}
    static String body(JSONObject d)throws Exception{
        StringBuilder out=new StringBuilder(d.optJSONArray("blocks")!=null?SourceTranslation.body(d.getJSONArray("blocks")):paragraphs(d.getString("summary")));JSONArray info=d.getJSONArray("metadata");if(info.length()>0){out.append("<h3>作品信息</h3><ul>");for(int i=0;i<info.length();i++){JSONObject v=info.getJSONObject(i);out.append("<li>").append(ReaderContent.escape(v.getString("label"))).append("：").append(ReaderContent.escape(v.getString("value"))).append("</li>");}out.append("</ul>\n");}
        JSONArray sections=d.getJSONArray("sections");for(int i=0;i<sections.length();i++){JSONObject v=sections.getJSONObject(i);out.append("<h3>").append(ReaderContent.escape(v.getString("heading"))).append("</h3>\n").append(paragraphs(v.getString("text")));}
        out.append("<h3>资料来源</h3><ul>");JSONArray sources=d.getJSONArray("sources");for(int i=0;i<sources.length();i++){String link=ReaderContent.escape(sources.getJSONObject(i).getString("url"));out.append("<li><a href=\"").append(link).append("\">").append(link).append("</a></li>");}return out.append("</ul>\n").toString();
    }
}
