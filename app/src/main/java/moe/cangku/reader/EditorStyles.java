package moe.cangku.reader;

import java.util.*;
import java.util.regex.*;

/** Display-only font size markers for Android's limited native HTML parser. */
public final class EditorStyles {
    private EditorStyles(){}
    public static String markFontSizes(String html){
        Matcher tag=Pattern.compile("(?is)</?span\\b[^>]*>").matcher(html);ArrayDeque<Integer> sizes=new ArrayDeque<>();StringBuffer out=new StringBuffer();
        while(tag.find()){
            String raw=tag.group(),replacement=raw;
            if(raw.startsWith("</")){
                if(!sizes.isEmpty()){int size=sizes.removeLast();if(size>0)replacement="</xysize"+size+">"+raw;}
            }else{
                Matcher style=Pattern.compile("(?i)\\bfont-size\\s*:\\s*([0-9]{1,2})px\\b").matcher(raw);int size=style.find()?Integer.parseInt(style.group(1)):0;if(size<10||size>72)size=0;
                sizes.addLast(size);if(size>0)replacement=raw+"<xysize"+size+">";
            }
            tag.appendReplacement(out,Matcher.quoteReplacement(replacement));
        }
        tag.appendTail(out);return out.toString();
    }
}
