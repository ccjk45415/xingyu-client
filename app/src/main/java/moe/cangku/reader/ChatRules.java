package moe.cangku.reader;

import java.net.URI;
import java.util.Locale;

/** Shared client boundaries: exactly two rooms and credentials bound to a single origin. */
public final class ChatRules {
    public static final String[] CHANNELS={"1","2"};
    private ChatRules(){}
    public static boolean channel(String id){return "1".equals(id)||"2".equals(id);}
    public static boolean accepts(String selected,String response){return channel(selected)&&selected.equals(response);}
    public static String server(String input){
        try{
            URI uri=URI.create(input.trim());String scheme=uri.getScheme(),host=uri.getHost();
            if(host==null||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null)return "";
            if(uri.getPath()!=null&&!uri.getPath().isEmpty()&&!uri.getPath().equals("/"))return "";
            boolean local=host.equalsIgnoreCase("localhost")||host.equals("127.0.0.1");
            if(!"https".equalsIgnoreCase(scheme)&&!(local&&"http".equalsIgnoreCase(scheme)))return "";
            if(uri.getPort()==0||uri.getPort()>65535)return "";
            return new URI(scheme.toLowerCase(Locale.ROOT),null,host.toLowerCase(Locale.ROOT),uri.getPort(),null,null,null).toASCIIString();
        }catch(Exception e){return "";}
    }
    public static boolean current(int requestedGeneration,int currentGeneration,String requestedRoom,String currentRoom){return requestedGeneration==currentGeneration&&accepts(currentRoom,requestedRoom);}
}
