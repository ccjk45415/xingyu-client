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
    interface DrawableResult { void ready(android.graphics.drawable.Drawable drawable); }
    private volatile boolean closed;
    private final LruCache<String,byte[]> animations=new LruCache<String,byte[]>(4*1024*1024){protected int sizeOf(String key,byte[] data){return data.length;}};
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
        if(closed)return;
        if(!UrlPolicy.isImage(url)){ui.post(()->result.ready(null));return;}
        Bitmap hit=cache.get(url);if(hit!=null){ui.post(()->result.ready(hit));return;}
        submit(()->{
            Bitmap bitmap=null;
            try{
                byte[] data=fetch(url);
                if(data!=null){BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(data,0,data.length,bounds);
                    if(bounds.outWidth>0&&bounds.outHeight>0){BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.RGB_565;options.inSampleSize=1;while(bounds.outWidth/options.inSampleSize>2048||bounds.outHeight/options.inSampleSize>4096)options.inSampleSize*=2;bitmap=BitmapFactory.decodeByteArray(data,0,data.length,options);if(bitmap!=null)cache.put(url,bitmap);}}
            }catch(Exception|OutOfMemoryError ignored){}
            Bitmap completed=bitmap;ui.post(()->{if(!closed)result.ready(completed);});
        });
    }
    private byte[] fetch(String url)throws IOException{
        String current=url;for(int redirect=0;redirect<4;redirect++){
            if(!UrlPolicy.isImage(current)||closed)return null;HttpURLConnection c=(HttpURLConnection)new URL(current).openConnection();c.setConnectTimeout(12000);c.setReadTimeout(18000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent",ApiClient.UA);c.setRequestProperty("Referer",UrlPolicy.ORIGIN+"/");
            try{int status=c.getResponseCode();if(status>=300&&status<400){String next=c.getHeaderField("Location");if(next==null)return null;current=new URL(new URL(current),next).toString();continue;}if(status!=200||c.getContentLengthLong()>10*1024*1024)return null;try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] chunk=new byte[8192];int n;while((n=in.read(chunk))!=-1){if(out.size()+n>10*1024*1024)throw new IOException("image size");out.write(chunk,0,n);}return out.toByteArray();}}finally{c.disconnect();}
        }return null;
    }
    /** Per-view drawable instances: animated emoji never share mutable callbacks across comments. */
    void animatedEmoji(String url,DrawableResult result){
        if(closed||!CommentMedia.emojiImage(url)||!url.endsWith(".gif"))return;
        submit(()->{android.graphics.drawable.Drawable drawable=null;try{byte[] data=animations.get(url);if(data==null){data=fetch(url);if(data!=null&&data.length<=1024*1024)animations.put(url,data);}if(data!=null){if(android.os.Build.VERSION.SDK_INT>=28)drawable=ImageDecoder.decodeDrawable(ImageDecoder.createSource(java.nio.ByteBuffer.wrap(data)));else{android.graphics.Movie movie=android.graphics.Movie.decodeByteArray(data,0,data.length);if(movie!=null)drawable=new MovieDrawable(movie);}}}catch(Exception|OutOfMemoryError ignored){}android.graphics.drawable.Drawable complete=drawable;ui.post(()->{if(!closed)result.ready(complete);});});
    }
    private static final class MovieDrawable extends android.graphics.drawable.Drawable implements android.graphics.drawable.Animatable,Runnable{
        final android.graphics.Movie movie;boolean running;long started;
        MovieDrawable(android.graphics.Movie m){movie=m;}
        @Override public void draw(Canvas c){if(running)movie.setTime((int)((android.os.SystemClock.uptimeMillis()-started)%Math.max(1,movie.duration()>0?movie.duration():1000)));c.save();c.translate(getBounds().left,getBounds().top);c.scale(getBounds().width()/(float)Math.max(1,movie.width()),getBounds().height()/(float)Math.max(1,movie.height()));movie.draw(c,0,0);c.restore();if(running)scheduleSelf(this,android.os.SystemClock.uptimeMillis()+33);}
        @Override public void start(){if(running)return;running=true;started=android.os.SystemClock.uptimeMillis();invalidateSelf();}@Override public void stop(){running=false;unscheduleSelf(this);}@Override public boolean isRunning(){return running;}@Override public void run(){invalidateSelf();}@Override public void setAlpha(int a){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    private void submit(Runnable work){if(closed)return;try{pool.execute(work);}catch(RejectedExecutionException ignored){/* Activity was destroyed between validation and dispatch. */}}
    void close(){closed=true;pool.shutdownNow();cache.evictAll();animations.evictAll();}
}
