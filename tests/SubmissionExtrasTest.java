package moe.cangku.reader;
import java.util.*;
public class SubmissionExtrasTest {
  static int n;
  static void check(boolean value){n++;if(!value)throw new AssertionError("case "+n);}
  public static void main(String[] args){
    String dl="https://www.dlsite.com/maniax-touch/work/=/product_id/RJ01699082.html";
    check(SubmissionExtras.withDlsiteIds("原作 😀",Arrays.asList(dl,dl)).equals("原作 😀 [RJ01699082]"));
    check(SubmissionExtras.withDlsiteIds("原作 [rj01699082]",Arrays.asList(dl)).equals("原作 [rj01699082]"));
    check(SubmissionExtras.withDlsiteIds("",Arrays.asList(dl)).isEmpty());
    for(String bad:Arrays.asList("https://dlsite.com.example.com/product_id/RJ01699082.html","https://example.com/?url="+dl,"https://dlsite.com@evil.com/product_id/RJ01699082.html","https://www.dlsite.com/path?product_id=RJ01699082","https://www.dlsite.com/product_id/RJ01699082.html.evil"))check(SubmissionExtras.withDlsiteIds("原作",Arrays.asList(bad)).equals("原作"));
    check(SubmissionExtras.withDlsiteIds("原作",Arrays.asList(dl,"https://www.dlsite.com/maniax/work/=/product_id/RJ123456.html")).equals("原作 [RJ01699082] [RJ123456]"));
    String intro="<p>原文 <b>格式 &amp; 内容</b></p><pre>[dlbox title=\"example\"]</pre><!-- [dlbox] -->",downloads="<p>[dlbox title=\"真实下载\" link1=\"测试|https://example.com\"][/dlbox]</p><p>尾部不变</p>",proof="https://file.cangku.moe/images/synthetic-proof.jpg?a=1&b=2";
    String out=SubmissionExtras.placePurchaseProof(intro+downloads,proof);
    check(out.startsWith(intro));check(out.endsWith(downloads));check(out.indexOf("data-xingyu-purchase-proof")>out.indexOf("</pre>"));check(out.indexOf("data-xingyu-purchase-proof")<out.indexOf(downloads));check(out.contains("?a=1&amp;b=2"));
    String twice=SubmissionExtras.placePurchaseProof(out,"https://file.cangku.moe/new.jpg");check(twice.split("data-xingyu-purchase-proof",-1).length==2);check(!twice.contains("synthetic-proof.jpg"));check(twice.contains(downloads));check(SubmissionExtras.placePurchaseProof(intro,proof).startsWith(intro));
    try{SubmissionExtras.placePurchaseProof(intro,"javascript:bad");check(false);}catch(IllegalArgumentException e){check(true);}
    String merged=SubmissionExtras.mergeBody(intro+downloads,"<p>AI忠实介绍</p>",true,proof);check(merged.indexOf("AI忠实介绍")<merged.indexOf("data-xingyu-purchase-proof"));check(merged.indexOf("data-xingyu-purchase-proof")<merged.indexOf(downloads));check(SubmissionExtras.mergeBody(intro+downloads,"新正文",true,"").equals(intro+downloads+"\n新正文"));
    System.out.println("PASS "+n+" native RJ and purchase-proof placement assertions; no website upload or AI calls");
  }
}
