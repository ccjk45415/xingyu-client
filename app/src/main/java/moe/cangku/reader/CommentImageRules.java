package moe.cangku.reader;
/** Website comment image contract: one original JPEG/PNG/GIF/WebP file, at most 1024 KiB. */
public final class CommentImageRules {
    public static final int MAX_BYTES=1024*1024;
    private CommentImageRules(){}
    public static String mediaType(byte[] bytes){
        if(bytes==null||bytes.length==0||bytes.length>MAX_BYTES)return "";
        if(bytes.length>=3&&(bytes[0]&255)==255&&(bytes[1]&255)==216&&(bytes[2]&255)==255)return "image/jpeg";
        if(bytes.length>=8&&(bytes[0]&255)==137&&bytes[1]==80&&bytes[2]==78&&bytes[3]==71&&bytes[4]==13&&bytes[5]==10&&bytes[6]==26&&bytes[7]==10)return "image/png";
        if(bytes.length>=6&&bytes[0]==71&&bytes[1]==73&&bytes[2]==70&&bytes[3]==56&&(bytes[4]==55||bytes[4]==57)&&bytes[5]==97)return "image/gif";
        if(bytes.length>=12&&bytes[0]==82&&bytes[1]==73&&bytes[2]==70&&bytes[3]==70&&bytes[8]==87&&bytes[9]==69&&bytes[10]==66&&bytes[11]==80)return "image/webp";
        return "";
    }
}
