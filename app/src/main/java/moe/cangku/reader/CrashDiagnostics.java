package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.os.Build;
import android.widget.*;
import org.json.*;

/** Private, manual diagnostics. Nothing is sent to a server. */
final class CrashDiagnostics {
    private static final String PREF="localCrashDiagnostics",KEY="pending",HISTORY="history";
    private static boolean installed;
    static synchronized void install(Activity host){
        if(installed)return;installed=true;
        final Context context=host.getApplicationContext();final Thread.UncaughtExceptionHandler previous=Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread,failure)->{
            try{record(context,failure,"uncaught");}catch(Throwable ignored){}
            if(previous!=null)previous.uncaughtException(thread,failure);
            else{android.os.Process.killProcess(android.os.Process.myPid());System.exit(10);}
        });
    }
    private static String environment(Context context){
        String version="unknown";try{version=context.getPackageManager().getPackageInfo(context.getPackageName(),0).versionName;}catch(Exception ignored){}
        return "星屿本机诊断\nVersion: "+version+"\nEngine: Android Native\nAndroid: "+Build.VERSION.RELEASE+" (API "+Build.VERSION.SDK_INT+")\nDevice: "+Build.MANUFACTURER+" "+Build.MODEL;
    }
    private static JSONArray history(Context context){
        SharedPreferences prefs=context.getSharedPreferences(PREF,0);
        try{JSONArray list=new JSONArray(prefs.getString(HISTORY,"[]"));if(list.length()>0)return list;}catch(Exception ignored){}
        JSONArray list=new JSONArray();String previous=prefs.getString(KEY,null);if(previous!=null)list.put(previous);return list;
    }
    static synchronized String record(Context context,Throwable failure,String step){
        String report=environment(context)+"\nTime (UTC): "+java.time.Instant.now()+"\nStep: "+step+"\n"+CrashReport.frames(failure);
        if(report.length()>16000)report=report.substring(0,16000)+"\n[truncated]";
        JSONArray previous=history(context),next=new JSONArray();next.put(report);for(int i=0;i<Math.min(9,previous.length());i++)next.put(previous.optString(i));
        context.getSharedPreferences(PREF,0).edit().putString(KEY,report).putString(HISTORY,next.toString()).commit();return report;
    }
    static synchronized String report(Context context){
        StringBuilder report=new StringBuilder(environment(context));report.append("\n\n仅保存在本机，不自动上传。最近最多保留10条异常；不记录密码、会话、API Key、请求正文或异常消息。\n");
        JSONArray entries=history(context);if(entries.length()==0)report.append("\n暂无异常记录。\n");
        for(int i=0;i<Math.min(10,entries.length());i++)report.append("\n—— 异常 ").append(i+1).append(" ——\n").append(entries.optString(i));return report.toString();
    }
    static void show(Activity host){
        boolean dark=host instanceof MainActivity&&((MainActivity)host).design().dark;Ui ui=new Ui(host,dark);
        TextView text=ui.text(report(host),12,ui.text,false);text.setTypeface(android.graphics.Typeface.MONOSPACE);text.setTextIsSelectable(true);ui.pad(text,18,14,18,14);
        ScrollView scroll=new ScrollView(host);scroll.addView(text);scroll.setFillViewport(false);
        AlertDialog dialog=new AlertDialog.Builder(new android.view.ContextThemeWrapper(host,dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert))
            .setTitle("诊断信息").setView(scroll).setNegativeButton("关闭",null).setNeutralButton("清空记录",null).setPositiveButton("复制诊断",null).create();
        dialog.setOnShowListener(d->{dialog.getButton(-1).setOnClickListener(v->{copy(host,report(host));clear(host);});dialog.getButton(-3).setOnClickListener(v->new AlertDialog.Builder(host).setTitle("清空本机异常记录？").setMessage("只清除诊断记录，不影响账号、投稿草稿或阅读数据。").setNegativeButton("取消",null).setPositiveButton("清空",(a,w)->{clearHistory(host);text.setText(report(host));}).show());});dialog.show();
        if(dialog.getWindow()!=null)dialog.getWindow().setLayout(-1,(int)(host.getResources().getDisplayMetrics().heightPixels*.8));
    }
    private static void copy(Activity host,String report){
        ((ClipboardManager)host.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("星屿本机诊断",report));Toast.makeText(host,"诊断已复制",Toast.LENGTH_SHORT).show();
    }
    static void offer(Activity host){
        String report=host.getSharedPreferences(PREF,0).getString(KEY,null);if(report==null)return;
        TextView text=new TextView(host);text.setText("请将下面的诊断复制给开发者，以便继续修复。只包含设备版本和错误调用位置，不包含密码、令牌和正文。\n\n"+report);text.setTextIsSelectable(true);text.setPadding(28,20,28,20);text.setTextSize(13);ScrollView scroll=new ScrollView(host);scroll.addView(text);
        new AlertDialog.Builder(host).setTitle("上次运行发生异常").setView(scroll).setNegativeButton("稍后",(d,w)->{})
            .setPositiveButton("复制诊断",(d,w)->{copy(host,report);clear(host);}).show();
    }
    static void clear(Context context){context.getSharedPreferences(PREF,0).edit().remove(KEY).apply();}
    static synchronized void clearHistory(Context context){context.getSharedPreferences(PREF,0).edit().remove(KEY).remove(HISTORY).apply();}
}
