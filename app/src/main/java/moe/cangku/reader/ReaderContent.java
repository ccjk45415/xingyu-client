package moe.cangku.reader;

import java.util.*;
import java.util.regex.*;

/** Site-specific shortcode decoding. HTML is rendered by native TextView, without JavaScript. */
public final class ReaderContent {
    public static final class Resource {
        public final String title,info,time,from;
        public final LinkedHashMap<String,String> links;
        Resource(String t,String i,String when,String source,LinkedHashMap<String,String> l){title=t;info=i;time=when;from=source;links=l;}
        public String details(){List<String> rows=new ArrayList<>();if(!time.isEmpty())rows.add("上传时间："+time);if(!from.isEmpty())rows.add("文件来源："+from);if(!info.isEmpty())rows.add("文件信息："+info);return String.join("\n",rows);}
    }
    public final String html;
    public final List<Resource> resources;
    public final boolean hasUnsupportedShortcodes;
    private ReaderContent(String h,List<Resource> r,boolean u){html=h;resources=r;hasUnsupportedShortcodes=u;}
    public static ReaderContent parse(String input){
        if(input==null)input="";
        List<Resource> resources=new ArrayList<>();
        // Code examples must never turn into active shortcodes or links.
        List<String> code=new ArrayList<>();String marker="XINGYU_PROTECTED_CODE_";while(input.contains(marker))marker+="_";
        Matcher pre=Pattern.compile("(?is)<pre\\b[^>]*>.*?</pre\\s*>").matcher(input);StringBuffer protectedBody=new StringBuffer();
        while(pre.find()){code.add(pre.group());pre.appendReplacement(protectedBody,Matcher.quoteReplacement(marker+(code.size()-1)+"_END"));}pre.appendTail(protectedBody);input=protectedBody.toString();
        Pattern box=Pattern.compile("\\[dlbox\\s*([^\\]]*)\\](?:[\\s\\S]*?\\[/dlbox\\])?",Pattern.CASE_INSENSITIVE);
        Matcher m=box.matcher(input);StringBuffer out=new StringBuffer();
        Pattern attr=Pattern.compile("([a-zA-Z0-9_]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')");
        while(m.find()){
            Map<String,String> attrs=new LinkedHashMap<>();Matcher a=attr.matcher(m.group(1));
            while(a.find())attrs.put(a.group(1).toLowerCase(Locale.ROOT),decode(a.group(2)!=null?a.group(2):a.group(3)));
            LinkedHashMap<String,String> links=new LinkedHashMap<>();
            for(Map.Entry<String,String> e:attrs.entrySet())if(e.getKey().startsWith("link")){
                String[] pair=e.getValue().split("\\|",2);String url=pair.length==2?pair[1].trim():pair[0].trim();
                if(UrlPolicy.canOpen(url)){String name=pair.length==2?pair[0].trim():"打开资源";if(name.isEmpty())name="打开资源";String label=name;int suffix=2;while(links.containsKey(label))label=name+"（"+(suffix++)+"）";links.put(label,url);}
            }
            resources.add(new Resource(attrs.getOrDefault("title","资源下载"),attrs.getOrDefault("info",""),attrs.getOrDefault("time",""),attrs.getOrDefault("from",""),links));
            m.appendReplacement(out,Matcher.quoteReplacement("<p><b>◇ 资源 "+resources.size()+" · "+escape(attrs.getOrDefault("title","下载链接"))+"</b></p>"));
        }
        m.appendTail(out);
        String html=out.toString().replaceAll("(?is)<(script|style|iframe|object|form)\\b[^>]*>.*?</\\1\\s*>","");
        Matcher external=Pattern.compile("(?is)\\[iframe\\](.*?)\\[/iframe\\]").matcher(html);StringBuffer embeds=new StringBuffer();
        while(external.find()){String link=decode(external.group(1)).replaceAll("<[^>]*>","").trim();String replacement=UrlPolicy.canOpen(link)&&link.matches("(?i)^https?://.*")?"<p><b>外部内容</b><br><a href=\""+escape(link)+"\">"+escape(link)+"</a><br>在系统浏览器打开</p>":"<p>外部链接无效</p>";external.appendReplacement(embeds,Matcher.quoteReplacement(replacement));}external.appendTail(embeds);html=embeds.toString();
        Matcher collapse=Pattern.compile("(?i)\\[collapse\\s*([^\\]]*)\\]").matcher(html);StringBuffer collapsed=new StringBuffer();
        while(collapse.find()){Matcher title=Pattern.compile("title\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')").matcher(collapse.group(1));String label=title.find()?decode(title.group(1)!=null?title.group(1):title.group(2)):"折叠内容";collapse.appendReplacement(collapsed,Matcher.quoteReplacement("<p><b>▾ "+escape(label)+"</b></p>"));}collapse.appendTail(collapsed);html=collapsed.toString().replaceAll("(?i)\\[/collapse\\]","<br>");
        html=html.replaceAll("(?i)\\[/?(?:code|spoiler|tip|warning|success|info|tabs|tab|quote|center|hide)(?:\\s[^\\]]*)?\\]","<br>");
        boolean unsupported=Pattern.compile("\\[/?[a-zA-Z][a-zA-Z0-9_]*(?:\\s[^\\]]*)?\\]").matcher(html).find();
        for(int i=0;i<code.size();i++)html=html.replace(marker+i+"_END",code.get(i));
        return new ReaderContent(html,resources,unsupported);
    }
    private static String decode(String s){return s.replace("&quot;","\"").replace("&#39;","'").replace("&lt;","<").replace("&gt;",">").replace("&amp;","&");}
    public static String escape(String s){return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;");}
    /** Android Html.fromHtml does not preserve pre whitespace. Only adjust display, never saved HTML. */
    public static String nativeCodeBlocks(String html){
        Matcher m=Pattern.compile("(?is)<pre\\b[^>]*>(.*?)</pre\\s*>").matcher(html);StringBuffer out=new StringBuffer();
        while(m.find()){
            String code=m.group(1).replaceFirst("(?is)^\\s*<code\\b[^>]*>","").replaceFirst("(?is)</code\\s*>\\s*$","");
            code=code.replace("\r\n","\n").replace("\r","\n").replace("\t","    ").replace(" ","&nbsp;").replace("\n","<br>");
            m.appendReplacement(out,Matcher.quoteReplacement("<p><tt>"+code+"</tt></p>"));
        }
        m.appendTail(out);return out.toString();
    }
}
