package moe.cangku.reader;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.util.LruCache;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.function.*;

/** Private authenticated image transport. No token-bearing URLs, website uploads, or image files on disk. */
final class MessageImages {
    private final MainActivity host;
    private boolean busy;
    private Pick pending;
    private final Map<String,List<Consumer<Bitmap>>> waiting=new HashMap<>();
    private static final class Prepared {byte[] bytes;Bitmap preview;Prepared(byte[] b,Bitmap p){bytes=b;preview=p;}}
    private final LruCache<String,Bitmap> cache=new LruCache<String,Bitmap>(16*1024*1024){protected int sizeOf(String k,Bitmap b){return b.getAllocationByteCount();}};
    private static final class Pick {long owner;String token,scope,target,nonce=UUID.randomUUID().toString();BooleanSupplier valid;Consumer<JSONObject> done;}
    MessageImages(MainActivity h){host=h;}
    void leavePage(){pending=null;busy=false;waiting.clear();}
    void clear(){leavePage();cache.evictAll();}
    void pick(String scope,String target,String token,BooleanSupplier valid,Consumer<JSONObject> done){
        if(busy){host.toast("正在处理上一张图片");return;}Pick p=new Pick();p.owner=host.account().optLong("id");p.scope=scope;p.target=target;p.token=token;p.valid=valid;p.done=done;pending=p;busy=true;
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);
        try{host.startActivityForResult(intent,6302);}catch(ActivityNotFoundException e){clear();host.toast("设备没有图片选择器");}
    }
    boolean onFileResult(int request,int result,Intent data){
        if(request!=6302)return false;Pick p=pending;pending=null;if(p==null||result!=Activity.RESULT_OK||data==null||data.getData()==null){busy=false;return true;}Uri uri=data.getData();
        host.task(()->prepare(uri),prepared->{busy=false;if(!valid(p))return;byte[] bytes=prepared.bytes;Bitmap bitmap=prepared.preview;ImageView preview=new ImageView(host);preview.setImageBitmap(bitmap);preview.setScaleType(ImageView.ScaleType.FIT_CENTER);LinearLayout wrap=host.design().column();host.design().pad(wrap,18,12,18,12);wrap.addView(preview,new LinearLayout.LayoutParams(-1,host.design().dp(230)));wrap.addView(host.design().text("压缩后 "+bytes.length/1024+"KB · JPEG静态图片 · 去除EXIF信息\n发出后图片保留7天；未发送附件1小时后清理。",12,host.design().muted,false));
            new AlertDialog.Builder(host).setTitle("添加这张图片？").setView(wrap).setNegativeButton("取消",null).setPositiveButton("添加",(d,w)->{if(!valid(p))return;busy=true;host.task(()->upload(p,bytes),image->{busy=false;if(valid(p)){cache.put(p.owner+"/"+image.optString("id"),bitmap);p.done.accept(image);}},error->{busy=false;host.toast(error);});}).show();
        },error->{busy=false;host.toast(error);});return true;
    }
    private boolean valid(Pick p){return host.account()!=null&&host.account().optLong("id")==p.owner&&p.valid.getAsBoolean();}
    private Prepared prepare(Uri uri)throws Exception{
        byte[] data;try(InputStream in=host.getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException("无法读取图片");byte[] buffer=new byte[8192];int n;while((n=in.read(buffer))!=-1){if(out.size()+n>20*1024*1024)throw new IOException("请选择20MB以内的图片");out.write(buffer,0,n);}data=out.toByteArray();}
        try{
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(data,0,data.length,bounds);if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IOException("图片格式不支持");BitmapFactory.Options opts=new BitmapFactory.Options();opts.inSampleSize=1;while(bounds.outWidth/opts.inSampleSize>2560||bounds.outHeight/opts.inSampleSize>2560)opts.inSampleSize*=2;Bitmap image=BitmapFactory.decodeByteArray(data,0,data.length,opts);if(image==null)throw new IOException("无法解码图片");
            Matrix rotate=new Matrix();try{int orientation=new android.media.ExifInterface(new ByteArrayInputStream(data)).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION,1);switch(orientation){case 2:rotate.setScale(-1,1);break;case 3:rotate.setRotate(180);break;case 4:rotate.setScale(1,-1);break;case 5:rotate.setRotate(90);rotate.postScale(-1,1);break;case 6:rotate.setRotate(90);break;case 7:rotate.setRotate(270);rotate.postScale(-1,1);break;case 8:rotate.setRotate(270);}}
            catch(IOException ignored){}if(!rotate.isIdentity()){Bitmap corrected=Bitmap.createBitmap(image,0,0,image.getWidth(),image.getHeight(),rotate,true);if(corrected!=image)image.recycle();image=corrected;}
            int edge=1280;for(int attempt=0;attempt<5;attempt++,edge=(int)(edge*.72)){
                float scale=Math.min(1,edge/(float)Math.max(image.getWidth(),image.getHeight()));Bitmap canvasImage=Bitmap.createBitmap(Math.max(1,(int)(image.getWidth()*scale)),Math.max(1,(int)(image.getHeight()*scale)),Bitmap.Config.RGB_565);Canvas canvas=new Canvas(canvasImage);canvas.drawColor(Color.WHITE);canvas.drawBitmap(image,null,new Rect(0,0,canvasImage.getWidth(),canvasImage.getHeight()),new Paint(3));
                for(int quality:new int[]{85,70,55}){ByteArrayOutputStream out=new ByteArrayOutputStream();canvasImage.compress(Bitmap.CompressFormat.JPEG,quality,out);if(out.size()<=192*1024){byte[] bytes=out.toByteArray();float shrink=Math.min(1,512f/Math.max(canvasImage.getWidth(),canvasImage.getHeight()));Bitmap thumbnail=Bitmap.createScaledBitmap(canvasImage,Math.max(1,(int)(canvasImage.getWidth()*shrink)),Math.max(1,(int)(canvasImage.getHeight()*shrink)),true);if(thumbnail!=canvasImage)canvasImage.recycle();image.recycle();return new Prepared(bytes,thumbnail);}}canvasImage.recycle();
            }image.recycle();throw new IOException("图片压缩后仍过大，请选择较小的图片");
        }catch(OutOfMemoryError e){throw new IOException("图片尺寸过大，请选择较小的图片");}
    }
    private JSONObject upload(Pick p,byte[] bytes)throws Exception{
        HttpURLConnection c=connection("/media/v1/images?scope="+p.scope+"&target="+p.target,p.token);c.setRequestMethod("POST");c.setRequestProperty("Content-Type","image/jpeg");c.setRequestProperty("X-Upload-ID",p.nonce);c.setDoOutput(true);c.setFixedLengthStreamingMode(bytes.length);
        try{try(OutputStream out=c.getOutputStream()){out.write(bytes);}int status=c.getResponseCode();JSONObject response=new JSONObject(ApiClient.read(status>=400?c.getErrorStream():c.getInputStream(),8192));if(status!=200)throw new IOException(response.optString("error","图片上传失败"));return response.getJSONObject("image");}finally{c.disconnect();}
    }
    private HttpURLConnection connection(String path,String token)throws Exception{HttpURLConnection c=(HttpURLConnection)new URL(ServiceEndpoint.origin()+path).openConnection();c.setConnectTimeout(12000);c.setReadTimeout(20000);c.setInstanceFollowRedirects(false);c.setUseCaches(false);c.setRequestProperty("Authorization","Bearer "+token);c.setRequestProperty("User-Agent","XingyuMedia/1");return c;}
    void image(LinearLayout parent,JSONObject meta,String token){
        String id=meta.optString("id");if(!id.matches("[a-f0-9]{32}"))return;long owner=host.account()==null?0:host.account().optLong("id");String key=owner+"/"+id;Ui u=host.design();LinearLayout box=u.column();ImageView view=new ImageView(host);view.setScaleType(ImageView.ScaleType.FIT_CENTER);view.setBackground(u.round(u.soft,14));view.setTag(key);view.setContentDescription("聊天图片，点击查看大图");box.addView(view,new LinearLayout.LayoutParams(u.dp(205),u.dp(160)));TextView label=u.text("加载图片…",11,u.muted,false);box.addView(label);parent.addView(box);
        Consumer<Bitmap> show=bitmap->{if(host.account()==null||host.account().optLong("id")!=owner||!key.equals(view.getTag()))return;if(bitmap==null){label.setText("图片已过期或暂时无法加载");return;}view.setImageBitmap(bitmap);label.setText("点击查看大图 · 长按识别二维码");view.setOnLongClickListener(v->{host.recognizeQr(bitmap);return true;});u.click(view,()->{ImageView full=new ImageView(host);full.setImageBitmap(bitmap);full.setAdjustViewBounds(true);full.setScaleType(ImageView.ScaleType.FIT_CENTER);full.setOnLongClickListener(v->{host.recognizeQr(bitmap);return true;});new AlertDialog.Builder(host).setTitle("查看图片 · 长按识别二维码").setView(full).setPositiveButton("关闭",null).show();});};Bitmap hit=cache.get(key);if(hit!=null){show.accept(hit);return;}
        Runnable load=()->load(key,id,token,show);u.click(view,load);load.run();
    }
    private void load(String key,String id,String token,Consumer<Bitmap> done){
        if(waiting.containsKey(key)){waiting.get(key).add(done);return;}List<Consumer<Bitmap>> group=new ArrayList<>();group.add(done);waiting.put(key,group);
        Consumer<Bitmap> finish=bitmap->{if(waiting.get(key)!=group)return;waiting.remove(key);if(bitmap!=null)cache.put(key,bitmap);for(Consumer<Bitmap> callback:group)callback.accept(bitmap);};
        host.task(()->{HttpURLConnection c=connection("/media/v1/images/"+id,token);try{if(c.getResponseCode()!=200)return null;ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>262144)throw new IOException("图片过大");out.write(b,0,n);}}byte[] bytes=out.toByteArray();BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);if(bounds.outWidth<1||bounds.outHeight<1||bounds.outWidth>1600||bounds.outHeight>1600)return null;BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.RGB_565;options.inSampleSize=1;return BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);}catch(OutOfMemoryError e){throw new IOException("图片内存不足，请稍后重试");}finally{c.disconnect();}},finish::accept,error->finish.accept(null));
    }
}
