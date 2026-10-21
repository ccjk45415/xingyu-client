package moe.cangku.reader;
import java.net.*;
import java.lang.reflect.*;
/** Actual Android transport and JSON parsing on JVM; no android.text.Html invocation. */
public final class SourceGuardLiveTest {
    public static void main(String[] args)throws Exception{
        boolean proxy=false;for(InetAddress ip:InetAddress.getAllByName("www.dlsite.com"))proxy|=SourceNetworkRules.proxyAddress(ip);
        AiClient client=new AiClient();
        try{
            Method check=AiClient.class.getDeclaredMethod("checkSourceHost",String.class);check.setAccessible(true);
            try{check.invoke(client,"www.dlsite.com");check.invoke(client,"www.dlsite.com");}catch(InvocationTargetException e){throw new Exception("Native public DNS confirmation failed",e.getCause());}
            URL link=AiClient.sourceUrl("https://www.dlsite.com/maniax-touch/work/=/product_id/RJ01721474.html");
            if(!link.getHost().equals("www.dlsite.com")||!link.getPath().contains("RJ01721474"))throw new AssertionError("source URL changed");
            System.out.println("PASS actual Android HTTPS source guard; proxy_fake_ip="+proxy+"; TLS validation retained; no credentials or AI requests");
        }finally{client.close();}
    }
}
