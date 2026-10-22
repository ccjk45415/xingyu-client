package moe.cangku.reader;

import android.content.Context;
import android.graphics.*;
import android.view.View;

/** Consistent 24-unit monochrome editor glyphs, without web fonts or bitmap assets. */
final class EditorToolIcon extends View {
    private final String kind;private final int color;private final Paint p=new Paint(3);
    EditorToolIcon(Context c,String kind,int color){super(c);this.kind=kind;this.color=color;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
    private void label(Canvas c,String s,int style){p.setStyle(Paint.Style.FILL);p.setTypeface(Typeface.create("sans-serif",style));p.setTextAlign(Paint.Align.CENTER);p.setTextSize(s.length()>2?10:17);c.drawText(s,12,18,p);p.setStyle(Paint.Style.STROKE);}
    @Override protected void onDraw(Canvas c){super.onDraw(c);c.save();c.scale(getWidth()/24f,getHeight()/24f);p.setColor(color);p.setStrokeWidth(1.8f);p.setStyle(Paint.Style.STROKE);p.setStrokeCap(Paint.Cap.ROUND);p.setStrokeJoin(Paint.Join.ROUND);Path path=new Path();
        switch(kind){
            case "close":c.drawLine(5,5,19,19,p);c.drawLine(19,5,5,19,p);break;
            case "stop":c.drawCircle(12,12,10,p);c.drawRoundRect(8,8,16,16,1,1,p);break;
            case "save":path.moveTo(3,3);path.lineTo(17,3);path.lineTo(21,7);path.lineTo(21,21);path.lineTo(3,21);path.close();c.drawPath(path,p);c.drawRect(7,3,15,9,p);c.drawRect(7,14,17,21,p);break;
            case "key":c.drawCircle(8,8,5,p);path.moveTo(12,12);path.lineTo(21,21);path.lineTo(21,16);path.moveTo(17,17);path.lineTo(20,14);c.drawPath(path,p);break;
            case "ai":path.moveTo(12,2);path.lineTo(15,9);path.lineTo(22,12);path.lineTo(15,15);path.lineTo(12,22);path.lineTo(9,15);path.lineTo(2,12);path.lineTo(9,9);path.close();c.drawPath(path,p);break;
            case "bold":label(c,"B",Typeface.BOLD);break;case "italic":label(c,"I",Typeface.BOLD_ITALIC);break;
            case "underline":label(c,"U",Typeface.NORMAL);c.drawLine(5,21,19,21,p);break;
            case "strike":label(c,"S",Typeface.NORMAL);c.drawLine(4,12,20,12,p);break;
            case "h1":case "h2":case "h3":label(c,kind.toUpperCase(),Typeface.BOLD);break;
            case "paragraph":label(c,"¶",Typeface.NORMAL);break;
            case "sub":case "sup":label(c,"x",Typeface.NORMAL);p.setStyle(Paint.Style.FILL);p.setTextSize(9);c.drawText("2",20,kind.equals("sub")?22:9,p);break;
            case "size":label(c,"A",Typeface.NORMAL);c.drawLine(2,4,2,20,p);c.drawLine(0,4,4,4,p);c.drawLine(0,20,4,20,p);break;
            case "zoomIn":case "zoomOut":label(c,"A",Typeface.NORMAL);c.drawLine(17,5,23,5,p);if(kind.equals("zoomIn"))c.drawLine(20,2,20,8,p);break;
            case "textColor":label(c,"A",Typeface.NORMAL);p.setStrokeWidth(3);c.drawLine(4,22,20,22,p);break;
            case "fillColor":path.moveTo(6,4);path.lineTo(18,16);path.lineTo(11,22);path.lineTo(1,12);path.lineTo(11,2);c.drawPath(path,p);c.drawLine(4,15,17,15,p);c.drawCircle(21,20,1.6f,p);break;
            case "undo":case "redo":if(kind.equals("redo")){c.translate(24,0);c.scale(-1,1);}c.drawArc(4,7,22,23,210,190,false,p);path.moveTo(3,4);path.lineTo(3,12);path.lineTo(11,12);c.drawPath(path,p);break;
            case "code":path.moveTo(8,6);path.lineTo(2,12);path.lineTo(8,18);path.moveTo(16,6);path.lineTo(22,12);path.lineTo(16,18);c.drawPath(path,p);break;
            case "codeBlock":c.drawRoundRect(3,2,21,22,2,2,p);path.moveTo(9,8);path.lineTo(6,12);path.lineTo(9,16);path.moveTo(15,8);path.lineTo(18,12);path.lineTo(15,16);c.drawPath(path,p);break;
            case "image":case "imageUrl":c.drawRoundRect(3,4,21,21,2,2,p);c.drawCircle(8,9,1.6f,p);path.moveTo(4,20);path.lineTo(10,14);path.lineTo(14,17);path.lineTo(18,12);path.lineTo(21,15);c.drawPath(path,p);if(kind.equals("imageUrl")){c.drawLine(18,1,18,7,p);c.drawLine(15,4,21,4,p);}break;
            case "download":c.drawArc(1,3,23,22,175,195,false,p);c.drawLine(12,8,12,19,p);path.moveTo(8,15);path.lineTo(12,19);path.lineTo(16,15);c.drawPath(path,p);break;
            case "link":c.save();c.rotate(-35,12,12);c.drawRoundRect(2,7,14,17,4,4,p);c.drawRoundRect(10,7,22,17,4,4,p);c.restore();break;
            case "table":c.drawRoundRect(2,3,22,21,1,1,p);c.drawLine(2,9,22,9,p);c.drawLine(2,15,22,15,p);c.drawLine(9,3,9,21,p);c.drawLine(16,3,16,21,p);break;
            case "rule":c.drawLine(3,12,21,12,p);break;
            case "quote":label(c,"“",Typeface.BOLD);break;
            case "list":case "ordered":for(int i=0;i<3;i++){if(kind.equals("ordered")){p.setStyle(Paint.Style.FILL);p.setTextSize(6);c.drawText(String.valueOf(i+1),2,7+i*6,p);p.setStyle(Paint.Style.STROKE);}else c.drawCircle(3,5+i*7,1,p);c.drawLine(8,5+i*7,21,5+i*7,p);}break;
            case "left":case "center":case "right":case "justify":for(int i=0;i<4;i++){float w=(i%2==0||kind.equals("justify"))?18:12;float x=kind.equals("center")?(24-w)/2:kind.equals("right")?21-w:3;c.drawLine(x,4+i*5,x+w,4+i*5,p);}break;
            case "indent":case "outdent":for(int i=0;i<4;i++)c.drawLine(11,4+i*5,21,4+i*5,p);path.moveTo(kind.equals("indent")?3:8,7);path.lineTo(kind.equals("indent")?8:3,12);path.lineTo(kind.equals("indent")?3:8,17);c.drawPath(path,p);break;
            case "clear":label(c,"T",Typeface.NORMAL);c.drawLine(2,2,22,22,p);break;
            case "return":path.moveTo(21,4);path.lineTo(21,12);path.lineTo(3,12);path.lineTo(8,7);path.moveTo(3,12);path.lineTo(8,17);c.drawPath(path,p);break;
            case "find":c.drawCircle(10,9,6,p);c.drawLine(14,14,21,21,p);c.drawLine(2,21,10,21,p);break;
            case "date":c.drawRoundRect(3,4,21,22,2,2,p);c.drawLine(3,10,21,10,p);c.drawLine(7,2,7,6,p);c.drawLine(17,2,17,6,p);label(c,"·",Typeface.BOLD);break;
            case "fontFamily":label(c,"Aa",Typeface.NORMAL);break;
            case "lineHeight":c.drawLine(9,4,21,4,p);c.drawLine(9,12,21,12,p);c.drawLine(9,20,21,20,p);c.drawLine(3,3,3,21,p);path.moveTo(0,6);path.lineTo(3,3);path.lineTo(6,6);path.moveTo(0,18);path.lineTo(3,21);path.lineTo(6,18);c.drawPath(path,p);break;
            case "emoji":c.drawCircle(12,12,10,p);c.drawCircle(8,9,1,p);c.drawCircle(16,9,1,p);c.drawArc(6,8,18,19,15,150,false,p);break;
            case "rainbow":c.drawArc(2,3,22,23,185,170,false,p);c.drawArc(6,7,18,23,190,160,false,p);c.drawArc(10,12,14,23,195,150,false,p);break;
            case "blackbar":c.drawRoundRect(2,6,22,19,2,2,p);c.drawLine(6,12,18,12,p);break;
            case "collapse":c.drawRoundRect(2,3,22,21,2,2,p);c.drawLine(2,9,22,9,p);path.moveTo(8,13);path.lineTo(12,17);path.lineTo(16,13);c.drawPath(path,p);break;
            case "randomFileName":label(c,"#",Typeface.BOLD);break;
            case "poll":c.drawLine(3,21,21,21,p);c.drawRect(4,12,7,20,p);c.drawRect(10,5,13,20,p);c.drawRect(16,9,19,20,p);break;
            case "lottery":c.drawRoundRect(3,8,21,21,2,2,p);c.drawLine(1,8,23,8,p);c.drawLine(12,8,12,21,p);c.drawOval(5,2,12,8,p);c.drawOval(12,2,19,8,p);break;
            case "imageEdit":c.drawRoundRect(2,3,20,20,2,2,p);path.moveTo(4,18);path.lineTo(9,12);path.lineTo(14,17);path.moveTo(14,19);path.lineTo(21,12);path.lineTo(23,14);path.lineTo(16,21);path.close();c.drawPath(path,p);break;
            case "external":c.drawRoundRect(3,5,18,22,2,2,p);c.drawLine(11,13,22,2,p);c.drawLine(16,2,22,2,p);c.drawLine(22,2,22,8,p);break;
            case "selectAll":c.drawRoundRect(3,3,21,21,2,2,p);c.drawLine(7,8,17,8,p);c.drawLine(7,12,17,12,p);c.drawLine(7,16,17,16,p);break;
            case "componentEdit":c.drawRoundRect(2,4,22,20,2,2,p);c.drawLine(7,9,17,9,p);c.drawLine(7,14,14,14,p);c.drawCircle(20,19,3,p);break;
            case "focus":path.moveTo(2,8);path.lineTo(2,2);path.lineTo(8,2);path.moveTo(16,2);path.lineTo(22,2);path.lineTo(22,8);path.moveTo(22,16);path.lineTo(22,22);path.lineTo(16,22);path.moveTo(8,22);path.lineTo(2,22);path.lineTo(2,16);c.drawPath(path,p);break;
            case "help":c.drawCircle(12,12,10,p);label(c,"?",Typeface.BOLD);break;
            case "print":c.drawRoundRect(2,7,22,18,2,2,p);c.drawRect(6,2,18,7,p);c.drawRect(6,14,18,23,p);c.drawCircle(18,10,0.6f,p);break;
            default:label(c,"&",Typeface.NORMAL);
        }c.restore();
    }
}
