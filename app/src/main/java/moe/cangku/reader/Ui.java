package moe.cangku.reader;

import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;
import android.content.res.ColorStateList;

final class Ui {
    final Context c; final boolean dark;
    final int bg,surface,text,muted,line,soft,accent=Color.rgb(125,105,235),pink=Color.rgb(232,143,194);
    Ui(Context ctx,boolean d){c=ctx;dark=d;bg=Color.parseColor(d?"#151420":"#F8F7FF");surface=Color.parseColor(d?"#211F30":"#FFFFFF");text=Color.parseColor(d?"#F5F1FF":"#28253C");muted=Color.parseColor(d?"#AAA3BE":"#8A839C");line=Color.parseColor(d?"#393348":"#EDE9F6");soft=Color.parseColor(d?"#322B49":"#EFEAFE");}
    int dp(float n){return (int)(n*c.getResources().getDisplayMetrics().density+.5f);}
    LinearLayout column(){LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.VERTICAL);return v;}
    LinearLayout row(){LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    TextView text(String s,float size,int color,boolean bold){TextView t=new TextView(c);t.setText(s);t.setTextSize(size);t.setTextColor(color);t.setFontFeatureSettings("kern");if(bold)t.setTypeface(Typeface.create("sans-serif",Typeface.BOLD));return t;}
    TextView label(String s,float size){return text(s,size,text,false);}
    GradientDrawable round(int color,float radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    GradientDrawable gradient(int a,int b,float radius){GradientDrawable d=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{a,b});d.setCornerRadius(dp(radius));return d;}
    void pad(View v,int a,int b,int e,int d){v.setPadding(dp(a),dp(b),dp(e),dp(d));}
    void space(LinearLayout parent,int height){parent.addView(new View(c),new LinearLayout.LayoutParams(1,dp(height)));}
    void click(View v,Runnable action){v.setClickable(true);v.setFocusable(true);v.setOnClickListener(x->action.run());}
    TextView button(String s,boolean filled,Runnable action){
        TextView t=text(s,14,filled?Color.WHITE:accent,true);t.setGravity(Gravity.CENTER);pad(t,18,13,18,13);
        t.setMinHeight(dp(48));t.setBackground(new RippleDrawable(ColorStateList.valueOf(0x227D69EB),round(filled?accent:soft,16),null));click(t,action);return t;
    }
    TextView chip(String s,boolean selected,Runnable action){TextView t=text(s,13,selected?Color.WHITE:muted,selected);pad(t,16,10,16,10);t.setGravity(Gravity.CENTER);t.setMinHeight(dp(44));t.setBackground(round(selected?accent:surface,24));click(t,action);return t;}
    FrameLayout iconButton(String name,Runnable action){FrameLayout f=new FrameLayout(c);f.setContentDescription(name);f.setBackground(round(soft,16));Icon icon=new Icon(c,name,accent);FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.CENTER);f.addView(icon,p);click(f,action);return f;}
    View icon(String name,int color){return new Icon(c,name,color);}
    static class Icon extends View {
        final String name;final Paint p=new Paint(3);final int color;
        Icon(Context c,String n,int col){super(c);name=n;color=col;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
        @Override protected void onDraw(Canvas canvas){
            super.onDraw(canvas);canvas.save();canvas.scale(getWidth()/24f,getHeight()/24f);p.setColor(color);p.setStrokeWidth(1.8f);p.setStyle(Paint.Style.STROKE);p.setStrokeCap(Paint.Cap.ROUND);p.setStrokeJoin(Paint.Join.ROUND);
            Path path=new Path();
            switch(name){
                case "搜索":canvas.drawCircle(10.5f,10.5f,6.5f,p);canvas.drawLine(16,16,21,21,p);break;
                case "返回":path.moveTo(14.5f,5);path.lineTo(7.5f,12);path.lineTo(14.5f,19);canvas.drawPath(path,p);break;
                case "动态":canvas.drawCircle(12,12,3,p);canvas.drawArc(3,3,21,21,30,120,false,p);canvas.drawArc(3,3,21,21,210,120,false,p);break;
                case "首页":path.moveTo(3,10);path.lineTo(12,3);path.lineTo(21,10);path.lineTo(21,21);path.lineTo(15,21);path.lineTo(15,14);path.lineTo(9,14);path.lineTo(9,21);path.lineTo(3,21);path.close();canvas.drawPath(path,p);break;
                case "分类":for(int x=0;x<2;x++)for(int y=0;y<2;y++)canvas.drawRoundRect(3+x*11,3+y*11,10+x*11,10+y*11,2,2,p);break;
                case "排行":canvas.drawRoundRect(3,13,7,21,1,1,p);canvas.drawRoundRect(10,4,14,21,1,1,p);canvas.drawRoundRect(17,9,21,21,1,1,p);break;
                case "聊天室":path.moveTo(5,3);path.lineTo(19,3);path.quadTo(22,3,22,6);path.lineTo(22,15);path.quadTo(22,18,19,18);path.lineTo(10,18);path.lineTo(5,22);path.lineTo(5,18);path.quadTo(2,18,2,15);path.lineTo(2,6);path.quadTo(2,3,5,3);canvas.drawPath(path,p);p.setStyle(Paint.Style.FILL);canvas.drawCircle(7,10.5f,1,p);canvas.drawCircle(12,10.5f,1,p);canvas.drawCircle(17,10.5f,1,p);break;
                case "我的":case "作者":canvas.drawCircle(12,7,4,p);canvas.drawArc(4,13,20,27,180,180,false,p);break;
                case "收藏":case "已收藏":path.moveTo(6,3);path.lineTo(18,3);path.lineTo(18,22);path.lineTo(12,17);path.lineTo(6,22);path.close();if(name.equals("已收藏"))p.setStyle(Paint.Style.FILL);canvas.drawPath(path,p);break;
                case "分享":canvas.drawCircle(18,4,2.5f,p);canvas.drawCircle(5,12,2.5f,p);canvas.drawCircle(18,20,2.5f,p);canvas.drawLine(7.5f,10.7f,15.5f,5.3f,p);canvas.drawLine(7.5f,13.3f,15.5f,18.7f,p);break;
                case "刷新":canvas.drawArc(4,4,20,20,35,295,false,p);path.moveTo(21,4);path.lineTo(21,10);path.lineTo(15,9);canvas.drawPath(path,p);break;
                case "历史":canvas.drawCircle(12,12,9,p);canvas.drawLine(12,6,12,12,p);canvas.drawLine(12,12,16,14,p);break;
                case "设置":canvas.drawCircle(12,12,8,p);canvas.drawCircle(12,12,3,p);break;
                default:for(int i=0;i<10;i++){double angle=-Math.PI/2+i*Math.PI/5;float r=i%2==0?10:4.6f;float x=12+(float)Math.cos(angle)*r,y=12+(float)Math.sin(angle)*r;if(i==0)path.moveTo(x,y);else path.lineTo(x,y);}path.close();canvas.drawPath(path,p);
            }
            canvas.restore();
        }
    }
    static final class Aurora extends View {
        final Paint paint=new Paint(3);
        Aurora(Context c){super(c);setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
        @Override protected void onDraw(Canvas c){
            float w=getWidth(),h=getHeight();paint.setShader(new LinearGradient(0,0,w,h,new int[]{0xFF8871EC,0xFFB193ED,0xFFE3B6DD},null,Shader.TileMode.CLAMP));c.drawRoundRect(0,0,w,h,30,30,paint);paint.setShader(null);
            paint.setColor(0x28FFFFFF);c.drawCircle(w*.9f,h*.28f,h*.62f,paint);c.drawCircle(w*.98f,h*.13f,h*.46f,paint);paint.setColor(0x66FFFFFF);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(1.4f);c.drawCircle(w*.82f,h*.5f,h*.25f,paint);paint.setStyle(Paint.Style.FILL);
            for(int i=0;i<18;i++){float x=w*((i*73%97)/100f),y=h*((i*31%89)/100f);paint.setColor(i%3==0?0xDDFFFFFF:0x77FFFFFF);c.drawCircle(x,y,i%3==0?3:1.7f,paint);}
        }
    }
}
