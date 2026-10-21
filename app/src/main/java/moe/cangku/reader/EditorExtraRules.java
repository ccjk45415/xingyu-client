package moe.cangku.reader;

import java.net.URI;
import java.security.SecureRandom;
import java.util.*;
import org.json.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;

/** Website-compatible local insertions; no network or editor state. */
public final class EditorExtraRules {
    private EditorExtraRules(){}
    public static final String[] FONT_NAMES={"默认字体","宋体","黑体","微软雅黑","仿宋","楷体","Arial","Georgia","Impact","Tahoma","Times New Roman","Verdana"};
    public static final String[] FONTS={"","SimSun, STSong, sans-serif","SimHei, STHeiti, sans-serif","\"Microsoft YaHei\", sans-serif","FangSong, STFangsong, sans-serif","KaiTi, STKaiti, sans-serif","Arial,Helvetica,sans-serif","Georgia,serif","Impact,Charcoal,sans-serif","Tahoma,Geneva,sans-serif","\"Times New Roman\",Times,serif","Verdana,Geneva,sans-serif"};
    public static final String[] EMOJI={"😀","😊","😍","🥰","😎","🤔","😭","😅","👍","👏","🙏","❤️","💜","✨","🎉","🎮","🎧","📚","🌸","⭐","(｡･ω･｡)","(๑•̀ㅂ•́)و✧"};
    public static final String[] SPECIAL={"©","®","™","°","±","×","÷","≠","≤","≥","∞","√","π","Ω","α","β","γ","δ","←","→","↑","↓","↔","⇒","★","☆","♥","♡","◆","◇","•","…","—","§","¶","€","£","¥","＜","＞","＆"};
    public static String esc(String s){return s==null?"":s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");}
    public static String font(int n,String html){if(n<0||n>=FONTS.length)throw new IllegalArgumentException("字体无效");return n==0?html:"<span style=\"font-family: "+esc(FONTS[n])+";\">"+html+"</span>";}
    public static String lineHeight(String value,String html){if(!Arrays.asList("1","1.15","1.5","1.75","2","2.5","3").contains(value))throw new IllegalArgumentException("行高无效");return "<div style=\"line-height: "+value+";\">"+html+"</div>";}
    public static String inline(String kind,String html){if(!Arrays.asList("text-rainbow","text-forbidden").contains(kind))throw new IllegalArgumentException("样式无效");return "<span class=\""+kind+"\">"+html+"</span>";}
    public static String collapse(String title,String content,boolean show){if(title.trim().isEmpty()||content.trim().isEmpty())throw new IllegalArgumentException("请填写标题和内容");String safe=esc(title.replace('[','【').replace(']','】'));return "<p>[collapse title=\""+safe+"\""+(show?" show=\"true\"":"")+"]</p>\n<p>"+esc(content).replace("\r\n","\n").replace("\n","<br>")+"</p>\n<p>[/collapse]</p>";}
    public static String reference(String kind,long id){if(!Arrays.asList("poll","lottery").contains(kind)||id<=0)throw new IllegalArgumentException("引用编号无效");return "["+kind+" id=\""+id+"\"][/"+kind+"]";}
    public static String randomFileName(){SecureRandom r=new SecureRandom();StringBuilder s=new StringBuilder("[GalACG]EX");for(int i=0;i<9;i++)s.append(r.nextInt(10));return s.toString();}
    public static String web(String raw,boolean optional){String s=raw.trim();if(optional&&s.isEmpty())return "";try{URI u=new URI(s);if((u.getScheme().equalsIgnoreCase("https")||u.getScheme().equalsIgnoreCase("http"))&&u.getHost()!=null&&!u.getHost().isEmpty()&&u.getUserInfo()==null&&s.indexOf('"')<0&&s.indexOf('<')<0&&s.indexOf('>')<0&&s.indexOf('\r')<0&&s.indexOf('\n')<0)return s;}catch(Exception ignored){}throw new IllegalArgumentException("请输入完整 http/https 地址");}
    public static boolean permission(JSONObject account,String name){return named(account,"permissions",name);}
    public static boolean named(JSONObject account,String key,String name){JSONArray a=account==null?null:account.optJSONArray(key);if(a!=null)for(int i=0;i<a.length();i++){Object v=a.opt(i);if(name.equals(v instanceof JSONObject?((JSONObject)v).optString("name"):String.valueOf(v)))return true;}return false;}
    public static boolean lotteryAllowed(JSONObject account){return named(account,"roles","administrator")||named(account,"roles","editor");}
    public static JSONObject pollPayload(JSONObject v)throws Exception{
        String title=v.optString("title").trim();if(title.isEmpty()||title.length()>1000)throw new IllegalArgumentException("投票主题需为 1～1000 个字符");JSONArray rows=v.optJSONArray("options");if(rows==null||rows.length()<2)throw new IllegalArgumentException("至少填写两个选项");Set<String> seen=new HashSet<>();JSONArray opts=new JSONArray();boolean images=v.optBoolean("image_mode"),multi=v.optBoolean("multi_select");
        for(int i=0;i<rows.length();i++){JSONObject x=rows.getJSONObject(i);String t=x.optString("text").trim();if(t.isEmpty()||t.length()>255||!seen.add(t))throw new IllegalArgumentException("选项需为 1～255 个字符且不能重复");JSONObject o=new JSONObject(x.toString());o.put("text",t);o.put("image",web(x.optString("image"),!images));opts.put(o);}
        int max=multi?v.optInt("max_select"):0;if(max<0||max>rows.length()||(multi&&max==1))throw new IllegalArgumentException("多选上限为 0（不限）或 2～选项数量");
        String start=date(v.optString("start_at")),end=date(v.optString("end_at"));if(!start.isEmpty()&&!end.isEmpty()&&start.compareTo(end)>=0)throw new IllegalArgumentException("截止时间必须晚于开始时间");JSONObject out=new JSONObject().put("title",title).put("options",opts).put("image_mode",images).put("multi_select",multi).put("max_select",max).put("start_at",start.isEmpty()?JSONObject.NULL:start).put("end_at",end.isEmpty()?JSONObject.NULL:end);if(v.optLong("id")>0)out.put("id",v.getLong("id"));return out;
    }
    private static String date(String s){s=s.trim();if(s.isEmpty()||s.equals("null"))return "";if(!s.matches("[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"))throw new IllegalArgumentException("时间格式：yyyy-MM-dd HH:mm:ss");java.text.SimpleDateFormat f=new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss",Locale.ROOT);f.setLenient(false);try{f.parse(s);}catch(Exception e){throw new IllegalArgumentException("日期时间无效");}return s;}
    public static Element image(String html){Element img=Jsoup.parseBodyFragment(html).selectFirst("img");if(img==null)throw new IllegalArgumentException("未找到图片");return img;}
    public static String updateImage(String original,String src,String alt,String width,String height,boolean blur,String link){Element root=Jsoup.parseBodyFragment(original).body();Element image=root.selectFirst("img");if(image==null)throw new IllegalArgumentException("未找到图片");String nextSrc=web(src,false);if(!nextSrc.equals(image.attr("src")))for(String key:new String[]{"data-src","data-original","data-lazy-src","srcset","data-srcset"})image.removeAttr(key);image.attr("src",nextSrc).attr("alt",alt);image.attr("style",withoutStyle(image.attr("style"),"width","height"));dimension(image,"width",width);dimension(image,"height",height);if(blur)image.addClass("blur-img");else image.removeClass("blur-img");String href=web(link,true);Element a=image.parent();if(a!=null&&a.tagName().equals("a")){if(href.isEmpty())a.unwrap();else a.attr("href",href);}else if(!href.isEmpty()){image.wrap("<a href=\""+esc(href)+"\"></a>");}return root.html();}
    private static void dimension(Element e,String key,String raw){String s=raw.trim();if(s.isEmpty()){e.removeAttr(key);return;}String size=tableDimension(s);if(size.endsWith("%")){e.removeAttr(key);String style=e.attr("style");e.attr("style",style+(style.isEmpty()||style.endsWith(";")?"":";")+key+":"+size+";");}else e.attr(key,size.replace("px",""));}

    public static String table(String original,int rows,int columns,List<String> cells,String width,String height,String border,String align){
        if(rows<1||rows>30||columns<1||columns>12||rows*columns>180)throw new IllegalArgumentException("表格为 1～30 行、1～12 列，总计最多 180 格");
        if(!Arrays.asList("left","center","right").contains(align)||!Arrays.asList("none","solid","dashed","dotted").contains(border))throw new IllegalArgumentException("表格样式无效");
        Element table=Jsoup.parseBodyFragment(original==null?"":original).selectFirst("table");boolean existing=table!=null;if(!existing)table=new Element("table");
        if(existing){for(Element cell:table.select("td,th"))if(cell.hasAttr("rowspan")||cell.hasAttr("colspan"))throw new IllegalArgumentException("此表格包含合并单元格，请在源码模式编辑以保留结构");}
        String style=withoutStyle(table.attr("style"),"width","height","border","border-collapse","text-align","margin-left","margin-right");
        String w=tableDimension(width),h=tableDimension(height);style+=(style.endsWith(";")||style.isEmpty()?"":";")+"border-collapse:collapse;text-align:"+align+";border:"+(border.equals("none")?"0":"1px "+border+" #888")+";";
        if(!w.isEmpty())style+="width:"+w+";";if(!h.isEmpty())style+="height:"+h+";";if(align.equals("center"))style+="margin-left:auto;margin-right:auto;";else if(align.equals("right"))style+="margin-left:auto;margin-right:0;";
        table.removeAttr("width").removeAttr("height");table.attr("style",style);table.removeClass("fr-dashed-borders");table.removeClass("fr-dotted-borders");if(border.equals("dashed"))table.addClass("fr-dashed-borders");if(border.equals("dotted"))table.addClass("fr-dotted-borders");
        ArrayList<Element> oldRows=new ArrayList<>(table.select("tr"));for(Element r:oldRows)if(r.closest("table")!=table)throw new IllegalArgumentException("嵌套表格请在源码模式编辑");
        Element tbody=table.selectFirst("tbody");if(tbody==null){tbody=new Element("tbody");table.appendChild(tbody);}
        for(int i=oldRows.size()-1;i>=rows;i--)oldRows.get(i).remove();
        for(int i=0;i<rows;i++){Element tr=i<oldRows.size()?oldRows.get(i):new Element("tr");if(tr.parent()==null)tbody.appendChild(tr);List<Element> prior=new ArrayList<>(tr.children());for(int j=prior.size()-1;j>=columns;j--)prior.get(j).remove();for(int j=0;j<columns;j++){Element cell=j<prior.size()?prior.get(j):new Element("td");String text=i*columns+j<cells.size()?cells.get(i*columns+j):"";if(j>=prior.size()||!cell.text().equals(text))cell.text(text);if(cell.parent()==null)tr.appendChild(cell);}}return table.outerHtml();
    }
    private static String withoutStyle(String style,String...keys){Set<String> names=new HashSet<>(Arrays.asList(keys));StringBuilder out=new StringBuilder();for(String item:style.split(";")){int colon=item.indexOf(':');if(colon>0&&!names.contains(item.substring(0,colon).trim().toLowerCase(Locale.ROOT)))out.append(item.trim()).append(';');}return out.toString();}
    private static String tableDimension(String raw){String s=raw.trim();if(s.isEmpty())return "";if(!s.matches("[1-9][0-9]{0,3}(?:px|%)?"))throw new IllegalArgumentException("表格宽高为像素或百分比，例如 600 或 100%");if(s.endsWith("%")&&Integer.parseInt(s.substring(0,s.length()-1))>100)throw new IllegalArgumentException("百分比不能大于 100");return s.matches("[0-9]+")?s+"px":s;}

}
