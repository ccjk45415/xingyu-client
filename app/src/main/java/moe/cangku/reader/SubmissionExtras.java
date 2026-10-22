package moe.cangku.reader;

import java.net.URI;
import java.util.*;
import java.util.regex.*;

/** Local metadata, kept entirely outside AI requests. */
public final class SubmissionExtras {
    public static String withDlsiteIds(String title,Iterable<String> urls){
        LinkedHashSet<String> ids=new LinkedHashSet<>();
        for(String raw:urls)try{URI u=new URI(raw);String host=u.getHost();if(!"https".equals(u.getScheme())||u.getUserInfo()!=null||host==null)continue;host=host.toLowerCase(Locale.ROOT);if(!host.equals("dlsite.com")&&!host.endsWith(".dlsite.com"))continue;Matcher m=Pattern.compile("(?i)/product_id/(RJ[0-9]{6,12})(?:\\.html)?(?:/|$)").matcher(u.getPath());if(m.find())ids.add(m.group(1).toUpperCase(Locale.ROOT));}catch(Exception ignored){}
        String out=title.trim();if(out.isEmpty())return out;for(String id:ids)if(!Pattern.compile("(?i)\\[\\s*"+id+"\\s*\\]").matcher(out).find())out+=" ["+id+"]";return out;
    }
    private static final Pattern TOKENS=Pattern.compile("(?i)<!--[\\s\\S]*?(?:-->|$)|<(pre|code|script|style)\\b[^>]*>[\\s\\S]*?(?:</\\1\\s*>|$)|<div\\b[^>]*\\bdata-xingyu-purchase-proof=[\"']1[\"'][^>]*>[\\s\\S]*?</div\\s*>|<(?:[^<>\"']|\"[^\"]*\"|'[^']*')*>|\\[dlbox\\b[^\\]]*\\]");
    private static final Pattern MARKER=Pattern.compile("(?i)\\bdata-xingyu-purchase-proof=[\"']1[\"']");
    private static int downloadIndex(String body){int index=body.length();Matcher m=TOKENS.matcher(body);while(m.find())if(m.group().toLowerCase(Locale.ROOT).startsWith("[dlbox")){index=m.start();Matcher p=Pattern.compile("(?i)<p\\b[^>]*>\\s*$").matcher(body.substring(0,index));if(p.find())index=p.start();break;}return index;}
    public static String mergeBody(String previous,String incoming,boolean append,String proof){if(!append||previous.isEmpty())return proof.isEmpty()?incoming:placePurchaseProof(incoming,proof);if(proof.isEmpty())return previous+"\n"+incoming;int i=downloadIndex(previous);return placePurchaseProof(previous.substring(0,i)+"\n"+incoming+"\n"+previous.substring(i),proof);}
    public static String placePurchaseProof(String body,String url){
        try{URI u=new URI(url);if(!"https".equals(u.getScheme())||u.getHost()==null||u.getUserInfo()!=null)throw new Exception();}catch(Exception e){throw new IllegalArgumentException("请先上传有效的自购证明图片");}
        StringBuilder clean=new StringBuilder();Matcher m=TOKENS.matcher(body);int at=0;while(m.find())if(m.group().toLowerCase(Locale.ROOT).startsWith("<div")&&MARKER.matcher(m.group()).find()){clean.append(body,at,m.start());at=m.end();}clean.append(body.substring(at));String value=clean.toString();int index=downloadIndex(value);
        String proof="<div data-xingyu-purchase-proof=\"1\"><p>自购证明</p><p><img src=\""+ReaderContent.escape(url)+"\" alt=\"自购证明\"></p></div>";
        return value.substring(0,index)+"\n"+proof+"\n"+value.substring(index);
    }
}
