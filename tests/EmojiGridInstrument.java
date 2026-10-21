package moe.cangku.reader;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;

/** Runs actual Android measurement and drawing in a separate APK without Internet permission. */
public final class EmojiGridInstrument extends Instrumentation {
    private int checks;private Throwable error;
    private final int[] counts={9,66,33,92,122};
    private void check(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    @Override public void onStart(){Bundle result=new Bundle();
        try{
            runOnMainSync(()->{try{exercise();}catch(Throwable failure){error=failure;}});
            if(error!=null)throw new AssertionError(error);
            result.putString("stream","EMOJI_GRID_DEVICE_PASS "+checks+" checks; actual Android views, synthetic images, no Internet\n");finish(Activity.RESULT_OK,result);
        }catch(Throwable failure){result.putString("stream","EMOJI_GRID_DEVICE_FAIL "+failure+"\n");finish(Activity.RESULT_CANCELED,result);}
    }
    private void exercise()throws Exception{
        for(float font:new float[]{1f,1.6f,2f}){
            Configuration config=new Configuration(getTargetContext().getResources().getConfiguration());config.fontScale=font;
            Context context=getTargetContext().createConfigurationContext(config);Ui ui=new Ui(context,false);
            for(int widthDp:new int[]{240,280,320,360,600}){
                for(int count:counts)for(int start=1;start<=count;start+=24){
                    ArrayList<View> cells=new ArrayList<>();
                    CommentEmojiGrid grid=new CommentEmojiGrid(context);
                    for(int id=start;id<=Math.min(count,start+23);id++)cells.add(cell(context,ui,id));
                    grid.setCells(cells);measure(grid,ui.dp(widthDp));
                    int seen=0,lastBottom=0;
                    for(int rowIndex=0;rowIndex<grid.getChildCount();rowIndex++){
                        ViewGroup row=(ViewGroup)grid.getChildAt(rowIndex);check(row.getTop()>=lastBottom,"overlapping rows");lastBottom=row.getBottom();
                        int lastRight=0,firstWidth=-1;
                        for(int col=0;col<row.getChildCount()&&seen<cells.size();col++,seen++){
                            ViewGroup item=(ViewGroup)row.getChildAt(col);check(item==cells.get(seen),"sticker ordering");
                            check(item.getWidth()>=ui.dp(46),"collapsed/tiny sticker cell");
                            check(item.getLeft()>=lastRight&&item.getRight()<=row.getWidth(),"clipped or overlapping cell");lastRight=item.getRight();
                            if(firstWidth<0)firstWidth=item.getWidth();check(Math.abs(firstWidth-item.getWidth())<=1,"unequal cell widths");
                            for(int child=0;child<item.getChildCount();child++){
                                View content=item.getChildAt(child);check(content.getWidth()>0&&content.getHeight()>0,"invisible sticker content");
                                check(content.getLeft()>=0&&content.getRight()<=item.getWidth()&&content.getTop()>=0&&content.getBottom()<=item.getHeight(),"cropped sticker or number");
                            }
                        }
                    }
                    check(seen==cells.size(),"missing stickers");
                    // A resize of the same production view must rebuild rows without losing cells.
                    measure(grid,ui.dp(widthDp==240?600:240));check(grid.getChildCount()>0,"resize lost rows");
                    CommentEmojiGrid.Viewport viewport=new CommentEmojiGrid.Viewport(context);viewport.addView(grid,new ScrollView.LayoutParams(-1,-2));measure(viewport,ui.dp(widthDp));
                    check(viewport.getMeasuredHeight()<=ui.dp(320),"sticker panel exceeds scroll cap");
                    if(font==1f&&widthDp==280&&start==1&&(count==9||count==66))save(viewport,"emoji-grid-"+count+".png");
                    if(font==2f&&widthDp==320&&count==9&&start==1)save(viewport,"emoji-grid-large-font.png");
                }
            }
        }
    }
    private LinearLayout cell(Context context,Ui ui,int index){
        LinearLayout cell=ui.column();cell.setGravity(Gravity.CENTER);cell.setBackground(ui.round(ui.soft,10));
        ImageView image=new ImageView(context);image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        Bitmap face=Bitmap.createBitmap(34,34,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(face);canvas.drawColor(Color.rgb(145,116,224));
        image.setImageBitmap(face);cell.addView(image,new LinearLayout.LayoutParams(ui.dp(34),ui.dp(34)));
        TextView number=ui.text(String.valueOf(index),10,ui.muted,false);number.setGravity(Gravity.CENTER);number.setSingleLine(true);cell.addView(number);return cell;
    }
    private void measure(View view,int width){view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());}
    private void save(View view,String name)throws Exception{
        Bitmap bitmap=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(bitmap);canvas.drawColor(Color.WHITE);view.draw(canvas);
        try(FileOutputStream output=new FileOutputStream(new File(getTargetContext().getExternalFilesDir(null),name))){bitmap.compress(Bitmap.CompressFormat.PNG,100,output);}bitmap.recycle();
    }
}
