package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.os.*;
import android.text.*;
import android.text.style.AbsoluteSizeSpan;
import android.view.*;
import android.view.accessibility.*;
import android.widget.*;
import android.graphics.Bitmap;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;

/** Optional isolated-device test. Its APK deliberately has no Internet permission. */
public final class EditorInstrument extends Instrumentation {
    int checks;MainActivity activity;Throwable error;
    void check(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    View tool(View v,String name){if(name.equals(String.valueOf(v.getContentDescription())))return v;if(v instanceof ViewGroup){ViewGroup group=(ViewGroup)v;for(int i=0;i<group.getChildCount();i++){View hit=tool(group.getChildAt(i),name);if(hit!=null)return hit;}}return null;}
    void main(Runnable work){runOnMainSync(()->{try{work.run();}catch(Throwable e){error=e;}});if(error!=null)throw new AssertionError(error);}
    public void onCreate(Bundle args){super.onCreate(args);start();}
    public void onStart(){
        Bundle result=new Bundle();
        try{
            getTargetContext().getSharedPreferences("authoringDrafts",0).edit().clear().commit();
            activity=(MainActivity)startActivitySync(new Intent().setClassName(getTargetContext(),MainActivity.class.getName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitForIdleSync();
            main(()->{try{
                Field f=MainActivity.class.getDeclaredField("user");f.setAccessible(true);f.set(activity,new JSONObject().put("id",777001).put("nickname","星屿工具测试").put("permissions",new JSONArray()));activity.navigateNative("editor","新建投稿",0);
            }catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
            main(()->{try{
                View root=activity.getWindow().getDecorView();String[] labels={"加粗","斜体","下划线","删除线","1级标题","2级标题","3级标题","段落","插入换行","无序列表","有序列表","引用","插入链接","上传正文图片","插入网络图片","下载卡片","插入表格","行内代码","插入代码块","水平分隔线","正文字号","文字颜色","文字背景色","左对齐","居中","右对齐","两端对齐","上标","下标","增加缩进","减少缩进","清除选区格式","HTML特殊字符","插入当前日期","查找与替换","减小编辑字号","增大编辑字号","撤销","重做"};
                for(String label:labels){View button=tool(root,label);check(button!=null,"Missing tool "+label);check(button.getWidth()>0&&button.getHeight()>0,"Unmeasured tool "+label);check(button.getLeft()>=0&&button.getRight()<=((View)button.getParent()).getWidth(),"Overflow tool "+label);}
                Object author=field(activity,"authoring");EditText input=(EditText)field(author,"contentInput");input.setText("星屿");input.setSelection(0,2);tool(root,"加粗").performClick();check(input.getText().toString().equals("<p><strong>星屿</strong></p>"),"selection wrapping");tool(root,"撤销").performClick();check(input.getText().toString().equals("星屿"),"undo text and plain mode");tool(root,"重做").performClick();check(input.getText().toString().contains("<strong>"),"redo");
                String before=input.getText().toString();float old=input.getTextSize();tool(root,"增大编辑字号").performClick();check(input.getTextSize()>old&&input.getText().toString().equals(before),"zoom only affects editor");
                Spanned rendered=Html.fromHtml(EditorStyles.markFontSizes("<span style='font-size:24px'>字号测试</span>"),Html.FROM_HTML_MODE_COMPACT,null,new NativeEditorStyles(1f));AbsoluteSizeSpan[] spans=rendered.getSpans(0,rendered.length(),AbsoluteSizeSpan.class);check(spans.length==1&&spans[0].getSize()==24,"actual Android font span");
                tool(root,"正文字号").performClick();
            }catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
            AccessibilityNodeInfo node=getUiAutomation().getRootInActiveWindow();List<AccessibilityNodeInfo> choices=node.findAccessibilityNodeInfosByText("24 px");check(!choices.isEmpty(),"font chooser visible");check(choices.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK),"choose 24px");waitForIdleSync();
            main(()->{try{Object author=field(activity,"authoring");EditText input=(EditText)field(author,"contentInput");check(input.getText().toString().contains("font-size:24px"),"font toolbar writes CSS");((ScrollView)field(activity,"scroll")).scrollTo(0,0);}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
            Bitmap shot=getUiAutomation().takeScreenshot();File image=new File(getTargetContext().getExternalFilesDir(null),"editor-toolbar.png");try(FileOutputStream stream=new FileOutputStream(image)){shot.compress(Bitmap.CompressFormat.PNG,100,stream);}shot.recycle();
            result.putString("stream","EDITOR_DEVICE_PASS "+checks+" checks; synthetic data; no Internet permission\n");finish(Activity.RESULT_OK,result);
        }catch(Throwable e){result.putString("stream","EDITOR_DEVICE_FAIL "+e.getClass().getSimpleName()+": "+e.getMessage()+"\n");finish(Activity.RESULT_CANCELED,result);}
        finally{if(activity!=null)runOnMainSync(()->activity.finish());}
    }
}
