package moe.cangku.reader;

/** Obfuscation only: a public service address cannot be kept secret inside an APK. */
final class ServiceEndpoint {
    private static final int[] DATA={5,248,223,186,154,50,8,105,29,237,205,165,152,117,50,93,53,29,239,151,186,155,125,93,97,65,167,131,228,222,127,79,42,9,248,132,173,141,113};
    static String origin(){char[] chars=new char[DATA.length];for(int i=0;i<chars.length;i++)chars[i]=(char)(DATA[i]^((0x6d+i*31)&255));return new String(chars);}
}
