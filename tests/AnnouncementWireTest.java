package moe.cangku.reader;
import java.net.URI;
import java.net.http.*;
import java.util.regex.*;
/** Exact Android transport on a disposable local announcement service, no site credentials. */
public class AnnouncementWireTest {
    public static void main(String[] args)throws Exception{
        String origin=args[0],secret=args[1];if(!origin.matches("http://127\\.0\\.0\\.1:[0-9]+"))throw new AssertionError("Local tests only");
        HttpClient http=HttpClient.newHttpClient();
        try(ChatSocket wire=ChatSocket.announcements(origin)){
            String initial=wire.read();if(!initial.contains("\"type\":\"announcements\""))throw new AssertionError("No subscription snapshot");
            Matcher revision=Pattern.compile("\"revision\":([0-9]+)").matcher(initial);if(!revision.find())throw new AssertionError("No revision");
            String body="{\"base_revision\":"+revision.group(1)+",\"items\":[{\"id\":\"jvm-test\",\"title\":\"即时公告\",\"content\":\"无需客户端更新 😀\"}]}";
            var response=http.send(HttpRequest.newBuilder(URI.create(origin+"/announcements/publish")).header("Authorization","Bearer "+secret).header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofString(body)).build(),HttpResponse.BodyHandlers.ofString());
            if(response.statusCode()!=200)throw new AssertionError("Publish failed");
            if(!wire.read().contains("无需客户端更新 😀"))throw new AssertionError("Live update missing");
            wire.send("ping");if(!wire.read().equals("pong"))throw new AssertionError("Heartbeat failed");
        }
        System.out.println("PASS exact Android/JVM announcement transport: anonymous snapshot, immediate push, UTF8 and heartbeat");
    }
}
