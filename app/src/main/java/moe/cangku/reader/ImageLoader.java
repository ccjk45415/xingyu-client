package moe.cangku.reader;

import android.graphics.*;
import android.os.*;
import android.util.LruCache;
import android.widget.ImageView;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;

final class ImageLoader {
    interface Result { void ready(Bitmap bitmap); }
    private final ExecutorService pool=Executors.newFixedThreadPool(4);
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final LruCache<String,Bitmap> cache=new LruCache<String,Bitmap>((int)Math.min(Runtime.getRuntime().maxMemory()/12,32*1024*1024)){
        protected int sizeOf(String key,Bitmap bitmap){return bitmap.getAllocationByteCount();}
    };
    void into(String url,ImageView view){
        view.setTag(url);view.setContentDescription("内容封面");
        load(url,b->{if(url.equals(view.getTag())&&b!=null)view.setImageBitmap(b);});
    }
    void load(String url,Result result){
        if(!UrlPolicy.isImage(url)){ui.post(()->result.ready(null));return;}
        Bitmap hit=cache.get(url);if(hit!=null){ui.post(()->result.ready(hit));return;}
        pool.execute(()->{
            Bitmap bitmap=null;
            try{
                String current=url;
                for(int redirect=0;redirect<4;redirect++){
                    if(!UrlPolicy.isImage(current))break;
                    HttpURLConnection c=(HttpURLConnection)new URL(current).openConnection();
                    c.setConnectTimeout(12000);c.setReadTimeout(18000);c.setInstanceFollowRedirects(false);
                    c.setRequestProperty("User-Agent",ApiClient.UA);c.setRequestProperty("Referer",UrlPolicy.ORIGIN+"/");
                    try{
                        int status=c.getResponseCode();
                        if(status>=300&&status<400){String next=c.getHeaderField("Location");if(next==null)break;current=new URL(new URL(current),next).toString();continue;}
                        if(status!=200||c.getContentLengthLong()>10*1024*1024)break;
                        ByteArrayOutputStream out=new ByteArrayOutputStream();
                        try(InputStream in=c.getInputStream()){
                            byte[] chunk=new byte[8192];int size=0,n;
                            while((n=in.read(chunk))!=-1){size+=n;if(size>10*1024*1024)throw new IOException("image size");out.write(chunk,0,n);}
                        }
                        byte[] data=out.toByteArray();BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(data,0,data.length,bounds);
                        if(bounds.outWidth<=0||bounds.outHeight<=0)break;
                        BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.RGB_565;
                        options.inSampleSize=1;
                        while(bounds.outWidth/options.inSampleSize>2048||bounds.outHeight/options.inSampleSize>4096){options.inSampleSize*=2;}
                        bitmap=BitmapFactory.decodeByteArray(data,0,data.length,options);if(bitmap!=null)cache.put(url,bitmap);break;
                    }finally{c.disconnect();}
                }
            }catch(Exception|OutOfMemoryError ignored){}
            Bitmap completed=bitmap;ui.post(()->result.ready(completed));
        });
    }
    void close(){pool.shutdownNow();cache.evictAll();}
}
