package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.os.*;
import android.print.*;
import android.print.pdf.PrintedPdfDocument;
import android.text.*;
import android.util.TypedValue;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;

/** Native post snapshot -> Android system print/PDF. Never creates a WebView or submits a post. */
final class NativePostPrinter {
    private NativePostPrinter(){}
    static void open(MainActivity host,String title,String raw){
        PrintManager manager=(PrintManager)host.getSystemService(Context.PRINT_SERVICE);if(manager==null){host.toast("此设备没有可用的系统打印服务");return;}
        ReaderContent parsed=ReaderContent.parse(raw);StringBuilder html=new StringBuilder(ReaderContent.nativeCodeBlocks(parsed.html));for(ReaderContent.Resource resource:parsed.resources){html.append("<h3>").append(ReaderContent.escape(resource.title)).append("</h3><p>").append(ReaderContent.escape(resource.details())).append("</p>");for(Map.Entry<String,String> entry:resource.links.entrySet())html.append("<p>").append(ReaderContent.escape(entry.getKey()+"："+entry.getValue())).append("</p>");}
        LinkedHashMap<String,Picture> images=new LinkedHashMap<>();Spanned body=Html.fromHtml(EditorStyles.markFontSizes(html.toString()),Html.FROM_HTML_MODE_COMPACT,url->{String resolved=url.startsWith("//")?"https:"+url:url.startsWith("/")?UrlPolicy.ORIGIN+url:url;Picture image=images.get(resolved);if(image==null){image=new Picture();images.put(resolved,image);}return image;},new NativeEditorStyles(1));
        if(images.size()>80){host.toast("正文包含超过80张图片，请缩小打印内容；当前正文未修改");return;}
        TextView status=new TextView(host);status.setTextColor(host.design().text);host.design().pad(status,20,16,20,16);status.setText("准备本机打印快照，不会提交网站。"+(images.isEmpty()?"":"\n正在加载图片：0 / "+images.size()));
        AlertDialog dialog=new AlertDialog.Builder(host).setTitle("打印 / 保存 PDF").setView(status).setNegativeButton("取消",null).setPositiveButton("打开系统打印",null).create();int[] pending={images.size()},failed={0};
        dialog.setOnShowListener(v->{android.widget.Button start=dialog.getButton(-1);start.setEnabled(pending[0]==0);start.setOnClickListener(w->{try{manager.print(title.trim().isEmpty()?"仓库·星屿投稿":title,new SnapshotAdapter(host,title,body,images.values()),new PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).setColorMode(PrintAttributes.COLOR_MODE_COLOR).setMinMargins(new PrintAttributes.Margins(500,500,500,500)).build());dialog.dismiss();}catch(RuntimeException e){host.toast("无法打开系统打印，请检查设备打印服务");}});
            for(Map.Entry<String,Picture> entry:images.entrySet()){host.pictures().load(entry.getKey(),bitmap->{if(!dialog.isShowing()||host.isFinishing())return;if(bitmap==null)failed[0]++;else entry.getValue().bitmap=bitmap;pending[0]--;status.setText("图片加载完成："+(images.size()-pending[0])+" / "+images.size()+(failed[0]>0?"\n有 "+failed[0]+" 张图片加载失败；打印会保留占位提示，可取消后检查网络再试。":"")+(pending[0]==0?"\n选择系统打印机，或选择系统提供的「另存为 PDF」。":""));if(pending[0]==0)start.setEnabled(true);});}
        });dialog.show();
    }
    private static final class Picture extends Drawable {
        Bitmap bitmap;private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        Picture(){setBounds(0,0,480,100);}
        void width(int width){int height=bitmap==null?70:Math.max(1,(int)Math.min(Integer.MAX_VALUE/4,(long)width*bitmap.getHeight()/Math.max(1,bitmap.getWidth())));setBounds(0,0,width,height);}
        @Override public void draw(Canvas canvas){if(bitmap==null){paint.setColor(0xffeeeeee);canvas.drawRect(getBounds(),paint);paint.setColor(0xff777777);paint.setTextSize(11);canvas.drawText("图片未能加载",8,30,paint);}else canvas.drawBitmap(bitmap,null,getBounds(),paint);}
        @Override public void setAlpha(int alpha){paint.setAlpha(alpha);}@Override public void setColorFilter(ColorFilter value){paint.setColorFilter(value);}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    private static final class SnapshotAdapter extends PrintDocumentAdapter {
        private final Context context;private final String title;private final Spanned body;private final Collection<Picture> images;private PrintedPdfDocument pdf;private PrintAttributes attributes;private LinearLayout view;private int pages,pageHeight;private Rect bounds;
        SnapshotAdapter(Context context,String title,Spanned body,Collection<Picture> images){this.context=context;this.title=title;this.body=body;this.images=images;}
        private TextView text(String value,int size,boolean bold){TextView text=new TextView(context);text.setTextColor(Color.BLACK);text.setTextSize(TypedValue.COMPLEX_UNIT_PX,size);text.setText(value);text.setTypeface(null,bold?Typeface.BOLD:Typeface.NORMAL);text.setLineSpacing(3,1.05f);return text;}
        @Override public void onLayout(PrintAttributes oldAttributes,PrintAttributes newAttributes,CancellationSignal cancellation,LayoutResultCallback callback,Bundle extras){
            if(cancellation.isCanceled()){callback.onLayoutCancelled();return;}try{if(pdf!=null)pdf.close();attributes=newAttributes;pdf=new PrintedPdfDocument(context,newAttributes);bounds=pdf.getPageContentRect();if(bounds.width()<100||bounds.height()<100)throw new IllegalArgumentException("打印纸张或页边距过小");pageHeight=bounds.height();view=new LinearLayout(context);view.setOrientation(LinearLayout.VERTICAL);view.setBackgroundColor(Color.WHITE);view.addView(text(title,18,true),new LinearLayout.LayoutParams(-1,-2));TextView content=text("",12,false);for(Picture image:images)image.width(Math.max(1,bounds.width()-4));content.setText(body);view.addView(content,new LinearLayout.LayoutParams(-1,-2));view.measure(View.MeasureSpec.makeMeasureSpec(bounds.width(),View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));view.layout(0,0,bounds.width(),view.getMeasuredHeight());pages=NativePrintPagination.count(view.getMeasuredHeight(),pageHeight);pdf.close();pdf=null;callback.onLayoutFinished(new PrintDocumentInfo.Builder("星屿投稿.pdf").setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(pages).build(),!newAttributes.equals(oldAttributes));}catch(Exception e){callback.onLayoutFailed(e.getMessage()==null?"无法排版打印快照":e.getMessage());}
        }
        @Override public void onWrite(PageRange[] requested,ParcelFileDescriptor destination,CancellationSignal cancellation,WriteResultCallback callback){
            if(attributes==null||view==null){callback.onWriteFailed("请重新打开打印预览");return;}if(pdf!=null)pdf.close();pdf=new PrintedPdfDocument(context,attributes);ArrayList<PageRange> written=new ArrayList<>();int[][] ranges=new int[requested.length][2];for(int i=0;i<requested.length;i++){ranges[i][0]=requested[i].getStart();ranges[i][1]=requested[i].getEnd();}
            try{for(int index=0;index<pages;index++){if(cancellation.isCanceled()){callback.onWriteCancelled();return;}if(!NativePrintPagination.included(index,ranges))continue;android.graphics.pdf.PdfDocument.Page page=pdf.startPage(index);Canvas canvas=page.getCanvas();canvas.save();canvas.clipRect(bounds);canvas.translate(bounds.left,bounds.top-index*pageHeight);view.draw(canvas);canvas.restore();pdf.finishPage(page);written.add(new PageRange(index,index));}try(FileOutputStream out=new FileOutputStream(destination.getFileDescriptor())){pdf.writeTo(out);}callback.onWriteFinished(written.toArray(new PageRange[0]));}catch(Exception e){callback.onWriteFailed("写入PDF失败，请重新选择打印目标");}finally{if(pdf!=null){pdf.close();pdf=null;}}
        }
        @Override public void onFinish(){if(pdf!=null){pdf.close();pdf=null;}view=null;}
    }
}
