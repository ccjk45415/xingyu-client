package moe.cangku.reader;

import android.app.AlertDialog;
import android.content.*;
import android.os.*;
import android.text.TextUtils;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

/** Two native pages: discovery artwork and a remotely managed, live announcement board. */
final class HomeCarousel {
    private final MainActivity host;
    private final Ui ui;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService network=Executors.newSingleThreadExecutor();
    private final ScheduledExecutorService heartbeat=Executors.newSingleThreadScheduledExecutor();
    private final android.content.SharedPreferences cache;
    private final LinearLayout root,track;
    private final Pager pager;
    private final TextView headline,preview,stamp,count;
    private final TextView[] indicators=new TextView[2];
    private JSONObject board;
    private AlertDialog detailDialog;
    private LinearLayout detailBody;
    private volatile boolean active,closed;
    private volatile int generation;
    private volatile ChatSocket socket;
    private Future<?> job;
    private int selected;
    private long touched;
    private final Runnable rotate=this::rotate;
    HomeCarousel(MainActivity h){
        host=h;ui=h.design();cache=h.getSharedPreferences("homeAnnouncements",Context.MODE_PRIVATE);root=ui.column();
        board=empty();try{board=validate(new JSONObject(cache.getString("board",empty().toString())));}catch(Exception ignored){}
        pager=new Pager();pager.setHorizontalScrollBarEnabled(false);pager.setOverScrollMode(View.OVER_SCROLL_NEVER);pager.setFillViewport(true);
        track=ui.row();pager.addView(track,new HorizontalScrollView.LayoutParams(-2,-1));root.addView(pager,new LinearLayout.LayoutParams(-1,ui.dp(172)));
        FrameLayout discovery=background();LinearLayout words=ui.column();ui.pad(words,22,23,22,20);
        words.addView(ui.text("YOUR LITTLE UNIVERSE",10,0xDDFFFFFF,true));ui.space(words,14);words.addView(ui.text("今天，也有新的心动。",23,android.graphics.Color.WHITE,true));ui.space(words,8);words.addView(ui.text("探索灵感 / 珍藏热爱 / 自在阅读",12,0xEEFFFFFF,false));discovery.addView(words);track.addView(discovery,new LinearLayout.LayoutParams(1,-1));
        FrameLayout announcements=background();LinearLayout notice=ui.column();ui.pad(notice,22,17,22,12);LinearLayout header=ui.row();header.addView(ui.text("✦  公告栏",13,android.graphics.Color.WHITE,true),new LinearLayout.LayoutParams(0,-2,1));count=ui.text("",10,0xEEFFFFFF,false);header.addView(count);notice.addView(header);ui.space(notice,9);
        headline=ui.text("",19,android.graphics.Color.WHITE,true);headline.setMaxLines(1);headline.setEllipsize(TextUtils.TruncateAt.END);notice.addView(headline);
        ui.space(notice,5);preview=ui.text("",12,0xEEFFFFFF,false);preview.setMaxLines(2);preview.setEllipsize(TextUtils.TruncateAt.END);preview.setLineSpacing(ui.dp(2),1.1f);notice.addView(preview,new LinearLayout.LayoutParams(-1,0,1));
        stamp=ui.text("",10,0xDDFFFFFF,false);notice.addView(stamp);announcements.addView(notice);announcements.setContentDescription("公告栏，点击查看完整公告");ui.click(announcements,this::details);track.addView(announcements,new LinearLayout.LayoutParams(1,-1));
        LinearLayout dots=ui.row();dots.setGravity(Gravity.CENTER);for(int i=0;i<2;i++){final int index=i;TextView dot=ui.text("",11,ui.muted,false);dot.setGravity(Gravity.CENTER);ui.pad(dot,13,8,13,5);dot.setMinHeight(ui.dp(32));dot.setContentDescription(i==0?"轮播：发现":"轮播：公告栏");indicators[i]=dot;ui.click(dot,()->{touched=SystemClock.elapsedRealtime();select(index,true);});dots.addView(dot);}root.addView(dots);select(0,false);renderBoard("正在连接公告…");
        heartbeat.scheduleWithFixedDelay(()->{ChatSocket wire=socket;if(wire!=null)try{wire.send("ping");}catch(Exception e){wire.close();}},35,35,TimeUnit.SECONDS);
    }
    View view(){return root;}
    private FrameLayout background(){FrameLayout frame=new FrameLayout(host);frame.setBackground(ui.round(ui.soft,22));frame.setClipToOutline(true);frame.addView(new Ui.Aurora(host),new FrameLayout.LayoutParams(-1,-1));return frame;}
    private static JSONObject empty(){try{return new JSONObject().put("schema",1).put("revision",0).put("updated_at",JSONObject.NULL).put("items",new JSONArray());}catch(JSONException e){throw new IllegalStateException(e);}}
    static JSONObject validate(JSONObject value)throws JSONException{
        if(value.getInt("schema")!=1||!(value.get("revision") instanceof Number)||value.getDouble("revision")!=value.getLong("revision")||value.getLong("revision")<0)throw new JSONException("公告版本无效");
        JSONArray items=value.getJSONArray("items");if(items.length()>10)throw new JSONException("公告数量过多");Set<String> ids=new HashSet<>();
        for(int i=0;i<items.length();i++){JSONObject item=items.getJSONObject(i);String id=item.getString("id");if(!id.matches("[a-zA-Z0-9_-]{1,64}")||!ids.add(id))throw new JSONException("公告ID无效");
            for(String key:new String[]{"title","content"}){Object raw=item.get(key);if(!(raw instanceof String))throw new JSONException("公告内容无效");String text=(String)raw;if(text.trim().isEmpty()||text.codePointCount(0,text.length())>(key.equals("title")?80:5000)||text.matches("(?s).*[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f].*"))throw new JSONException("公告内容无效");}}
        if(value.getLong("revision")>0)try{java.time.Instant.parse(value.getString("updated_at"));}catch(Exception e){throw new JSONException("公告时间无效");}return value;
    }
    private void renderBoard(String connection){
        JSONArray items=board.optJSONArray("items");int n=items==null?0:items.length();JSONObject first=n==0?null:items.optJSONObject(0);
        headline.setText(first==null?"暂无公告":first.optString("title"));preview.setText(first==null?"新消息会在这里与你相遇。":first.optString("content"));count.setText(n==0?"":"共 "+n+" 条  ›");
        String updated="";try{updated=java.time.Instant.parse(board.getString("updated_at")).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm"));}catch(Exception ignored){}
        stamp.setText(connection+(updated.isEmpty()?"":" · 更新于 "+updated));
    }
    private void accept(JSONObject value,int request){
        if(!valid(request)||value.optLong("revision")<board.optLong("revision"))return;boolean changed=value.optLong("revision")>board.optLong("revision");board=value;
        cache.edit().putString("board",value.toString()).apply();renderBoard("实时公告 · 点击查看全文");
        if(detailDialog!=null&&detailDialog.isShowing())renderDetails();
        if(changed&&value.optJSONArray("items").length()>0&&!pager.dragging&&SystemClock.elapsedRealtime()-touched>2000)select(1,true);
    }
    void start(){
        if(closed||active)return;active=true;int requested=++generation;main.removeCallbacks(rotate);main.postDelayed(rotate,6000);renderBoard("正在同步公告…");
        job=network.submit(()->{int failures=0;
            while(valid(requested)&&!Thread.currentThread().isInterrupted()){
                ChatSocket wire=null;
                try{
                    wire=ChatSocket.announcements(ServiceEndpoint.origin());if(!valid(requested)){wire.close();return;}socket=wire;
                    // Every subscription includes the latest snapshot, covering offline updates.
                    while(valid(requested)){String raw=wire.read();if(raw.equals("pong"))continue;JSONObject event=new JSONObject(raw);if(!event.optString("type").equals("announcements"))continue;JSONObject next=validate(event.getJSONObject("data"));failures=0;main.post(()->accept(next,requested));}
                }catch(Exception e){
                    if(!valid(requested))return;
                    // Read fallback also covers networks that temporarily reject WebSocket upgrades.
                    try{JSONObject next=validate(new ChatClient(ServiceEndpoint.origin()).request("/announcements",null,null,false));main.post(()->{accept(next,requested);if(valid(requested))renderBoard("公告已同步 · 实时连接重试中");});}catch(Exception ignored){main.post(()->{if(valid(requested))renderBoard(board.optLong("revision")>0?"上次公告 · 正在重连":"公告暂未连接 · 正在重试");});}
                    try{Thread.sleep(Math.min(30000,1000L<<Math.min(failures++,5)));}catch(InterruptedException stopped){Thread.currentThread().interrupt();return;}
                }finally{if(wire!=null)wire.close();if(socket==wire)socket=null;}
            }
        });
    }
    private boolean valid(int request){return active&&!closed&&request==generation;}
    void pause(){active=false;generation++;pager.dragging=false;main.removeCallbacks(rotate);ChatSocket wire=socket;socket=null;if(wire!=null)wire.close();if(job!=null)job.cancel(true);job=null;}
    void close(){closed=true;pause();if(detailDialog!=null)detailDialog.dismiss();network.shutdownNow();heartbeat.shutdownNow();}
    private void rotate(){if(!active||closed)return;if(!pager.dragging&&SystemClock.elapsedRealtime()-touched>12000)select(1-selected,true);main.postDelayed(rotate,6000);}
    private void select(int page,boolean animate){selected=page;for(int i=0;i<2;i++){indicators[i].setText((i==selected?"●  ":"○  ")+(i==0?"发现":"公告"));indicators[i].setTextColor(i==selected?ui.accent:ui.muted);}if(pager.getWidth()>0){if(animate)pager.smoothScrollTo(page*pager.getWidth(),0);else pager.scrollTo(page*pager.getWidth(),0);}}
    private void details(){
        if(detailDialog!=null&&detailDialog.isShowing())return;
        ScrollView scroll=new ScrollView(host);detailBody=ui.column();ui.pad(detailBody,20,12,20,20);scroll.addView(detailBody);renderDetails();
        detailDialog=new AlertDialog.Builder(new ContextThemeWrapper(host,ui.dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert)).setTitle("公告栏").setView(scroll).setPositiveButton("关闭",null).create();detailDialog.setOnDismissListener(d->{detailDialog=null;detailBody=null;});detailDialog.show();
    }
    private void renderDetails(){LinearLayout body=detailBody;if(body==null)return;body.removeAllViews();JSONArray items=board.optJSONArray("items");if(items==null||items.length()==0)body.addView(ui.text("暂时没有公告。",15,ui.muted,false));else for(int i=0;i<items.length();i++){JSONObject item=items.optJSONObject(i);body.addView(ui.text(item.optString("title"),19,ui.text,true));ui.space(body,10);TextView content=ui.text(item.optString("content"),15,ui.text,false);content.setTextIsSelectable(true);content.setLineSpacing(ui.dp(5),1.15f);body.addView(content);ui.space(body,24);}}
    private final class Pager extends HorizontalScrollView {
        boolean dragging;private float downX,downY;private final int slop=ViewConfiguration.get(host).getScaledTouchSlop();
        Pager(){super(host);}
        @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){super.onSizeChanged(w,h,oldw,oldh);if(w>0){for(int i=0;i<track.getChildCount();i++){View card=track.getChildAt(i);LinearLayout.LayoutParams p=(LinearLayout.LayoutParams)card.getLayoutParams();p.width=w;card.setLayoutParams(p);}post(()->select(selected,false));}}
        @Override public boolean onInterceptTouchEvent(android.view.MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN){downX=e.getX();downY=e.getY();dragging=true;touched=SystemClock.elapsedRealtime();}if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&Math.abs(e.getX()-downX)>slop&&Math.abs(e.getX()-downX)>Math.abs(e.getY()-downY))getParent().requestDisallowInterceptTouchEvent(true);if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL){dragging=false;touched=SystemClock.elapsedRealtime();}return super.onInterceptTouchEvent(e);}
        @Override public boolean onTouchEvent(MotionEvent e){boolean handled=super.onTouchEvent(e);if(e.getActionMasked()==MotionEvent.ACTION_DOWN){downX=e.getX();downY=e.getY();dragging=true;touched=SystemClock.elapsedRealtime();}if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL){dragging=false;touched=SystemClock.elapsedRealtime();float dx=downX-e.getX(),dy=downY-e.getY();int target=e.getActionMasked()==MotionEvent.ACTION_UP&&Math.abs(dx)>ui.dp(28)&&Math.abs(dx)>Math.abs(dy)?(dx>0?1:0):(getScrollX()>getWidth()/2?1:0);select(target,true);getParent().requestDisallowInterceptTouchEvent(false);}return handled;}
        @Override public void fling(int velocity){select(velocity>0?1:velocity<0?0:selected,true);}
    }
}
