package moe.cangku.reader;

import java.util.*;
import java.util.regex.*;

/** Site-specific shortcode decoding. HTML is rendered by native TextView, without JavaScript. */
public final class ReaderContent {
    public static final class Resource {
        public final String title,info;
        public final LinkedHashMap<String,String> links;
        Resource(String t,String i,LinkedHashMap<String,String> l){title=t;info=i;links=l;}
    }
    public final String html;
    public final List<Resource> resources;
    public final boolean hasUnsupportedShortcodes;
    private ReaderContent(String h,List<Resource> r,boolean u){html=h;resources=r;hasUnsupportedShortcodes=u;}
    public static ReaderContent parse(String input){
        if(input==null)input="";
        List<Resource> resources=new ArrayList<>();
        Pattern box=Pattern.compile("\\[dlbox\\s*([^\\]]*)\\](?:[\\s\\S]*?\\[/dlbox\\])?",Pattern.CASE_INSENSITIVE);
        Matcher m=box.matcher(input);StringBuffer out=new StringBuffer();
        Pattern attr=Pattern.compile("([a-zA-Z0-9_]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')");
        while(m.find()){
            Map<String,String> attrs=new LinkedHashMap<>();Matcher a=attr.matcher(m.group(1));
            while(a.find())attrs.put(a.group(1).toLowerCase(Locale.ROOT),decode(a.group(2)!=null?a.group(2):a.group(3)));
            LinkedHashMap<String,String> links=new LinkedHashMap<>();
            for(Map.Entry<String,String> e:attrs.entrySet())if(e.getKey().startsWith("link")){
                String[] pair=e.getValue().split("\\|",2);String url=pair.length==2?pair[1].trim():pair[0].trim();
                if(UrlPolicy.canOpen(url))links.put(pair.length==2?pair[0].trim():"打开资源",url);
            }
            resources.add(new Resource(attrs.getOrDefault("title","资源下载"),attrs.getOrDefault("info",""),links));
            m.appendReplacement(out,Matcher.quoteReplacement("<p><b>◇ 资源 "+resources.size()+" · "+escape(attrs.getOrDefault("title","下载链接"))+"</b></p>"));
        }
        m.appendTail(out);
        String html=out.toString().replaceAll("(?is)<(script|style|iframe|object|form)\\b[^>]*>.*?</\\1\\s*>","");
        html=html.replaceAll("(?i)\\[/?(?:collapse|spoiler|tip|warning|success|info|tabs|tab|quote|center|hide)(?:\\s[^\\]]*)?\\]","<br>");
        boolean unsupported=Pattern.compile("\\[/?[a-zA-Z][a-zA-Z0-9_]*(?:\\s[^\\]]*)?\\]").matcher(html).find();
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
