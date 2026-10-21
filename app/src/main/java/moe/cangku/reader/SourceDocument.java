package moe.cangku.reader;
import org.jsoup.*;import org.jsoup.nodes.*;import org.json.*;
import java.net.*;import java.util.*;

/** Extract the actual introduction, never a site's SEO summary or work metadata table. */
final class SourceDocument {
    static String desktopUrl(String raw)throws Exception{
        URI u=new URI(raw);if(("www.dlsite.com".equalsIgnoreCase(u.getHost())||"dlsite.com".equalsIgnoreCase(u.getHost()))&&u.getRawPath().matches("^/(maniax|home|books|pro|soft)-touch/.*"))return raw.replaceFirst("/(maniax|home|books|pro|soft)-touch/","/$1/");return raw;
    }
    static String image(Element e,URI base){
        for(String name:new String[]{"data-src","data-original","data-lazy-src","src","data-srcset","srcset"}){
            String raw=e.attr(name).trim();if(raw.isEmpty())continue;if(name.endsWith("srcset")){String[] choices=raw.split(",");raw=choices[choices.length-1].trim().split("\\s+")[0];}
            try{String u=base.resolve(raw).toString();String path=new URI(u).getPath().toLowerCase(Locale.ROOT);if(path.contains("loading.")||path.contains("blank.")||path.contains("spacer."))continue;return AiClient.sourceUrl(u).toString();}catch(Exception ignored){}
        }return "";
    }
    static JSONObject parse(String raw,String url)throws Exception{
        Document doc=Jsoup.parse(raw,url);String title="";Element heading=doc.selectFirst("#work_name,h1");if(heading!=null)title=heading.text();if(title.isEmpty()){Element og=doc.selectFirst("meta[property=og:title]");title=og==null?doc.title():og.attr("content");}
        String cover="";Element og=doc.selectFirst("meta[property=og:image]");if(og!=null)try{cover=AiClient.sourceUrl(new URI(url).resolve(og.attr("content")).toString()).toString();}catch(Exception ignored){}
        Element intro=null;for(String css:new String[]{".work_parts_container[itemprop=description]",".work_parts_container","#work_description","#game_area_description","[itemprop=description]","article","main"}){Element found=doc.selectFirst(css);if(found!=null&&!found.text().isEmpty()||found!=null&&!found.select("img").isEmpty()){intro=found;break;}}
        URI base=new URI(url);Element pageError=doc.selectFirst(".error_box_work");if(intro==null&&pageError!=null&&pageError.text().matches("(?s).*(国|地域|country|region).*"))throw new java.io.IOException("来源网站限制了当前网络出口地区，请检查代理出口或粘贴原文；未读取到详细介绍");if(intro==null&&base.getHost().endsWith("dlsite.com"))throw new java.io.IOException("未读取到DLsite详细介绍，请重试或粘贴原文；不会用网页摘要代替");
        if(intro==null)intro=doc.body();if(intro==null)throw new java.io.IOException("网页没有可读取的介绍");
        intro.select("script,style,nav,header,footer,noscript,iframe,form,button,svg").remove();Collector c=new Collector(base);c.walk(intro,"p");c.flush("p");
        if(c.blocks.length()==0)throw new java.io.IOException("未读取到作品详细介绍，请粘贴原文");
        return new JSONObject().put("url",url).put("title",title).put("cover",cover).put("blocks",c.blocks).put("text",text(c.blocks));
    }
    static JSONArray fromText(String text)throws Exception{JSONArray blocks=new JSONArray();for(String p:text.split("\\n\\s*\\n"))if(!p.trim().isEmpty())blocks.put(new JSONObject().put("kind","p").put("text",p));return blocks;}
    static String text(JSONArray blocks){StringBuilder out=new StringBuilder();for(int i=0;i<blocks.length();i++){JSONObject v=blocks.optJSONObject(i);if(v!=null&&!v.optString("kind").equals("image")){if(out.length()>0)out.append("\n\n");out.append(v.optString("text"));}}return out.toString();}
    private static final class Collector{
        final URI base;final JSONArray blocks=new JSONArray();final StringBuilder text=new StringBuilder();
        Collector(URI base){this.base=base;}
        void flush(String kind)throws Exception{String t=text.toString().replaceAll("[ \\t\\r\\f]+"," ").replaceAll(" *\\n *","\n").trim();text.setLength(0);if(!t.isEmpty())blocks.put(new JSONObject().put("kind",kind).put("text",t));if(blocks.length()>2000)throw new java.io.IOException("介绍过长，未截断；请分次导入");}
        void walk(Node node,String kind)throws Exception{
            if(node instanceof TextNode){text.append(((TextNode)node).getWholeText());return;}if(!(node instanceof Element))return;Element e=(Element)node;String tag=e.normalName();
            if(tag.equals("img")){flush(kind);String u=image(e,base);if(!u.isEmpty())blocks.put(new JSONObject().put("kind","image").put("url",u).put("alt",e.attr("alt")));return;}
            if(tag.equals("br")){text.append('\n');return;}
            boolean boundary=Arrays.asList("p","div","section","article","ul","ol","li","blockquote","h1","h2","h3","h4","h5","h6","figure","figcaption","table","tr").contains(tag);
            String next=tag.matches("h[1-6]")?(tag.equals("h1")||tag.equals("h2")?"h2":"h3"):tag.equals("li")?"li":tag.equals("blockquote")?"quote":kind;
            if(boundary)flush(kind);for(Node child:e.childNodes())walk(child,next);if(boundary)flush(next);
        }
    }
}
