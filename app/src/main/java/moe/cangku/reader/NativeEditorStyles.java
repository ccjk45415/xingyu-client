package moe.cangku.reader;

import android.text.*;
import android.text.style.AbsoluteSizeSpan;
import org.xml.sax.XMLReader;

/** Restore authored font sizes in native reader and local preview, without WebView. */
final class NativeEditorStyles implements Html.TagHandler {
    private final float scale;
    private static final class Marker {final String name;Marker(String name){this.name=name;}}
    NativeEditorStyles(float scale){this.scale=scale;}
    public void handleTag(boolean opening,String tag,Editable output,XMLReader reader){
        if(!tag.matches("xysize[0-9]{2}"))return;
        if(opening){Marker marker=new Marker(tag);output.setSpan(marker,output.length(),output.length(),Spanned.SPAN_MARK_MARK);return;}
        Marker[] markers=output.getSpans(0,output.length(),Marker.class);
        for(int i=markers.length-1;i>=0;i--)if(markers[i].name.equals(tag)){
            int start=output.getSpanStart(markers[i]);output.removeSpan(markers[i]);
            if(start<output.length())output.setSpan(new AbsoluteSizeSpan(Math.round(Integer.parseInt(tag.substring(6))*scale)),start,output.length(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);return;
        }
    }
}
