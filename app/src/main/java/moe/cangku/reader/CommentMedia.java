package moe.cangku.reader;

import java.net.URI;
import java.util.*;
import java.util.regex.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.*;

/** Display-only website comment expansion. The original comment is always submitted and copied intact. */
public final class CommentMedia {
    private CommentMedia(){}
    public static final String[] GROUPS={"cangku_1","new_paopao","paopao","qq","aru"};
    public static final String[] NAMES={"仓库娘","新版泡泡","泡泡","QQ","aru"};
    public static final int[] COUNTS={9,66,33,92,122};
    private static final Pattern PART=Pattern.compile("\\[([a-z0-9_]+):([0-9]{1,5})\\]|https://[^\\s<>\\x22'，。；！？（）【】]+",Pattern.CASE_INSENSITIVE);
    public static String token(int group,int id){return group>=0&&group<GROUPS.length&&id>=1&&id<=COUNTS[group]?"["+GROUPS[group]+":"+id+"]":"";}
    public static String emojiUrl(String group,int id){
        for(int i=0;i<GROUPS.length;i++)if(GROUPS[i].equals(group)&&id>=1&&id<=COUNTS[i])return UrlPolicy.ORIGIN+"/images/stickers/"+group+"/"+id+(group.equals("qq")?".gif":".png");return "";
    }
    public static boolean emojiImage(String source){
        try{URI u=URI.create(source);if(!UrlPolicy.isSite(source))return false;String[] path=u.getPath().split("/");if(path.length!=5||!path[1].equals("images")||!path[2].equals("stickers"))return false;String id=path[4].replaceFirst("\\.(png|gif)$","");return emojiUrl(path[3],Integer.parseInt(id)).equals(source);}catch(Exception ignored){return false;}
    }
    public static String imageUrl(String raw){
        String value=raw.trim();if(value.startsWith("//"))value="https:"+value;else if(value.startsWith("/"))value=UrlPolicy.ORIGIN+value;
        if(!UrlPolicy.isImage(value))return "";
        try{return URI.create(value).getPath().matches("(?i).*\\.(png|jpe?g|gif|webp|bmp|avif)$")?value:"";}catch(Exception ignored){return "";}
    }
    public static String html(String raw){
        Document doc=Jsoup.parseBodyFragment(raw==null?"":raw);doc.outputSettings().prettyPrint(false);
        doc.select("script,style,iframe,object,embed,form,svg,math").remove();
        for(Element image:new ArrayList<>(doc.select("img"))){String url=imageUrl(image.attr("src"));if(url.isEmpty()){image.replaceWith(new TextNode(image.attr("alt")));continue;}image.clearAttributes();image.attr("src",url);}
        List<TextNode> text=new ArrayList<>();collect(doc.body(),text);
        for(TextNode node:text){boolean literal=false;for(Node parent=node.parent();parent!=null;parent=parent.parent())if(parent instanceof Element&&(((Element)parent).tagName().equals("pre")||((Element)parent).tagName().equals("code"))){literal=true;break;}if(literal)continue;
            String value=node.getWholeText();Matcher m=PART.matcher(value);List<Node> replacement=new ArrayList<>();int at=0;
            while(m.find()){String url="";String matched=m.group();if(m.group(1)!=null){try{url=emojiUrl(m.group(1),Integer.parseInt(m.group(2)));}catch(Exception ignored){}}else{while(!matched.isEmpty()&&".,;!?，。；！？）)]}".indexOf(matched.charAt(matched.length()-1))>=0)matched=matched.substring(0,matched.length()-1);url=imageUrl(matched);}
                if(url.isEmpty())continue;append(replacement,value.substring(at,m.start()));Element image=new Element("img").attr("src",url).attr("alt",matched);replacement.add(image);at=m.start()+matched.length();}
            if(at==0&&!value.contains("\n")&&!value.contains("\r"))continue;append(replacement,value.substring(at));for(Node next:replacement)node.before(next);node.remove();
        }
        return doc.body().html();
    }
    private static void collect(Node node,List<TextNode> out){for(Node child:node.childNodes()){if(child instanceof TextNode)out.add((TextNode)child);else collect(child,out);}}
    private static void append(List<Node> out,String text){String[] lines=text.replace("\r\n","\n").replace('\r','\n').split("\n",-1);for(int i=0;i<lines.length;i++){if(i>0)out.add(new Element("br"));if(!lines[i].isEmpty())out.add(new TextNode(lines[i]));}}
}
