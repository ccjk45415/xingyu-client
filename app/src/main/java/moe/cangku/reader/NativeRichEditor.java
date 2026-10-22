package moe.cangku.reader;

import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.*;
import android.text.*;
import android.text.style.*;
import android.widget.EditText;
import java.util.*;
import java.util.regex.*;

/** Real native editable styled text, backed by untouched HTML. No browser or remote scripts. */
final class NativeRichEditor extends EditText {
    interface Changed {void changed(String source);}
    private RichEditorDocument document=new RichEditorDocument("");private boolean rendering,sourceMode;private int previousRawA,previousRawB;private final ImageLoader pictures;private final Changed changed;
    NativeRichEditor(Context context,ImageLoader pictures,Changed changed){super(context,null,0,R.style.ScrollableEditor);this.pictures=pictures;this.changed=changed;setOverScrollMode(android.view.View.OVER_SCROLL_IF_CONTENT_SCROLLS);setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE|InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int after){if(!rendering){previousRawA=rawStart();previousRawB=rawEnd();}}public void onTextChanged(CharSequence s,int st,int before,int count){}public void afterTextChanged(Editable text){if(rendering)return;String value=text.toString();if(!RichEditorDocument.withinCapacity(value)){document(document.source,previousRawA,previousRawB,sourceMode);android.widget.Toast.makeText(getContext(),"正文请控制在100万字符以内",android.widget.Toast.LENGTH_SHORT).show();return;}int caret=Math.max(0,getSelectionEnd());if(sourceMode){document=new RichEditorDocument(value);changed.changed(value);return;}String old=document.text;int a=0;while(a<old.length()&&a<value.length()&&old.charAt(a)==value.charAt(a))a++;int b=old.length(),end=value.length();while(b>a&&end>a&&old.charAt(b-1)==value.charAt(end-1)){b--;end--;}if(a>0&&((a<old.length()&&Character.isLowSurrogate(old.charAt(a)))||(a<value.length()&&Character.isLowSurrogate(value.charAt(a)))))a--;if(b<old.length()&&Character.isLowSurrogate(old.charAt(b)))b++;if(end<value.length()&&Character.isLowSurrogate(value.charAt(end)))end++;String raw=document.replace(a,b,value.substring(a,end));if(!RichEditorDocument.withinCapacity(raw)){document(document.source,previousRawA,previousRawB,false);android.widget.Toast.makeText(getContext(),"正文请控制在100万字符以内",android.widget.Toast.LENGTH_SHORT).show();return;}RichEditorDocument next=new RichEditorDocument(raw);rendering=true;document=next;if(!value.equals(next.text))setText(next.text);style();setSelection(Math.min(caret,length()));rendering=false;changed.changed(raw);}});}
    // Keep the bounded editor scrollable inside the outer form. At either end,
    // hand a new outward drag to the page so its remaining fields stay reachable.
    private float touchY;private boolean innerDrag;
    @Override public boolean onTouchEvent(android.view.MotionEvent event){
        int action=event.getActionMasked();
        if(action==android.view.MotionEvent.ACTION_DOWN){touchY=event.getY();innerDrag=canScrollVertically(-1)||canScrollVertically(1);if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(innerDrag);}
        else if(action==android.view.MotionEvent.ACTION_MOVE&&innerDrag){float dy=event.getY()-touchY;if(Math.abs(dy)>android.view.ViewConfiguration.get(getContext()).getScaledTouchSlop()){int direction=dy>0?-1:1;if(!canScrollVertically(direction)){innerDrag=false;if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(false);}}}
        boolean handled=super.onTouchEvent(event);
        if(action==android.view.MotionEvent.ACTION_UP||action==android.view.MotionEvent.ACTION_CANCEL){innerDrag=false;if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(false);}
        return handled;
    }
    String source(){return sourceMode?getText().toString():document.source;}
    int rawStart(){return sourceMode?Math.max(0,getSelectionStart()):document.sourceOffset(Math.max(0,getSelectionStart()));}
    int rawEnd(){return sourceMode?Math.max(0,getSelectionEnd()):(getSelectionStart()==getSelectionEnd()?rawStart():document.sourceOffset(Math.max(0,getSelectionEnd()),true));}
    void selectRaw(int a,int b){int from=sourceMode?a:document.visibleOffset(a),to=sourceMode?b:document.visibleOffset(b);setSelection(Math.min(length(),Math.max(0,from)),Math.min(length(),Math.max(0,to)));}
    void document(String source,int a,int b,boolean mode){rendering=true;sourceMode=mode;document=new RichEditorDocument(source);setTypeface(mode?Typeface.MONOSPACE:Typeface.DEFAULT);setText(mode?source:document.text);if(!mode)style();selectRaw(a,b);rendering=false;}
    private void span(Object value,int a,int b){if(a<b&&a>=0&&b<=length())getText().setSpan(value,a,b,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);}
    private void style(){
        Editable text=getText();for(Object old:text.getSpans(0,text.length(),Object.class)){if((old instanceof CharacterStyle||old instanceof ParagraphStyle)&&(text.getSpanFlags(old)&Spanned.SPAN_COMPOSING)==0)text.removeSpan(old);}
        for(RichEditorDocument.Mark mark:document.marks){int a=mark.a,b=mark.b;String tag=mark.tag;
            if(Arrays.asList("b","strong","h1","h2","h3","h4").contains(tag))span(new StyleSpan(Typeface.BOLD),a,b);
            if(tag.equals("i")||tag.equals("em"))span(new StyleSpan(Typeface.ITALIC),a,b);
            if(tag.equals("li"))span(new BulletSpan(16),a,b);if(tag.equals("blockquote"))span(new QuoteSpan(0xff9c87d8),a,b);
            if(tag.equals("u"))span(new UnderlineSpan(),a,b);if(tag.equals("del")||tag.equals("s")||tag.equals("strike"))span(new StrikethroughSpan(),a,b);
            if(tag.matches("h[1-6]"))span(new RelativeSizeSpan(tag.equals("h1")?1.7f:tag.equals("h2")?1.4f:1.15f),a,b);
            if(tag.equals("code")||tag.equals("pre")){span(new TypefaceSpan("monospace"),a,b);span(new BackgroundColorSpan(0x167D69EB),a,b);}
            if(tag.equals("a")){span(new ForegroundColorSpan(0xff7d69eb),a,b);span(new UnderlineSpan(),a,b);}
            if(tag.equals("sup"))span(new SuperscriptSpan(),a,b);if(tag.equals("sub"))span(new SubscriptSpan(),a,b);
            Matcher css=Pattern.compile("(?i)(font-size|font-family|line-height|background-color|color|text-align)\\s*:\\s*([^;\\\"']+)").matcher(mark.style);
            while(css.find()){String key=css.group(1).toLowerCase(Locale.ROOT),value=css.group(2).trim();try{if(key.equals("font-size")){Matcher n=Pattern.compile("([0-9.]+)").matcher(value);if(n.find())span(new AbsoluteSizeSpan(Math.min(96,Math.max(8,(int)Float.parseFloat(n.group(1)))),true),a,b);}else if(key.equals("font-family"))span(new TypefaceSpan(value.replace("\"", "").replace("'", "").split(",")[0].trim()),a,b);else if(key.equals("line-height")){try{float factor=Float.parseFloat(value);if(factor>=1&&factor<=4)span(new LineHeightSpan(){public void chooseHeight(CharSequence t,int start,int end,int v,int y,Paint.FontMetricsInt fm){int h=fm.descent-fm.ascent;fm.descent+=(int)(h*(factor-1));fm.bottom=Math.max(fm.bottom,fm.descent);}},a,b);}catch(NumberFormatException ignored){}}else if(key.equals("color"))span(new ForegroundColorSpan(Color.parseColor(value)),a,b);else if(key.equals("background-color"))span(new BackgroundColorSpan(Color.parseColor(value)),a,b);else if(key.equals("text-align")){Layout.Alignment align=value.equals("center")?Layout.Alignment.ALIGN_CENTER:value.equals("right")?Layout.Alignment.ALIGN_OPPOSITE:Layout.Alignment.ALIGN_NORMAL;int from=a==0?0:document.text.lastIndexOf('\n',a-1)+1;int to=document.text.indexOf('\n',Math.max(a,b-1));if(to<0)to=length();else to++;if(from<to)text.setSpan(new AlignmentSpan.Standard(align),from,to,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);}}catch(IllegalArgumentException ignored){}}
        }
        int position=0;String source=document.source;for(RichEditorDocument.Unit unit:document.units){int a=position,b=a+unit.text.length();position=b;if(unit.kind.equals("image")){
            int width=Math.max(160,Math.min(600,getResources().getDisplayMetrics().widthPixels-96)),height=180;GradientDrawable placeholder=new GradientDrawable();placeholder.setColor(0xffeae5f7);placeholder.setBounds(0,0,width,height);ImageSpan loading=new ImageSpan(placeholder,ImageSpan.ALIGN_BASELINE);span(loading,a,b);pictures.load(unit.detail,bitmap->{if(bitmap==null||sourceMode||!document.source.equals(source))return;Editable current=getText();int start=current.getSpanStart(loading),end=current.getSpanEnd(loading);if(start<0||end<=start)return;BitmapDrawable drawable=new BitmapDrawable(getResources(),bitmap);int h=Math.max(40,Math.min(600,(int)(width*(bitmap.getHeight()/(float)bitmap.getWidth()))));drawable.setBounds(0,0,width,h);current.removeSpan(loading);current.setSpan(new ImageSpan(drawable,ImageSpan.ALIGN_BASELINE),start,end,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);requestLayout();invalidate();});
            }else if(!unit.kind.equals("text")&&!unit.kind.equals("br")&&!unit.kind.equals("break")&&!unit.kind.equals("join")&&!unit.kind.equals("hr")){span(new CardSpan(unit.detail),a,b);}
        }
    }
    private static final class CardSpan extends ReplacementSpan {
        private final String title;CardSpan(String label){title="  ▣ "+label+"  ";}
        public int getSize(Paint p,CharSequence t,int a,int b,Paint.FontMetricsInt f){return (int)p.measureText(title)+16;}
        public void draw(Canvas c,CharSequence t,int a,int b,float x,int top,int y,int bottom,Paint p){int old=p.getColor();p.setColor(0xffeae5f7);c.drawRoundRect(x,top,x+getSize(p,t,a,b,null),bottom,8,8,p);p.setColor(0xff63508c);c.drawText(title,x+8,y,p);p.setColor(old);}
    }
}
