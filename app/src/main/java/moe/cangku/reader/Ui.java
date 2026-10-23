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
    Ui(Context ctx,boolean d){c=ctx;dark=d;bg=Color.parseColor(d?"#1B1926":"#F8F7FC");surface=Color.parseColor(d?"#252232":"#FFFFFF");text=Color.parseColor(d?"#F5F1FF":"#28253C");muted=Color.parseColor(d?"#AAA3BE":"#8A839C");line=Color.parseColor(d?"#393348":"#EDE9F6");soft=Color.parseColor(d?"#322B49":"#EFEAFE");}
    int dp(float n){return (int)(n*c.getResources().getDisplayMetrics().density+.5f);}
    LinearLayout column(){LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.VERTICAL);return v;}
    LinearLayout row(){LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    TextView text(String s,float size,int color,boolean bold){TextView t=new TextView(c);t.setText(s);t.setTextSize(size);t.setTextColor(color);t.setFontFeatureSettings("kern");t.setLetterSpacing(.012f);t.setLineSpacing(dp(1),1.12f);if(bold)t.setTypeface(Typeface.create(size>=20?"sans-serif":"sans-serif-medium",size>=20?Typeface.BOLD:Typeface.NORMAL));return t;}
    TextView label(String s,float size){return text(s,size,text,false);}
    GradientDrawable round(int color,float radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));if(color==surface&&radius>=12)d.setStroke(dp(1),line);return d;}
    GradientDrawable gradient(int a,int b,float radius){GradientDrawable d=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{a,b});d.setCornerRadius(dp(radius));return d;}
    void pad(View v,int a,int b,int e,int d){v.setPadding(dp(a),dp(b),dp(e),dp(d));}
    void space(LinearLayout parent,int height){parent.addView(new View(c),new LinearLayout.LayoutParams(1,dp(height)));}
    void click(View v,Runnable action){v.setClickable(true);v.setFocusable(true);v.setOnClickListener(x->action.run());}
    TextView button(String s,boolean filled,Runnable action){
        TextView t=text(s,14,filled?Color.WHITE:accent,true);String glyph=semantic(s,"");if(!glyph.isEmpty()){t.setCompoundDrawables(new Symbol(glyph,filled?Color.WHITE:accent,dp(18)),null,null,null);t.setCompoundDrawablePadding(dp(7));}t.setContentDescription(s);t.setTooltipText(s);t.setGravity(Gravity.CENTER);pad(t,18,13,18,13);
        t.setMinHeight(dp(48));t.setBackground(new RippleDrawable(ColorStateList.valueOf(0x227D69EB),filled?gradient(accent,Color.rgb(150,119,237),14):round(soft,14),null));click(t,action);return t;
    }
    TextView chip(String s,boolean selected,Runnable action){TextView t=text(s,13,selected?Color.WHITE:muted,selected);pad(t,16,10,16,10);t.setGravity(Gravity.CENTER);t.setMinHeight(dp(44));t.setBackground(round(selected?accent:surface,24));click(t,action);return t;}
    FrameLayout iconButton(String name,Runnable action){FrameLayout f=new FrameLayout(c);f.setContentDescription(name);f.setTooltipText(name);f.setBackground(new RippleDrawable(ColorStateList.valueOf(0x227D69EB),round(soft,14),null));Icon icon=new Icon(c,name,accent);FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.CENTER);f.addView(icon,p);click(f,action);return f;}
    View icon(String name,int color){return new Icon(c,name,color);}
    static String semantic(String label,String fallback){
        String[][] rules={{"诊断","诊断"},{"安全|密码|邮箱","安全"},{"外观|字号|日间|夜间|主题","外观"},{"更新|下载","下载"},{"设置|偏好","设置"},{"通知","通知"},{"评论|回复|讨论","评论"},{"私信","私信"},{"聊天|频道","聊天室"},{"粉丝|关注","关注"},{"动态","动态"},{"筛选|定制首页","筛选"},{"分类","分类"},{"排行","排行"},{"投稿|草稿|创作|编辑","投稿"},{"资料","资料"},{"收藏","收藏"},{"足迹|历史","历史"},{"积分|经验","积分"},{"搜索|查找","搜索"},{"刷新|重试|重新","刷新"},{"上传","上传"},{"复制","复制"},{"删除|清空|回收","删除"},{"预览|查看|浏览","预览"},{"保存","保存"},{"AI|智能","AI"},{"链接|官网|注册","链接"},{"上一页|返回","返回"},{"下一页","前进"},{"发布|提交|发送","发送"},{"作者|用户|我的","我的"},{"发现|首页","首页"}};
        for(String[] rule:rules)for(String word:rule[0].split("[|]"))if(label.contains(word))return rule[1];return fallback;
    }
    static final class Symbol extends Drawable {
        final String name;final int color,size;final Paint p=new Paint(3);
        Symbol(String name,int color,int size){this.name=name;this.color=color;this.size=size;setBounds(0,0,size,size);}
        public void draw(Canvas c){Rect b=getBounds();c.save();c.translate(b.left,b.top);Icon.drawSymbol(c,name,color,p,b.width(),b.height());c.restore();}
        public int getIntrinsicWidth(){return size;}public int getIntrinsicHeight(){return size;}public void setAlpha(int a){p.setAlpha(a);}public void setColorFilter(ColorFilter f){p.setColorFilter(f);}public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    static class Icon extends View {
        final String name;final Paint p=new Paint(3);final int color;
        Icon(Context c,String n,int col){super(c);name=n;color=col;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);drawSymbol(canvas,name,color,p,getWidth(),getHeight());}
        static void drawSymbol(Canvas canvas,String name,int color,Paint p,int width,int height){
            canvas.save();canvas.scale(width/24f,height/24f);p.setColor(color);p.setStrokeWidth(1.75f);p.setStyle(Paint.Style.STROKE);p.setStrokeCap(Paint.Cap.ROUND);p.setStrokeJoin(Paint.Join.ROUND);Path path=new Path();
            switch(name){
                case "搜索":canvas.drawCircle(10.5f,10.5f,6.3f,p);canvas.drawLine(15.2f,15.2f,21,21,p);break;
                case "返回":case "前进":if(name.equals("前进")){canvas.translate(24,0);canvas.scale(-1,1);}path.moveTo(14.5f,5);path.lineTo(7.5f,12);path.lineTo(14.5f,19);canvas.drawPath(path,p);break;
                case "动态":canvas.drawCircle(5,19,1,p);canvas.drawArc(-9,5,19,33,270,90,false,p);canvas.drawArc(-3,11,13,27,270,90,false,p);break;
                case "首页":path.moveTo(3,10);path.lineTo(12,3);path.lineTo(21,10);path.lineTo(21,21);path.lineTo(15,21);path.lineTo(15,14);path.lineTo(9,14);path.lineTo(9,21);path.lineTo(3,21);path.close();canvas.drawPath(path,p);break;
                case "分类":for(int x=0;x<2;x++)for(int y=0;y<2;y++)canvas.drawRoundRect(3+x*11,3+y*11,10+x*11,10+y*11,2,2,p);break;
                case "排行":canvas.drawRoundRect(3,13,7,21,1,1,p);canvas.drawRoundRect(10,4,14,21,1,1,p);canvas.drawRoundRect(17,9,21,21,1,1,p);break;
                case "聊天室":case "评论":path.moveTo(5,4);path.lineTo(19,4);path.quadTo(22,4,22,7);path.lineTo(22,15);path.quadTo(22,18,19,18);path.lineTo(10,18);path.lineTo(5,22);path.lineTo(5,18);path.quadTo(2,18,2,15);path.lineTo(2,7);path.quadTo(2,4,5,4);canvas.drawPath(path,p);canvas.drawLine(7,10,17,10,p);canvas.drawLine(7,14,13,14,p);break;
                case "我的":case "作者":case "资料":canvas.drawCircle(12,7,4,p);canvas.drawArc(4,13,20,27,180,180,false,p);break;
                case "关注":canvas.drawCircle(9,7,3.5f,p);canvas.drawArc(2,13,16,26,180,180,false,p);canvas.drawLine(19,10,19,18,p);canvas.drawLine(15,14,23,14,p);break;
                case "收藏":case "已收藏":path.moveTo(6,3);path.lineTo(18,3);path.lineTo(18,22);path.lineTo(12,17);path.lineTo(6,22);path.close();if(name.equals("已收藏"))p.setStyle(Paint.Style.FILL);canvas.drawPath(path,p);break;
                case "分享":canvas.drawCircle(18,4,2.5f,p);canvas.drawCircle(5,12,2.5f,p);canvas.drawCircle(18,20,2.5f,p);canvas.drawLine(7.5f,10.7f,15.5f,5.3f,p);canvas.drawLine(7.5f,13.3f,15.5f,18.7f,p);break;
                case "刷新":canvas.drawArc(4,4,20,20,35,285,false,p);path.moveTo(21,4);path.lineTo(21,10);path.lineTo(15,9);canvas.drawPath(path,p);break;
                case "历史":canvas.drawArc(4,4,21,21,210,310,false,p);canvas.drawLine(3,4,3,10,p);canvas.drawLine(3,10,9,10,p);canvas.drawLine(12,7,12,13,p);canvas.drawLine(12,13,16,15,p);break;
                case "设置":for(int i=0;i<24;i++){double angle=-Math.PI/2+i*Math.PI/12;float r=(i%4==0||i%4==3)?10:8;float x=12+(float)Math.cos(angle)*r,y=12+(float)Math.sin(angle)*r;if(i==0)path.moveTo(x,y);else path.lineTo(x,y);}path.close();canvas.drawPath(path,p);canvas.drawCircle(12,12,3,p);break;
                case "安全":path.moveTo(12,2);path.lineTo(21,6);path.lineTo(20,14);path.quadTo(18,20,12,23);path.quadTo(6,20,4,14);path.lineTo(3,6);path.close();canvas.drawPath(path,p);path.reset();path.moveTo(8,12);path.lineTo(11,15);path.lineTo(16,9);canvas.drawPath(path,p);break;
                case "通知":path.moveTo(5,17);path.lineTo(6,9);path.quadTo(6,3,12,3);path.quadTo(18,3,18,9);path.lineTo(19,17);path.close();canvas.drawPath(path,p);canvas.drawArc(9,17,15,23,0,180,false,p);break;
                case "私信":canvas.drawRoundRect(2,5,22,20,3,3,p);path.moveTo(3,6);path.lineTo(12,13);path.lineTo(21,6);canvas.drawPath(path,p);break;
                case "投稿":canvas.drawRoundRect(3,3,17,22,2,2,p);canvas.drawLine(7,7,12,7,p);canvas.drawLine(7,11,11,11,p);path.moveTo(12,17);path.lineTo(19,10);path.lineTo(22,13);path.lineTo(15,20);path.lineTo(11,21);path.close();canvas.drawPath(path,p);break;
                case "筛选":canvas.drawLine(3,6,21,6,p);canvas.drawLine(3,12,21,12,p);canvas.drawLine(3,18,21,18,p);for(int i=0;i<3;i++){p.setStyle(Paint.Style.FILL);canvas.drawCircle(i==1?15:8,6+i*6,2.5f,p);}break;
                case "外观":canvas.drawCircle(12,12,9,p);p.setStyle(Paint.Style.FILL);canvas.drawCircle(8,8,1.4f,p);canvas.drawCircle(14,6,1.4f,p);canvas.drawCircle(18,11,1.4f,p);p.setStyle(Paint.Style.STROKE);canvas.drawCircle(10,16,2.5f,p);break;
                case "积分":canvas.drawOval(3,4,21,11,p);canvas.drawArc(3,8,21,15,0,180,false,p);canvas.drawArc(3,12,21,19,0,180,false,p);canvas.drawLine(3,7,3,16,p);canvas.drawLine(21,7,21,16,p);break;
                case "下载":case "上传":canvas.drawLine(4,18,4,22,p);canvas.drawLine(4,22,20,22,p);canvas.drawLine(20,22,20,18,p);if(name.equals("上传")){canvas.translate(0,18);canvas.scale(1,-1);}canvas.drawLine(12,2,12,15,p);path.moveTo(7,10);path.lineTo(12,15);path.lineTo(17,10);canvas.drawPath(path,p);break;
                case "复制":canvas.drawRoundRect(8,7,21,22,2,2,p);path.moveTo(16,3);path.lineTo(3,3);path.lineTo(3,17);canvas.drawPath(path,p);break;
                case "删除":canvas.drawLine(3,6,21,6,p);canvas.drawLine(8,3,16,3,p);path.moveTo(5,6);path.lineTo(6,22);path.lineTo(18,22);path.lineTo(19,6);canvas.drawPath(path,p);canvas.drawLine(10,10,10,18,p);canvas.drawLine(14,10,14,18,p);break;
                case "预览":path.moveTo(2,12);path.quadTo(12,-1,22,12);path.quadTo(12,25,2,12);canvas.drawPath(path,p);canvas.drawCircle(12,12,3,p);break;
                case "保存":path.moveTo(3,3);path.lineTo(17,3);path.lineTo(21,7);path.lineTo(21,21);path.lineTo(3,21);path.close();canvas.drawPath(path,p);canvas.drawRect(7,3,15,9,p);canvas.drawRect(7,14,17,21,p);break;
                case "链接":canvas.rotate(-35,12,12);canvas.drawRoundRect(2,7,14,17,4,4,p);canvas.drawRoundRect(10,7,22,17,4,4,p);break;
                case "发送":path.moveTo(2,3);path.lineTo(22,12);path.lineTo(2,21);path.lineTo(6,12);path.close();canvas.drawPath(path,p);canvas.drawLine(6,12,22,12,p);break;
                case "诊断":canvas.drawRoundRect(7,6,17,21,4,4,p);canvas.drawLine(9,3,15,3,p);for(int i=0;i<3;i++){canvas.drawLine(3,9+i*5,7,9+i*5,p);canvas.drawLine(17,9+i*5,21,9+i*5,p);}canvas.drawLine(12,10,12,17,p);break;
                case "AI":path.moveTo(12,2);path.lineTo(15,9);path.lineTo(22,12);path.lineTo(15,15);path.lineTo(12,22);path.lineTo(9,15);path.lineTo(2,12);path.lineTo(9,9);path.close();canvas.drawPath(path,p);break;
                default:canvas.drawCircle(12,12,9,p);canvas.drawLine(12,10,12,17,p);p.setStyle(Paint.Style.FILL);canvas.drawCircle(12,6,1,p);break;
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
