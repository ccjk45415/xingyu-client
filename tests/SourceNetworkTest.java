package moe.cangku.reader;
import java.net.*;
import java.io.*;
public final class SourceNetworkTest {
    static int checks;
    static void check(boolean value){checks++;if(!value)throw new AssertionError("source rule check "+checks);}
    static InetAddress ip(String value)throws Exception{return InetAddress.getByName(value);}
    public static void main(String[] args)throws Exception{
        for(String value:new String[]{"198.18.0.1","198.18.5.104","198.19.255.254"}){
            check(SourceNetworkRules.proxyAddress(ip(value)));check(!SourceNetworkRules.publicAddress(ip(value)));check(SourceNetworkRules.needsPublicConfirmation(new InetAddress[]{ip(value)}));
        }
        for(String value:new String[]{"1.1.1.1","104.18.2.173","2606:4700:4700::1111"}){check(SourceNetworkRules.publicAddress(ip(value)));check(!SourceNetworkRules.proxyAddress(ip(value)));check(!SourceNetworkRules.needsPublicConfirmation(new InetAddress[]{ip(value)}));}
        for(String value:new String[]{"127.0.0.1","10.0.0.1","192.168.1.1","172.16.0.1","169.254.169.254","100.64.1.1","::1","fc00::1","fe80::1","::ffff:127.0.0.1"}){
            check(!SourceNetworkRules.publicAddress(ip(value)));check(!SourceNetworkRules.proxyAddress(ip(value)));
            try{SourceNetworkRules.needsPublicConfirmation(new InetAddress[]{ip("198.18.5.104"),ip(value)});throw new AssertionError("private DNS answer admitted");}catch(IOException expected){checks++;}
        }
        check(SourceNetworkRules.needsPublicConfirmation(new InetAddress[]{ip("104.18.2.173"),ip("198.18.5.104")}));
        try{SourceNetworkRules.needsPublicConfirmation(new InetAddress[0]);throw new AssertionError("empty DNS admitted");}catch(IOException expected){checks++;}
        System.out.println("PASS "+checks+" native source DNS rules: public, proxy confirmation and private/mixed rejection");
    }
}
