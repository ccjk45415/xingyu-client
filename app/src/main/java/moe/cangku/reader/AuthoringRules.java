package moe.cangku.reader;

import java.text.*;
import java.util.*;

/** Existing HTML is never round-tripped through a renderer. */
public final class AuthoringRules {
    private AuthoringRules(){}
    public static String bodyHtml(String raw,boolean html){
        if(html)return raw;
        return "<p>"+ReaderContent.escape(raw).replace("\r\n","\n").replace("\r","\n").replace("\n\n","</p><p>").replace("\n","<br>")+"</p>";
    }
    public static List<String> tags(String input){
        LinkedHashSet<String> out=new LinkedHashSet<>();
        for(String s:input.split("[,，\\n]")){s=s.trim();if(!s.isEmpty())out.add(s);}
        return new ArrayList<>(out);
    }
    public static String editablePlainHtml(String raw){return "<p>"+ReaderContent.escape(raw).replace("\r\n","\n").replace("\r","\n").replace("\n","<br>")+"</p>";}
    public static int plainOffset(String raw,int offset){offset=Math.max(0,Math.min(raw.length(),offset));return editablePlainHtml(raw.substring(0,offset)).length()-4;}
    public static long scheduleMillis(String date)throws IllegalArgumentException {
        if(!date.matches("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}"))throw new IllegalArgumentException("时间格式应为 yyyy-MM-dd HH:mm:ss");
        SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd HH:mm:ss",Locale.ROOT);f.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));f.setLenient(false);
        try{return f.parse(date).getTime();}catch(ParseException e){throw new IllegalArgumentException("日期或时间无效");}
    }
    public static boolean conflict(String loaded,String latest){return !loaded.isEmpty()&&!latest.isEmpty()&&!loaded.equals(latest);}
    public static String wrap(String source,int start,int end,String before,String after){
        start=Math.max(0,Math.min(source.length(),start));end=Math.max(start,Math.min(source.length(),end));
        return source.substring(0,start)+before+source.substring(start,end)+after+source.substring(end);
    }
}
