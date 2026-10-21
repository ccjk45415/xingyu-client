import moe.cangku.reader.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.*;
import java.nio.charset.StandardCharsets;

public final class CommentMediaTest {
    private static int assertions;
    private static void check(boolean value,String name){assertions++;if(!value)throw new AssertionError(name);}
    private static Element body(String raw){return Jsoup.parseBodyFragment(CommentMedia.html(raw)).body();}
    public static void main(String[] args){
        for(int group=0;group<CommentMedia.GROUPS.length;group++){
            String first=CommentMedia.token(group,1),last=CommentMedia.token(group,CommentMedia.COUNTS[group]);
            check(body(first+last).select("img").size()==2,"all groups first/last display");
            check(CommentMedia.emojiImage(CommentMedia.emojiUrl(CommentMedia.GROUPS[group],1)),"official emoji URL recognized");
            check(CommentMedia.token(group,0).isEmpty()&&CommentMedia.token(group,CommentMedia.COUNTS[group]+1).isEmpty(),"picker index boundaries");
            check(CommentMedia.emojiUrl(CommentMedia.GROUPS[group],0).isEmpty()&&CommentMedia.emojiUrl(CommentMedia.GROUPS[group],CommentMedia.COUNTS[group]+1).isEmpty(),"render index boundaries");
        }
        check(CommentMedia.emojiUrl("qq",1).endsWith("/1.gif"),"QQ original GIF endpoint");
        check(CommentMedia.emojiUrl("new_paopao",12).equals("https://cangku.moe/images/stickers/new_paopao/12.png"),"reported website sample");
        String raw="前面[new_paopao:12]\nhttps://file.cangku.moe/images/one.webp?x=1&y=2 后面";Element shown=body(raw);
        check(shown.select("img").size()==2&&shown.select("br").size()==1,"mixed inline emoji and bare image with newline");
        check(shown.select("img").get(1).attr("src").endsWith("one.webp?x=1&y=2"),"image query retained");
        check(raw.contains("[new_paopao:12]")&&raw.contains("\nhttps://"),"source not rewritten for send/copy");
        check(body("[unknown:1][new_paopao:0][qq:93]").select("img").isEmpty(),"unknown/out-of-range tokens remain literal");
        check(body("[unknown:1][new_paopao:0]").text().equals("[unknown:1][new_paopao:0]"),"invalid tokens preserved");
        check(body("<img src=\"https://file.cangku.moe/images/a.png\" onerror=\"bad()\" width=\"99999\">").selectFirst("img").attributes().size()==1,"HTML images preserved and attributes bounded");
        check(body("<img src=\"javascript:bad()\" alt=\"原图\">").text().equals("原图"),"unsafe image shows alt");
        check(body("<script>bad()</script><style>body{}</style><iframe>bad</iframe>正常").text().equals("正常"),"noncontent excluded");
        check(body("<a href=\"https://cangku.moe/?q=[new_paopao:12]\">普通链接</a>").select("img").isEmpty(),"token in attribute not expanded");
        check(body("<pre>[new_paopao:12] https://file.cangku.moe/images/a.jpg</pre><code>[qq:1]</code>").select("img").isEmpty(),"code examples remain literal");
        check(body("图：https://file.cangku.moe/images/a.png。后面").selectFirst("img").attr("src").endsWith("a.png"),"Chinese punctuation separated");
        check(body("https://file.cangku.moe/images/a.png)\n下一行").text().equals(") 下一行"),"trailing punctuation and following text preserved");
        check(body("https://file.cangku.moe/images/a.png https://file.cangku.moe/images/a.png").select("img").size()==2,"repeated image positions retained");
        check(body("<img src=\"//file.cangku.moe/images/a.webp\"><img src=\"/images/a.gif\">").select("img").size()==2,"HTTPS relative images");
        for(String unsafe:new String[]{"http://file.cangku.moe/a.png","file:///a.png","data:image/png;base64,abc","https://localhost/a.png","https://127.0.0.1/a.png","https://user:secret@example.com/a.png","https://example.com/normal"})check(CommentMedia.imageUrl(unsafe).isEmpty(),"unsafe/non-image URL rejected");
        check(!CommentMedia.emojiImage("https://example.com/images/stickers/qq/1.gif"),"ordinary image cannot claim emoji sizing");
        check(!CommentMedia.emojiImage("https://cangku.moe/images/stickers/qq/1.png"),"wrong extension cannot claim emoji sizing");
        check(body("a\r\nb\rc\nd").select("br").size()==3,"line endings retained");
        check(body("<b>标题</b> &lt;普通&gt; [new_paopao:12]").selectFirst("b").text().equals("标题"),"existing comment formatting retained");
        byte[][] headers={new byte[]{(byte)255,(byte)216,(byte)255},new byte[]{(byte)137,80,78,71,13,10,26,10},"GIF89a".getBytes(StandardCharsets.US_ASCII),new byte[]{82,73,70,70,0,0,0,0,87,69,66,80}};
        String[] types={"image/jpeg","image/png","image/gif","image/webp"};for(int i=0;i<headers.length;i++){check(CommentImageRules.mediaType(headers[i]).equals(types[i]),"original MIME signature");byte[] max=new byte[CommentImageRules.MAX_BYTES];System.arraycopy(headers[i],0,max,0,headers[i].length);check(CommentImageRules.mediaType(max).equals(types[i]),"exact 1MiB accepted");byte[] tooLarge=new byte[CommentImageRules.MAX_BYTES+1];System.arraycopy(headers[i],0,tooLarge,0,headers[i].length);check(CommentImageRules.mediaType(tooLarge).isEmpty(),"1MiB+1 rejected");}
        check(CommentImageRules.mediaType(new byte[0]).isEmpty(),"empty rejected");check(CommentImageRules.mediaType("not a PNG".getBytes(StandardCharsets.US_ASCII)).isEmpty(),"fake format rejected");
        System.out.println("PASS "+assertions+" native comment media and image boundary assertions; no website writes");
    }
}
