package moe.cangku.reader;

import java.io.IOException;
import java.net.InetAddress;

/** Pure rules shared by the native fetcher and JVM regressions. Fake IP is not a public IP. */
final class SourceNetworkRules {
    static boolean publicAddress(InetAddress ip){
        byte[] b=ip.getAddress();if(b.length==16)return (b[0]&255)>=32&&(b[0]&255)<=63;
        int a=b[0]&255,c=b[1]&255;
        return !(a==0||a==10||a==127||a>=224||a==169&&c==254||a==172&&c>=16&&c<=31||a==192&&c==168||a==100&&c>=64&&c<=127||a==198&&(c==18||c==19));
    }
    static boolean proxyAddress(InetAddress ip){byte[] b=ip.getAddress();return b.length==4&&(b[0]&255)==198&&((b[1]&255)==18||(b[1]&255)==19);}
    static boolean needsPublicConfirmation(InetAddress[] addresses)throws IOException{
        if(addresses.length==0)throw new IOException("来源域名不可用");boolean proxy=false;
        for(InetAddress ip:addresses){if(proxyAddress(ip))proxy=true;else if(!publicAddress(ip))throw new IOException("来源解析到内网地址，无法提取。请使用公开作品链接");}
        return proxy;
    }
}
