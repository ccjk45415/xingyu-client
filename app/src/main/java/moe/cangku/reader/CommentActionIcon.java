package moe.cangku.reader;
import android.graphics.*;
import android.graphics.drawable.Drawable;

/** Consistent stroke icons rather than platform-dependent text glyphs. */
final class CommentActionIcon extends Drawable {
    private final String kind;private final int color;private final Paint paint=new Paint(3);
    CommentActionIcon(String name,int color,int size){kind=name;this.color=color;setBounds(0,0,size,size);}
    @Override public void draw(Canvas c){c.save();c.translate(getBounds().left,getBounds().top);c.scale(getBounds().width()/24f,getBounds().height()/24f);paint.setColor(color);paint.setStrokeWidth(1.7f);paint.setStyle(Paint.Style.STROKE);paint.setStrokeCap(Paint.Cap.ROUND);paint.setStrokeJoin(Paint.Join.ROUND);Path p=new Path();
        if(kind.equals("点赞")||kind.equals("已赞")){p.moveTo(12,21);p.cubicTo(9,18,2.5f,13.5f,2.5f,8.3f);p.cubicTo(2.5f,2.7f,9.5f,1.4f,12,6);p.cubicTo(14.5f,1.4f,21.5f,2.7f,21.5f,8.3f);p.cubicTo(21.5f,13.5f,15,18,12,21);p.close();if(kind.equals("已赞"))paint.setStyle(Paint.Style.FILL);c.drawPath(p,paint);}
        else if(kind.equals("回复")){c.drawRoundRect(3,3,21,18,4,4,paint);p.moveTo(8,18);p.lineTo(6,22);p.lineTo(13,18);c.drawPath(p,paint);c.drawLine(7,8,17,8,paint);c.drawLine(7,12,14,12,paint);}
        else {c.drawLine(4,6,20,6,paint);c.drawLine(9,3,15,3,paint);p.moveTo(6,6);p.lineTo(7,21);p.lineTo(17,21);p.lineTo(18,6);c.drawPath(p,paint);c.drawLine(10,10,10,17,paint);c.drawLine(14,10,14,17,paint);}c.restore();}
    @Override public void setAlpha(int a){paint.setAlpha(a);}@Override public void setColorFilter(ColorFilter f){paint.setColorFilter(f);}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
}
