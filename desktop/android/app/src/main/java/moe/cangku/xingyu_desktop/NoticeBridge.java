package moe.cangku.xingyu_desktop;

import android.app.*;
import android.app.job.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;
import org.json.*;
import java.util.*;

/** System notifications and JobScheduler; never starts a permanent service. */
final class NoticeBridge {
    static final Object LOCK = new Object();
    static final int JOB = 73105, PERMISSION = 4103;
    static final String EXTRA = "xingyu.notice", CHANNEL = "xingyu.messages.v1";
    static SharedPreferences prefs(Context c) { return c.getSharedPreferences("xingyu.notices", Context.MODE_PRIVATE); }
    static boolean granted(Context c) {
        return (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED)
            && c.getSystemService(NotificationManager.class).areNotificationsEnabled();
    }
    static void channels(Context c) {
        NotificationChannel channel = new NotificationChannel(CHANNEL, "消息提醒", NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription("私信、艾特、帖子与评论回复");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        c.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }
    static Map<String,Object> status(Context c) {
        Map<String,Object> out = new HashMap<>();
        out.put("supported",true); out.put("granted",granted(c));
        NotificationChannel channel=c.getSystemService(NotificationManager.class).getNotificationChannel(CHANNEL);
        out.put("channelBlocked",channel!=null && channel.getImportance()==NotificationManager.IMPORTANCE_NONE);
        out.put("scheduled",c.getSystemService(JobScheduler.class).getPendingJob(JOB)!=null);
        out.put("lastCheck",prefs(c).getString("lastCheck",""));
        out.put("backgroundStatus",prefs(c).getString("status","waiting"));
        return out;
    }
    static void configure(Context c, int uid, boolean enabled, String origin, JSONObject preferences) throws Exception {
        synchronized(LOCK) {
            SharedPreferences p=prefs(c);
            boolean active=enabled && uid>0;
            boolean same=p.getInt("uid",0)==uid && p.getBoolean("enabled",false)==active;
            SharedPreferences.Editor edit=p.edit();
            if (!same) { edit.clear().putLong("epoch",p.getLong("epoch",0)+1); c.getSystemService(NotificationManager.class).cancelAll(); }
            edit.putInt("uid",uid).putBoolean("enabled",active).putString("origin",origin).putString("preferences",preferences.toString()).commit();
            JobScheduler scheduler=c.getSystemService(JobScheduler.class);
            if(!active) { scheduler.cancel(JOB); return; }
            channels(c);
            if(same && scheduler.getPendingJob(JOB)!=null) return;
            JobInfo job=new JobInfo.Builder(JOB,new ComponentName(c,NoticeJobService.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
                .setPeriodic(15*60*1000L,5*60*1000L)
                .setBackoffCriteria(15*60*1000L,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build();
            if(scheduler.schedule(job)!=JobScheduler.RESULT_SUCCESS) throw new IllegalStateException("schedule");
        }
    }
    static void settings(Activity a) {
        a.startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,a.getPackageName()));
    }
    static void show(Context c, JSONObject payload) throws Exception {
        synchronized(LOCK) {
            SharedPreferences p=prefs(c); int uid=payload.optInt("uid");
            if(!p.getBoolean("enabled",false) || p.getInt("uid",0)!=uid || !granted(c)) return;
            JSONObject options=new JSONObject(p.getString("preferences","{}"));
            String key=payload.optString("key"),kind=payload.optString("kind");
            if(key.isEmpty() || key.length()>180 || !options.optBoolean(kind,true)) return;
            JSONArray seen=new JSONArray(p.getString("delivered","[]"));
            for(int i=0;i<seen.length();i++) if(key.equals(seen.optString(i))) return;
            channels(c);
            String title=(kind.equals("checkin")||options.optBoolean("preview",false))?payload.optString("title","星屿 · 新消息"):"星屿 · 新消息";
            String body=(kind.equals("checkin")||options.optBoolean("preview",false))?payload.optString("body","点击查看新消息"):"你有一条新的消息，点击查看";
            // Only routing metadata enters PendingIntent, never the body or credentials.
            JSONObject route=new JSONObject().put("uid",uid).put("key",key).put("kind",kind)
                .put("target",payload.optInt("target")).put("channel",payload.optString("channel"));
            Intent intent=new Intent(c,MainActivity.class).setAction("xingyu.notice."+key)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra(EXTRA,route.toString());
            PendingIntent tap=PendingIntent.getActivity(c,key.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
            Notification notification=new Notification.Builder(c,CHANNEL).setSmallIcon(moe.cangku.xingyu_desktop.R.drawable.ic_notification)
                .setContentTitle(title).setContentText(body).setStyle(new Notification.BigTextStyle().bigText(body))
                .setContentIntent(tap).setAutoCancel(true).setCategory(Notification.CATEGORY_SOCIAL)
                .setVisibility(Notification.VISIBILITY_PRIVATE).build();
            c.getSystemService(NotificationManager.class).notify(key,0,notification);
            JSONArray next=new JSONArray(); for(int i=Math.max(0,seen.length()-399);i<seen.length();i++) next.put(seen.get(i)); next.put(key);
            p.edit().putString("delivered",next.toString()).commit();
        }
    }
}
