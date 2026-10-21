package moe.cangku.reader;
import java.util.*;
import java.util.regex.*;
import org.jsoup.parser.Parser;
import java.nio.charset.StandardCharsets;

/** Website-compatible shortcode construction; values can never escape the attribute. */
public final class EditorTemplates {
    private EditorTemplates(){}
    public static final String[] EXTERNAL_SERVICES={"Youtube","Bilibili视频","Bilibili直播","Twitch视频","Twitch直播","Twitcasting直播","斗鱼直播","网络视频（mp4、webm）","Mixcloud","Apple Music","网易云音乐","SoundCloud","chobit","网络音频（wav、mp3、ogg）","Steam","TapTap","Twitter","Facebook","Pixiv","Imgur","Streamja"};
    public static final class Link {public final String name,url;public Link(String n,String u){name=n;url=u;}}
    private static String attr(String value){return ReaderContent.escape(value.replace("]","】").replace("[","【").replace("\r"," ").replace("\n"," "));}
    public static String download(String title,String time,String from,String extraction,String password,List<Link> links){
        title=title.trim();time=time.trim();from=from.trim();extraction=extraction.trim();password=password.trim();if(title.isEmpty())throw new IllegalArgumentException("请填写下载链接标题");if(links.isEmpty())throw new IllegalArgumentException("请至少添加一个下载链接");String info="";if(!extraction.isEmpty())info="提取："+extraction;if(!password.isEmpty())info+=(info.isEmpty()?"":" / ")+"密码："+password;
        StringBuilder out=new StringBuilder("[dlbox title=\"").append(attr(title)).append("\" time=\"").append(attr(time)).append("\" info=\"").append(attr(info)).append("\" from=\"").append(attr(from)).append("\"");int i=0;for(Link link:links){String url=link.url.trim();if(!UrlPolicy.canOpen(url)||url.contains("|"))throw new IllegalArgumentException("链接"+(i+1)+"：请输入有效地址，地址不能含竖线");out.append(" link").append(++i).append("=\"").append(attr(link.name.trim().replace("|"," ")+"|"+url)).append("\"");}return out.append("][/dlbox]").toString();
    }
    public static final class Download {
        public String title="",time="",from="",extraction="",password="",otherInfo="",body="";public final List<Link> links=new ArrayList<>();public final LinkedHashMap<String,String> extras=new LinkedHashMap<>();
    }
    public static Download parseDownload(String source){Download value=new Download();if(source==null||source.isEmpty())return value;Matcher outer=Pattern.compile("(?is)^\\[dlbox\\b([^\\]]*)\\](.*?)\\[/dlbox\\]$").matcher(source);if(!outer.find())throw new IllegalArgumentException("下载组件格式无法识别，原内容未修改");value.body=outer.group(2);Matcher attrs=Pattern.compile("([a-zA-Z0-9_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')").matcher(outer.group(1));while(attrs.find()){String key=attrs.group(1).toLowerCase(Locale.ROOT),raw=Parser.unescapeEntities(attrs.group(2)!=null?attrs.group(2):attrs.group(3),false);switch(key){case "title":value.title=raw;break;case "time":value.time=raw;break;case "from":value.from=raw;break;case "info":value.otherInfo=raw;break;default:if(key.matches("link[0-9]+")){String[] parts=raw.split("\\|",2);value.links.add(new Link(parts.length==2?parts[0]:"下载链接",parts.length==2?parts[1]:parts[0]));}else value.extras.put(key,raw);}}
        Matcher info=Pattern.compile("^(?:提取：([^/]*?))?(?: / )?(?:密码：(.*))?$").matcher(value.otherInfo);if(info.matches()){value.extraction=info.group(1)==null?"":info.group(1);value.password=info.group(2)==null?"":info.group(2);value.otherInfo="";}return value;
    }
    public static String updateDownload(Download original,String title,String time,String from,String extraction,String password,String otherInfo,List<Link> links){String generated=download(title,time,from,extraction,password,links);String extra=otherInfo.trim();if(!extra.isEmpty()){int a=generated.indexOf(" info=\"")+7,b=generated.indexOf('"',a);String existing=Parser.unescapeEntities(generated.substring(a,b),false);generated=generated.substring(0,a)+attr(existing.isEmpty()?extra:existing+" / "+extra)+generated.substring(b);}int end=generated.indexOf(']');StringBuilder more=new StringBuilder();for(Map.Entry<String,String> entry:original.extras.entrySet())more.append(' ').append(entry.getKey()).append("=\"").append(attr(entry.getValue())).append('"');return generated.substring(0,end)+more+generated.substring(end,generated.length()-"[/dlbox]".length())+original.body+"[/dlbox]";}
    public static String external(String url){if(!UrlPolicy.canOpen(url)||url.startsWith("magnet:")||url.contains("[")||url.contains("]"))throw new IllegalArgumentException("请输入有效的网页或媒体链接");return "[iframe]"+url+"[/iframe]";}
    public static String rapid(String code,boolean ali){String value=code.trim();if(value.isEmpty())throw new IllegalArgumentException("请粘贴秒传代码");if(value.matches("(?is)^https?://.*"))throw new IllegalArgumentException("普通下载链接请直接填入链接栏；这里填写秒传代码");return (ali?"https://www.aliyundrive.com/drive/#alink=":"https://pan.baidu.com/#bdlink=")+Base64.getEncoder().encodeToString(value.getBytes(StandardCharsets.UTF_8));}
}
