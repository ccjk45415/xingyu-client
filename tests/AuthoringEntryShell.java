package moe.cangku.reader;

import android.content.*;
import android.os.Looper;
import android.widget.*;
import org.json.*;
import java.lang.reflect.*;
import java.util.*;

/** No-install probe of the real editor form; no account, network, or preference writes. */
public final class AuthoringEntryShell {
    static final class Host extends MainActivity {
        boolean failFont;
        android.content.res.Resources resources;android.content.res.Resources.Theme theme;
        final Map<String,Map<String,Object>> preferences=new HashMap<>();
        void base(Context c){attachBaseContext(c);}
        @Override public android.content.res.Resources getResources(){return resources==null?super.getResources():resources;}
        @Override public void setTheme(int id){theme=getResources().newTheme();theme.applyStyle(id,true);}
        @Override public android.content.res.Resources.Theme getTheme(){return theme;}
        @Override public Object getSystemService(String name){return getBaseContext().getSystemService(name);}
        @Override public SharedPreferences getSharedPreferences(String name,int mode){
            Map<String,Object> values=preferences.computeIfAbsent(name,n->new HashMap<>());
            return (SharedPreferences)Proxy.newProxyInstance(SharedPreferences.class.getClassLoader(),new Class[]{SharedPreferences.class},(p,m,a)->{
                if(m.getName().equals("getAll"))return new HashMap<>(values);
                if(m.getName().equals("contains"))return values.containsKey(a[0]);
                if(m.getName().startsWith("get")){if(failFont&&String.valueOf(a[0]).startsWith("editor.font.")){failFont=false;throw new IllegalStateException("private-draft-marker");}return values.getOrDefault(a[0],a[1]);}
                if(m.getName().equals("edit")){Map<String,Object> pending=new HashMap<>();return Proxy.newProxyInstance(SharedPreferences.Editor.class.getClassLoader(),new Class[]{SharedPreferences.Editor.class},(e,em,ea)->{
                    if(em.getName().startsWith("put")){pending.put((String)ea[0],ea[1]);return e;}
                    if(em.getName().equals("remove")){values.remove(ea[0]);return e;}
                    if(em.getName().equals("apply")||em.getName().equals("commit")){values.putAll(pending);return em.getName().equals("commit")?true:null;}
                    throw new AssertionError(em.getName());});}
                throw new AssertionError("Unexpected preference write: "+m.getName());
            });
        }
    }
    static void put(Object o,String n,Object v)throws Exception{Field f=MainActivity.class.getDeclaredField(n);f.setAccessible(true);f.set(o,v);}
    public static void main(String[] args)throws Exception{
        try { run(args); } catch(Throwable error){error.printStackTrace(System.out);System.exit(1);}
    }
    static void run(String[] args)throws Exception{
        System.out.println("PROBE_STARTED");
        Looper.prepareMainLooper();
        Class<?> thread=Class.forName("android.app.ActivityThread");Constructor<?> ctor=thread.getDeclaredConstructor();ctor.setAccessible(true);Object at=ctor.newInstance();
        System.out.println("THREAD_READY");
        Method context=thread.getDeclaredMethod("getSystemContext");context.setAccessible(true);
        Context base=(Context)context.invoke(at);System.out.println("CONTEXT_READY");
        final ContentResolver[] resolvers=new ContentResolver[1];
        android.app.Application application=new android.app.Application(){@Override public ContentResolver getContentResolver(){return resolvers[0];}};Method attach=android.app.Application.class.getDeclaredMethod("attach",Context.class);attach.setAccessible(true);attach.invoke(application,base);Field app=thread.getDeclaredField("mInitialApplication");app.setAccessible(true);app.set(at,application);Field current=thread.getDeclaredField("sCurrentActivityThread");current.setAccessible(true);current.set(null,at);
        resolvers[0]=base.getContentResolver();
        Class<?> provider=Class.forName("android.content.IContentProvider");Object mock=Proxy.newProxyInstance(provider.getClassLoader(),new Class[]{provider},(p,m,a)->null);
        for(String name:new String[]{"Config","System","Secure","Global"}){Class<?> settings=Class.forName("android.provider.Settings$"+name);Field holder=settings.getDeclaredField("sProviderHolder");holder.setAccessible(true);Object h=holder.get(null);Field cp=h.getClass().getDeclaredField("mContentProvider");cp.setAccessible(true);cp.set(h,mock);}
        android.graphics.Typeface.class.getMethod("loadPreinstalledSystemFontMap").invoke(null);
        Host host=new Host();System.out.println("HOST_READY");host.base(base);System.out.println("BASE_READY");
        android.content.res.AssetManager assets=android.content.res.AssetManager.class.getDeclaredConstructor().newInstance();Method add=android.content.res.AssetManager.class.getDeclaredMethod("addAssetPath",String.class);add.setAccessible(true);if((Integer)add.invoke(assets,args[0])==0)throw new AssertionError("APK resource load failed");
        host.resources=new android.content.res.Resources(assets,base.getResources().getDisplayMetrics(),base.getResources().getConfiguration());host.setTheme(android.R.style.Theme_Material_Light_NoActionBar);System.out.println("THEME_READY");
        Ui ui=new Ui(host,false);put(host,"ui",ui);System.out.println("UI_READY");LinearLayout body=ui.column();put(host,"body",body);put(host,"top",ui.row());put(host,"images",new ImageLoader());System.out.println("LAYOUT_READY");
        put(host,"user",new JSONObject().put("id",777001).put("permissions",new JSONArray()));
        AuthoringScreens screens=new AuthoringScreens(host);System.out.println("ENTER_NEW_POST");screens.editor(0);System.out.println("FORM_READY");body.measure(android.view.View.MeasureSpec.makeMeasureSpec(ui.dp(360),1073741824),0);body.layout(0,0,body.getMeasuredWidth(),body.getMeasuredHeight());
        Field input=AuthoringScreens.class.getDeclaredField("richInput");input.setAccessible(true);if(input.get(screens)==null)throw new AssertionError("editor missing");
        android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(body.getWidth(),Math.min(body.getHeight(),ui.dp(900)),android.graphics.Bitmap.Config.ARGB_8888);
        body.draw(new android.graphics.Canvas(bitmap));bitmap.recycle();System.out.println("FORM_DRAW_PASS");
        NativeRichEditor editor=(NativeRichEditor)input.get(screens);draw(editor,ui);if(!editor.isVerticalScrollBarEnabled()||editor.isScrollbarFadingEnabled())throw new AssertionError("persistent scrollbar missing");
        StringBuilder longBody=new StringBuilder();for(int i=0;i<180;i++)longBody.append("<p>长正文滚动测试 ").append(i).append("</p>");
        editor.document(longBody.toString(),0,0,false);draw(editor,ui);if(!editor.canScrollVertically(1))throw new AssertionError("long body not scrollable");editor.scrollBy(0,ui.dp(100));if(editor.getScrollY()<=0)throw new AssertionError("scroll did not move");draw(editor,ui);
        editor.document(longBody.toString(),0,0,true);draw(editor,ui);if(!editor.source().equals(longBody.toString()))throw new AssertionError("HTML mode lost source");
        EditText ai=new AiPanelUi(host,ui).field(ui.column(),"作品素材",4);ai.setText(longBody.toString());draw(ai,ui);System.out.println("EMPTY_LONG_SOURCE_AI_DRAW_PASS");
        body.removeAllViews();host.failFont=true;screens.editor(0);
        if(input.get(screens)!=null)throw new AssertionError("fault not isolated");
        String report=host.getSharedPreferences("localCrashDiagnostics",0).getString("pending","");if(!report.contains("editor/native-editor")||!report.contains("IllegalStateException")||report.contains("private-draft-marker"))throw new AssertionError("diagnostic incomplete or leaked content");
        body.removeAllViews();screens.editor(0);if(input.get(screens)==null)throw new AssertionError("retry failed");
        for(int i=0;i<13;i++)CrashDiagnostics.record(host,new IllegalStateException("private-record-"+i),"test");
        String diagnostic=CrashDiagnostics.report(host);if(!diagnostic.contains("—— 异常 10 ——")||diagnostic.contains("—— 异常 11 ——")||diagnostic.contains("private-record-"))throw new AssertionError("history bounds or privacy");
        CrashDiagnostics.clear(host);if(!CrashDiagnostics.report(host).contains("异常 1"))throw new AssertionError("copy acknowledgement deleted history");
        CrashDiagnostics.clearHistory(host);if(!CrashDiagnostics.report(host).contains("暂无异常记录"))throw new AssertionError("history clear failed");System.out.println("DIAGNOSTICS_HISTORY_PASS");
        verifyDesign(host,ui,body);
        System.out.println("AUTHORING_ENTRY_PASS: create, layout, injected failure recovery, private report, retry");System.exit(0);
    }
    static void verifyDesign(Host host,Ui ui,LinearLayout body)throws Exception {
        String[][] labels={{"账号安全","安全"},{"诊断信息","诊断"},{"我的私信","私信"},{"通知","通知"},{"阅读与外观","外观"},{"检查更新","下载"},{"投稿与管理","投稿"},{"首页筛选","筛选"}};
        for(String[] pair:labels)if(!Ui.semantic(pair[0],"").equals(pair[1]))throw new AssertionError("misleading semantic icon: "+pair[0]);
        String[] names={"首页","分类","排行","聊天室","动态","我的","设置","安全","通知","私信","投稿","关注","收藏","历史","积分","诊断","外观","下载","上传","搜索","筛选","预览","复制","删除","保存","链接","发送","AI"};
        java.util.Set<Integer> hashes=new java.util.HashSet<>();int cell=ui.dp(76),width=cell*4,height=cell*((names.length+3)/4);
        android.graphics.Bitmap atlas=android.graphics.Bitmap.createBitmap(width,height,android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Canvas canvas=new android.graphics.Canvas(atlas);canvas.drawColor(ui.bg);
        for(int i=0;i<names.length;i++){
            android.graphics.Bitmap icon=android.graphics.Bitmap.createBitmap(ui.dp(24),ui.dp(24),android.graphics.Bitmap.Config.ARGB_8888);new Ui.Symbol(names[i],ui.accent,ui.dp(24)).draw(new android.graphics.Canvas(icon));int[] pixels=new int[icon.getWidth()*icon.getHeight()];icon.getPixels(pixels,0,icon.getWidth(),0,0,icon.getWidth(),icon.getHeight());hashes.add(java.util.Arrays.hashCode(pixels));
            int x=(i%4)*cell,y=(i/4)*cell;canvas.drawBitmap(icon,x+ui.dp(26),y+ui.dp(10),null);icon.recycle();android.graphics.Paint font=new android.graphics.Paint(3);font.setColor(ui.text);font.setTextSize(ui.dp(12));font.setTextAlign(android.graphics.Paint.Align.CENTER);canvas.drawText(names[i],x+cell/2f,y+ui.dp(56),font);
        }
        if(hashes.size()<26)throw new AssertionError("unrelated actions reuse the same icon");
        try(java.io.FileOutputStream out=new java.io.FileOutputStream("/data/local/tmp/xingyu-ui-icons.png")){atlas.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);}atlas.recycle();
        body.removeAllViews();Method settings=MainActivity.class.getDeclaredMethod("settingsHub");settings.setAccessible(true);settings.invoke(host);
        body.measure(android.view.View.MeasureSpec.makeMeasureSpec(ui.dp(360),1073741824),0);body.layout(0,0,body.getMeasuredWidth(),body.getMeasuredHeight());android.graphics.Bitmap image=android.graphics.Bitmap.createBitmap(body.getWidth(),body.getHeight(),android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Canvas page=new android.graphics.Canvas(image);page.drawColor(ui.bg);body.draw(page);
        try(java.io.FileOutputStream out=new java.io.FileOutputStream("/data/local/tmp/xingyu-ui-settings.png")){image.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);}image.recycle();System.out.println("SEMANTIC_ICONS_AND_SETTINGS_DRAW_PASS");
    }
    static void draw(android.view.View view,Ui ui){view.measure(android.view.View.MeasureSpec.makeMeasureSpec(ui.dp(320),1073741824),android.view.View.MeasureSpec.makeMeasureSpec(ui.dp(220),1073741824));view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());android.graphics.Bitmap b=android.graphics.Bitmap.createBitmap(view.getWidth(),view.getHeight(),android.graphics.Bitmap.Config.ARGB_8888);view.draw(new android.graphics.Canvas(b));b.recycle();}
}
