package moe.cangku.xingyu_desktop;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import java.net.*;
import java.util.Map;

/** App-private policy shared by system-scheduled jobs. Never changes device proxy. */
final class NetworkProxy {
    private static SharedPreferences prefs(Context c){return c.getSharedPreferences("xingyu.network",Context.MODE_PRIVATE);}
    static void configure(Context c,Map<?,?> value){
        String mode=String.valueOf(value.get("mode")),scope=String.valueOf(value.get("scope")),host=String.valueOf(value.get("host"));
        int port=value.get("port") instanceof Number?((Number)value.get("port")).intValue():0;
        if(!java.util.Arrays.asList("system","direct","manual").contains(mode)||!java.util.Arrays.asList("all","updates").contains(scope))throw new IllegalArgumentException();
        if(mode.equals("manual")&&(host.isEmpty()||host.length()>253||!host.matches("[A-Za-z0-9.\\-:\\[\\]]+")||port<1||port>65535))throw new IllegalArgumentException();
        if(!prefs(c).edit().putString("mode",mode).putString("scope",scope).putString("host",host).putInt("port",port).commit())throw new IllegalStateException();
    }
    static Proxy forUrl(Context c,URL url){
        SharedPreferences p=prefs(c);String mode=p.getString("mode","system");
        if(mode.equals("direct"))return Proxy.NO_PROXY;
        boolean updates=java.util.Arrays.asList("api.shorebird.dev","cdn.shorebird.cloud","download.shorebird.dev","storage.googleapis.com").contains(url.getHost())||url.getPath().startsWith("/updates/")||url.getPath().startsWith("/releases/");
        if(mode.equals("manual")&&(p.getString("scope","all").equals("all")||updates)){
            String host=p.getString("host","").replace("[","").replace("]","");int port=p.getInt("port",0);
            if(host.isEmpty()||port<1||port>65535)throw new IllegalStateException();
            return new Proxy(Proxy.Type.HTTP,InetSocketAddress.createUnresolved(host,port));
        }
        ConnectivityManager manager=c.getSystemService(ConnectivityManager.class);ProxyInfo info=manager==null?null:manager.getDefaultProxy();
        if(info==null||info.getHost()==null||info.getPort()<1)return Proxy.NO_PROXY;
        for(String raw:info.getExclusionList()){
            String rule=raw.trim().toLowerCase();if(rule.isEmpty())continue;
            String regex=java.util.regex.Pattern.quote(rule).replace("*","\\E.*\\Q");
            if(url.getHost().toLowerCase().matches(regex))return Proxy.NO_PROXY;
        }
        return new Proxy(Proxy.Type.HTTP,InetSocketAddress.createUnresolved(info.getHost(),info.getPort()));
    }
}
