import moe.cangku.reader.ChatSocket;
public class VerifiedChatWireTest {
    public static void main(String[] args)throws Exception{
        if(!args[0].matches("http://127\\.0\\.0\\.1:[0-9]+"))throw new AssertionError("Local only");
        try(ChatSocket wire=new ChatSocket(args[0],"2",args[1])){
            if(!wire.read().contains("\"type\":\"ready\""))throw new AssertionError("No ready");
            wire.send("{\"type\":\"send\",\"channel\":\"2\",\"text\":\"已认证的Java传输 😀\",\"client_id\":\"java_verified_nonce_0001\"}");
            if(!wire.read().contains("已认证的Java传输 😀"))throw new AssertionError("No verified echo");
            wire.send("ping");if(!wire.read().equals("pong"))throw new AssertionError("No pong");
        }
        System.out.println("PASS exact Android/JVM verified chat transport, UTF8 and heartbeat");
    }
}
