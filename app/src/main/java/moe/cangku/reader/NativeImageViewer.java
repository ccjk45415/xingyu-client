package moe.cangku.reader;

import android.app.Dialog;
import android.graphics.*;
import android.graphics.drawable.ColorDrawable;
import android.view.*;
import android.widget.*;

/** Native, bounded bitmap viewer with pinch/double-tap zoom and pan; no embedded browser. */
final class NativeImageViewer {
    static void show(MainActivity host,String url){
        Ui ui=host.design();Dialog dialog=new Dialog(host,android.R.style.Theme_Material_NoActionBar_Fullscreen);LinearLayout root=ui.column();root.setBackgroundColor(0xFF101018);LinearLayout bar=ui.row();ui.pad(bar,12,8,12,8);TextView close=ui.text("关闭",14,0xFFFFFFFF,true);close.setGravity(Gravity.CENTER);close.setMinHeight(ui.dp(44));bar.addView(close,new LinearLayout.LayoutParams(ui.dp(70),-2));ui.click(close,dialog::dismiss);TextView title=ui.text("查看图片",14,0xFFFFFFFF,true);title.setGravity(Gravity.CENTER);bar.addView(title,new LinearLayout.LayoutParams(0,-2,1));TextView copy=ui.text("复制链接",12,0xFFBDB1FF,false);copy.setGravity(Gravity.CENTER);copy.setMinHeight(ui.dp(44));bar.addView(copy,new LinearLayout.LayoutParams(ui.dp(80),-2));ui.click(copy,()->host.copyText(url));root.addView(bar);
        ZoomImage image=new ZoomImage(host);image.setContentDescription("作品图片，双指缩放、双击放大，长按识别二维码");root.addView(image,new LinearLayout.LayoutParams(-1,0,1));TextView hint=ui.text("正在加载图片…",12,0xFFBCB8CD,false);hint.setGravity(Gravity.CENTER);ui.pad(hint,14,12,14,16);root.addView(hint);dialog.setContentView(root);if(dialog.getWindow()!=null){dialog.getWindow().setBackgroundDrawable(new ColorDrawable(0xFF101018));dialog.getWindow().setLayout(-1,-1);}dialog.show();if(dialog.getWindow()!=null)dialog.getWindow().setLayout(-1,-1);
        host.pictures().load(url,bitmap->{if(!dialog.isShowing()||host.isFinishing()||host.isDestroyed())return;if(bitmap==null){hint.setText("图片加载失败，请返回重试；也可复制图片链接");return;}image.setImageBitmap(bitmap);image.longPress=()->host.recognizeQr(bitmap);hint.setText("双指缩放 · 双击放大 · 拖动查看 · 长按识别二维码");});
    }
    private static final class ZoomImage extends ImageView {
        private final Matrix matrix=new Matrix();private final float[] values=new float[9];private final ScaleGestureDetector scale;private final GestureDetector taps;private float base=1,current=1,lastX,lastY;private boolean dragging;Runnable longPress;
        ZoomImage(MainActivity host){super(host);setScaleType(ScaleType.MATRIX);scale=new ScaleGestureDetector(host,new ScaleGestureDetector.SimpleOnScaleGestureListener(){@Override public boolean onScale(ScaleGestureDetector detector){zoom(detector.getScaleFactor(),detector.getFocusX(),detector.getFocusY());return true;}});taps=new GestureDetector(host,new GestureDetector.SimpleOnGestureListener(){@Override public boolean onDown(MotionEvent e){return true;}@Override public boolean onDoubleTap(MotionEvent e){zoom(current>base*1.3f?base/current:2.5f,e.getX(),e.getY());return true;}@Override public void onLongPress(MotionEvent e){if(longPress!=null)longPress.run();}});}
        @Override public void setImageBitmap(Bitmap b){super.setImageBitmap(b);post(this::fit);}
        @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){super.onSizeChanged(w,h,oldw,oldh);fit();}
        private void fit(){if(getDrawable()==null||getWidth()==0||getHeight()==0)return;float w=getDrawable().getIntrinsicWidth(),h=getDrawable().getIntrinsicHeight();if(w<=0||h<=0)return;base=Math.min(getWidth()/w,getHeight()/h);current=base;matrix.reset();matrix.postScale(base,base);matrix.postTranslate((getWidth()-w*base)/2,(getHeight()-h*base)/2);setImageMatrix(matrix);}
        private void zoom(float factor,float x,float y){float next=Math.max(base,Math.min(base*6,current*factor));matrix.postScale(next/current,next/current,x,y);current=next;bound();}
        private void bound(){if(getDrawable()==null)return;matrix.getValues(values);float w=getDrawable().getIntrinsicWidth()*current,h=getDrawable().getIntrinsicHeight()*current,x=values[Matrix.MTRANS_X],y=values[Matrix.MTRANS_Y];float nx=w<=getWidth()?(getWidth()-w)/2:Math.min(0,Math.max(getWidth()-w,x)),ny=h<=getHeight()?(getHeight()-h)/2:Math.min(0,Math.max(getHeight()-h,y));matrix.postTranslate(nx-x,ny-y);setImageMatrix(matrix);}
        @Override public boolean onTouchEvent(MotionEvent event){scale.onTouchEvent(event);taps.onTouchEvent(event);switch(event.getActionMasked()){case MotionEvent.ACTION_DOWN:lastX=event.getX();lastY=event.getY();dragging=true;break;case MotionEvent.ACTION_POINTER_DOWN:dragging=false;break;case MotionEvent.ACTION_MOVE:if(event.getPointerCount()==1&&dragging&&!scale.isInProgress()){matrix.postTranslate(event.getX()-lastX,event.getY()-lastY);bound();}lastX=event.getX();lastY=event.getY();break;case MotionEvent.ACTION_UP:case MotionEvent.ACTION_CANCEL:dragging=false;break;case MotionEvent.ACTION_POINTER_UP:dragging=false;break;}return true;}
        @Override public boolean performClick(){super.performClick();return true;}
    }
}
