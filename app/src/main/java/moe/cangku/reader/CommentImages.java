package moe.cangku.reader;

import android.app.Activity;
import android.content.*;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.widget.*;
import java.io.*;
import java.util.*;
import java.util.function.*;
import org.json.JSONObject;

/** Original files go only to the website image host; uploading does not publish a comment. */
final class CommentImages {
    static final int REQUEST=6303;
    private final MainActivity host;private Session pending;
    CommentImages(MainActivity h){host=h;}
    static final class Session {
        final EditText input;final TextView status;final BooleanSupplier valid;final Runnable changed;
        boolean busy;String text="";int a,b;final long owner;final long version;
        Session(EditText i,TextView s,BooleanSupplier v,Runnable c,long uid,long apiVersion){input=i;status=s;valid=v;changed=c;owner=uid;version=apiVersion;}
    }
    Session session(EditText input,TextView status,BooleanSupplier valid,Runnable changed){return new Session(input,status,valid,changed,host.account().optLong("id"),host.client().sessionVersion());}
    private boolean valid(Session s){return s.valid.getAsBoolean()&&host.account()!=null&&host.account().optLong("id")==s.owner&&host.client().sessionVersion()==s.version;}
    void pick(Session s){
        if(!valid(s)||s.busy)return;pending=s;s.busy=true;s.status.setText("选择一张1MB以内的 JPG / PNG / GIF / WebP 图片");s.changed.run();
        Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);
        try{host.startActivityForResult(pick,REQUEST);}catch(ActivityNotFoundException e){pending=null;reset(s,"设备没有图片选择器");}
    }
    void cancel(Session s){if(pending==s)pending=null;}
    boolean onFileResult(int request,int result,Intent data){
        if(request!=REQUEST)return false;Session s=pending;pending=null;if(s==null||!valid(s))return true;
        if(result!=Activity.RESULT_OK||data==null||data.getData()==null){reset(s,"已取消选图，原评论内容保留");return true;}
        Uri uri=data.getData();if(!"content".equalsIgnoreCase(uri.getScheme())){reset(s,"请选择系统相册或文件选择器中的图片");return true;}
        s.text=s.input.getText().toString();s.a=Math.max(0,s.input.getSelectionStart());s.b=Math.max(s.a,s.input.getSelectionEnd());s.input.setEnabled(false);s.status.setText("正在上传至官网图床…");s.changed.run();
        host.task(()->{if(host.client().sessionVersion()!=s.version)throw new IOException("账号已切换，已取消上传");byte[] bytes=read(uri);if(host.client().sessionVersion()!=s.version)throw new IOException("账号已切换，已取消上传");return host.client().upload("upload/image","image",bytes,Collections.emptyMap(),CommentImageRules.mediaType(bytes),s.version);},response->{
            if(!valid(s))return;JSONObject dataObject=response.optJSONObject("data");String url=dataObject==null?response.optString("url",response.optString("link")):dataObject.optString("url",dataObject.optString("link"));url=CommentMedia.imageUrl(url);if(url.isEmpty()){reset(s,"上传成功，但网站没有返回有效图片地址；原评论已保留");return;}
            String inserted="\n"+url+"\n";int a=s.text.equals(s.input.getText().toString())?s.a:Math.max(0,s.input.getSelectionStart()),b=s.text.equals(s.input.getText().toString())?s.b:Math.max(a,s.input.getSelectionEnd());
            if(s.input.length()-(b-a)+inserted.length()>5000){reset(s,"图片已上传，但评论超过5000字。请删减文字后重试；已上传地址可通过长按此提示复制");s.status.setOnLongClickListener(v->{host.copyText(CommentMedia.imageUrl(dataObject==null?response.optString("url",response.optString("link")):dataObject.optString("url",dataObject.optString("link"))));return true;});return;}
            s.input.getText().replace(a,b,inserted);s.input.setSelection(a+inserted.length());reset(s,"图片已上传并加入预览，点击「发布」才会发送评论");
        },error->{if(valid(s))reset(s,error+"，原评论内容保留，可重新上传");});return true;
    }
    private byte[] read(Uri uri)throws Exception{
        byte[] bytes;try(InputStream in=host.getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException("无法读取图片");byte[] chunk=new byte[8192];int n;while((n=in.read(chunk))!=-1){if(out.size()+n>CommentImageRules.MAX_BYTES)throw new IOException("图片超过1MB，请选择1MB以内的图片");out.write(chunk,0,n);}bytes=out.toByteArray();}
        if(CommentImageRules.mediaType(bytes).isEmpty())throw new IOException("仅支持有效的 JPG / PNG / GIF / WebP 图片");
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);if(bounds.outWidth<=0||bounds.outHeight<=0||(long)bounds.outWidth*bounds.outHeight>100000000L)throw new IOException("图片无法解码或尺寸过大");return bytes;
    }
    private void reset(Session s,String message){s.busy=false;s.input.setEnabled(true);s.status.setText(message);s.changed.run();}
}
