import moe.cangku.reader.ChatSocket;
import java.net.*;
import java.net.http.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;

/** Exercises the exact Android WebSocket transport against the local Cloudflare runtime. */
public class ChatWireTest {
    static String register(String origin,int i)throws Exception{
        HttpRequest req=HttpRequest.newBuilder(URI.create(origin+"/v1/session")).header("Content-Type","application/json").header("CF-Connecting-IP","198.19.0."+i).POST(HttpRequest.BodyPublishers.ofString("{\"nickname\":\"JavaWire"+i+"\"}")).build();
        HttpResponse<String> r=HttpClient.newHttpClient().send(req,HttpResponse.BodyHandlers.ofString());
        Matcher m=Pattern.compile("\"token\":\"([a-f0-9]{64})\"").matcher(r.body());if(r.statusCode()!=200||!m.find())throw new AssertionError("Cannot create synthetic local identity");return m.group(1);
    }
    static void check(boolean ok){if(!ok)throw new AssertionError("WebSocket transport verification failed");}
    public static void main(String[] args)throws Exception{
        String base=args[0];check(base.startsWith("http://127.0.0.1:"));String a=register(base,1),b=register(base,2),c=register(base,3);
        try(ChatSocket one=new ChatSocket(base,"1",a);ChatSocket two=new ChatSocket(base,"2",b);ChatSocket reader=new ChatSocket(base,"1",c)){
            check(one.read().contains("\"type\":\"ready\""));check(two.read().contains("\"channel\":\"2\""));check(reader.read().contains("\"channel\":\"1\""));
            String id=UUID.randomUUID().toString();String payload="{\"type\":\"send\",\"channel\":\"1\",\"text\":\"Android transport UTF8 星屿\",\"client_id\":\""+id+"\"}";
            one.send(payload);check(one.read().contains(id));check(reader.read().contains(id));one.send(payload);check(one.read().contains(id));
            two.send("ping");check(two.read().equals("pong"));
            HttpResponse<String> history=HttpClient.newHttpClient().send(HttpRequest.newBuilder(URI.create(base+"/v1/channels/2/messages")).header("Authorization","Bearer "+b).build(),HttpResponse.BodyHandlers.ofString());check(!history.body().contains(id));
        }
        try(ServerSocket server=new ServerSocket(0,1,InetAddress.getLoopbackAddress())){
            Thread fake=new Thread(()->{try(Socket s=server.accept()){
                int end=0;while(end!=0x0d0a0d0a){int x=s.getInputStream().read();if(x<0)return;end=(end<<8)|x;}
                s.getOutputStream().write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: wrong-proof\r\n\r\n".getBytes(StandardCharsets.US_ASCII));s.getOutputStream().flush();
            }catch(Exception ignored){}});fake.start();boolean denied=false;
            try(ChatSocket invalid=new ChatSocket("http://127.0.0.1:"+server.getLocalPort(),"1",a)){}catch(IOException e){denied=true;}check(denied);fake.join(3000);
        }
        System.out.println("PASS JVM/Android transport: handshake proof, masked UTF8 send, receive, retry, heartbeat, channel isolation");
    }
}
