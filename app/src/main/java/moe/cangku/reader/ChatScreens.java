package moe.cangku.reader;

import android.app.AlertDialog;
import android.content.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;

/** Native chat with independent room timelines, drafts, cursors and send retries. */
final class ChatScreens {
    private final MainActivity host;
    private final ChatVault vault;
    private final android.content.SharedPreferences prefs;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService polling=Executors.newSingleThreadExecutor(),sending=Executors.newSingleThreadExecutor();
    private final Map<String,Room> rooms=new HashMap<>();
    private final Map<Long,JSONObject> profiles=new HashMap<>();
    private volatile int generation,revision;
    private volatile boolean active,foreground=true,connected;
    private boolean connecting,closed;
    private volatile String channel="1";
    private long owner=-1;
    private String address="",name="星屿旅人",token="",identity="";
    private ChatClient client;
    private final Object socketLock=new Object();
    private volatile ChatSocket socket;
    private final ScheduledExecutorService heartbeat=Executors.newSingleThreadScheduledExecutor();
    private boolean socketReady;
    private Future<?> pollingJob;
    private LinearLayout panel,messages;
    private ScrollView timeline;
    private TextView status,send,jump,photo;
    private EditText composer;
    private static final class Pending {String text,nonce;boolean inFlight;String image;long reply;JSONArray mentions;Pending(String t){text=t;nonce=UUID.randomUUID().toString();}}
    private static final class Room {final TreeMap<Long,JSONObject> messages=new TreeMap<>();long cursor;boolean loaded,older,loadingOlder;String draft="";Pending pending;JSONObject image,reply;final LinkedHashMap<Long,String> mentions=new LinkedHashMap<>();}
    ChatScreens(MainActivity h){host=h;vault=new ChatVault(h,"privateIdentity","cangku.private.v1");prefs=h.getSharedPreferences("chatUi",Context.MODE_PRIVATE);resetRooms();heartbeat.scheduleWithFixedDelay(()->{ChatSocket s=socket;if(s!=null)try{s.send("ping");}catch(Exception e){s.close();}},35,35,TimeUnit.SECONDS);}
    private void resetRooms(){rooms.clear();profiles.clear();rooms.put("1",new Room());rooms.put("2",new Room());}
    private Ui ui(){return host.design();}
    private long account(){return host.account()==null?0:host.account().optLong("id");}
    private Room room(){return rooms.get(channel);}
    private AlertDialog.Builder dialog(){return new AlertDialog.Builder(new ContextThemeWrapper(host,ui().dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert));}

    void show(){
        if(owner!=account()){
            revision++;stopPolling();owner=account();connected=false;connecting=false;resetRooms();
            address=ServiceEndpoint.origin();name=host.account()==null?"":host.account().optString("nickname");
            JSONObject saved=vault.load(owner,address);token=saved==null?"":saved.optString("token");JSONObject user=saved==null?null:saved.optJSONObject("user");identity=user==null?"":user.optString("id");
            client=address.isEmpty()?null:new ChatClient(address);channel=prefs.getString("room."+owner,"1");if(!ChatRules.channel(channel))channel="1";
        }
        JSONObject fresh=vault.load(owner,address);String latest=fresh==null?"":fresh.optString("token");
        if(!latest.equals(token)){revision++;stopPolling();token=latest;connected=false;connecting=false;}
        active=true;host.chatToolbar(this::configure);panel=ui().column();host.chatContent(panel);draw();
        if(!connected&&!connecting&&client!=null&&!token.isEmpty())connectExisting();else startPolling();host.syncChatProfile(true);
    }
    void leavePage(){saveDraft();active=false;stopPolling();}
    void pause(){saveDraft();foreground=false;stopPolling();}
    void resume(){foreground=true;if(active){if(!connected&&!connecting&&client!=null&&!token.isEmpty())connectExisting();else startPolling();host.syncChatProfile(true);}}
    void close(){closed=true;leavePage();main.removeCallbacksAndMessages(null);polling.shutdownNow();sending.shutdownNow();heartbeat.shutdownNow();}
    void resetAccount(){saveDraft();revision++;stopPolling();active=false;connected=false;connecting=false;owner=-1;token="";identity="";client=null;composer=null;resetRooms();}
    private void saveDraft(){if(composer!=null&&rooms.containsKey(channel))room().draft=composer.getText().toString();}
    private void stopPolling(){
        // Invalidate queued responses before detaching the connection. Closing a
        // TLS socket can write to the network, so ChatSocket releases it off-UI.
        generation++;socketReady=false;
        for(Room r:rooms.values()){r.loadingOlder=false;if(r.pending!=null)r.pending.inFlight=false;}
        ChatSocket previous;synchronized(socketLock){previous=socket;socket=null;}
        if(previous!=null)previous.close();
        if(client!=null)client.cancelPoll();if(pollingJob!=null)pollingJob.cancel(true);pollingJob=null;
    }
    private void choose(String next){if(channel.equals(next))return;saveDraft();stopPolling();channel=next;prefs.edit().putString("room."+owner,channel).apply();draw();startPolling();}

    private void draw(){
        if(!active||panel==null)return;Ui u=ui();panel.removeAllViews();u.pad(panel,16,8,16,6);
        LinearLayout tabs=u.row();for(String id:ChatRules.CHANNELS){TextView tab=u.chip("频道"+(id.equals("1")?"一":"二"),channel.equals(id),()->choose(id));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,u.dp(46),1);p.setMargins(id.equals("1")?0:u.dp(5),0,id.equals("1")?u.dp(5):0,0);tabs.addView(tab,p);}panel.addView(tabs);
        status=u.text(connected?"已连接 · 消息仅在当前频道显示":connecting?"正在连接聊天室…":"尚未连接聊天室",11,u.muted,false);u.pad(status,3,10,3,10);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);panel.addView(status);
        if(!connected){
            LinearLayout intro=u.column();intro.setGravity(Gravity.CENTER);TextView star=u.text("✦",48,u.pink,false);intro.addView(star);u.space(intro,18);TextView title=u.text("两个频道，各聊各的。",21,u.text,true);title.setGravity(Gravity.CENTER);intro.addView(title);u.space(intro,14);TextView description=u.text("绑定仓库账号后才能开始聊天。\n使用仓库昵称、UID和头像，频道独立。\n历史消息保留7天，请友善交流。",14,u.muted,false);description.setGravity(Gravity.CENTER);description.setLineSpacing(u.dp(6),1.1f);intro.addView(description);u.space(intro,24);TextView join=u.button(connecting?"正在连接…":"认证仓库账号 · 开始聊天",true,this::configure);join.setEnabled(!connecting);intro.addView(join,new LinearLayout.LayoutParams(-1,-2));panel.addView(intro,new LinearLayout.LayoutParams(-1,0,1));composer=null;return;
        }
        timeline=new ScrollView(host);timeline.setFillViewport(true);timeline.setVerticalScrollBarEnabled(false);messages=u.column();timeline.addView(messages,new ScrollView.LayoutParams(-1,-2));panel.addView(timeline,new LinearLayout.LayoutParams(-1,0,1));
        jump=u.text("有新消息 · 点击查看 ↓",12,u.accent,true);jump.setGravity(Gravity.CENTER);u.pad(jump,0,8,0,8);jump.setVisibility(View.GONE);u.click(jump,()->{timeline.fullScroll(View.FOCUS_DOWN);jump.setVisibility(View.GONE);});panel.addView(jump);
        if(room().reply!=null){JSONObject original=room().reply;JSONObject who=original.optJSONObject("sender");panel.addView(u.button("回复 "+(who==null?"":who.optString("nickname")+" · UID "+who.optLong("id"))+"："+(original.optJSONObject("image")!=null?"[图片] ":"")+excerpt(original.optString("text"),80)+"  ×",false,()->{if(sendingNow())return;saveDraft();room().reply=null;draw();}));}
        if(room().image!=null){LinearLayout attachment=u.row();attachment.addView(u.text("已添加图片",12,u.accent,true),new LinearLayout.LayoutParams(0,-2,1));attachment.addView(u.button("移除",false,()->{if(sendingNow())return;saveDraft();room().image=null;draw();}));panel.addView(attachment);}
        LinearLayout tools=u.row();photo=u.button("＋ 图片",false,this::pickImage);photo.setEnabled(socketReady);tools.addView(photo);panel.addView(tools);
        LinearLayout compose=u.row();composer=new EditText(host);composer.setTextColor(u.text);composer.setHintTextColor(u.muted);composer.setTextSize(15);composer.setHint("发到频道"+(channel.equals("1")?"一":"二")+"…");composer.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE|android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);composer.setMinLines(1);composer.setMaxLines(4);composer.setFilters(new InputFilter[]{new InputFilter.LengthFilter(600)});composer.setBackground(u.round(u.surface,17));u.pad(composer,14,10,14,10);composer.setText(room().draft);compose.addView(composer,new LinearLayout.LayoutParams(0,-2,1));
        String draftRoom=channel;composer.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int count,int after){}public void onTextChanged(CharSequence s,int st,int before,int count){rooms.get(draftRoom).draft=s.toString();}public void afterTextChanged(Editable e){}});
        send=u.button("发送",true,this::sendMessage);LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(u.dp(72),u.dp(48));sp.leftMargin=u.dp(8);compose.addView(send,sp);u.pad(compose,0,7,0,5);panel.addView(compose,new LinearLayout.LayoutParams(-1,-2));refreshMessages(true,false);updateComposer();
    }
    private void updateComposer(){if(composer==null||!connected)return;Pending p=room().pending;boolean inFlight=p!=null&&p.inFlight;composer.setEnabled(!inFlight);send.setEnabled(!inFlight&&socketReady);if(photo!=null)photo.setEnabled(!inFlight&&socketReady);send.setText(inFlight?"发送中":p!=null?"重试":"发送");}
    private void refreshMessages(boolean bottom,boolean older){
        if(!active||!connected||messages==null)return;Ui u=ui();int y=timeline.getScrollY(),height=messages.getHeight();boolean nearBottom=bottom||y+timeline.getHeight()>=height-u.dp(80);messages.removeAllViews();Room state=room();
        if(state.older){TextView more=u.text(state.messages.size()>=300?"已显示最近300条消息":state.loadingOlder?"正在加载…":"加载更早的消息",12,u.accent,false);more.setGravity(Gravity.CENTER);u.pad(more,0,12,0,14);if(state.messages.size()<300&&!state.loadingOlder)u.click(more,this::loadOlder);messages.addView(more);}
        if(state.messages.isEmpty()){TextView empty=u.text(state.loaded?"这里还很安静，来打个招呼吧 ✦":"正在载入消息…",14,u.muted,false);empty.setGravity(Gravity.CENTER);u.pad(empty,8,42,8,30);messages.addView(empty);}
        for(JSONObject message:state.messages.values())bubble(message);
        ScrollView currentTimeline=timeline;LinearLayout currentMessages=messages;
        timeline.post(()->{if(!active||currentTimeline!=timeline||currentMessages!=messages)return;if(older)timeline.scrollTo(0,Math.max(0,y+messages.getHeight()-height));else if(nearBottom){timeline.fullScroll(View.FOCUS_DOWN);jump.setVisibility(View.GONE);}else{timeline.scrollTo(0,y);jump.setVisibility(View.VISIBLE);}});
    }
    private void bubble(JSONObject message){
        if(!ChatRules.accepts(channel,message.optString("channel")))return;for(JSONObject profile:profiles.values())updateMessageProfile(message,profile);JSONObject sender=message.optJSONObject("sender");if(sender==null)return;Ui u=ui();boolean mine=identity.equals(sender.optString("id"));
        LinearLayout outer=u.column();outer.setGravity(mine?Gravity.RIGHT:Gravity.LEFT);u.pad(outer,0,9,0,7);LinearLayout header=u.row();
        ImageView avatar=new ImageView(host);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(u.round(u.soft,20));avatar.setClipToOutline(true);header.addView(avatar,new LinearLayout.LayoutParams(u.dp(36),u.dp(36)));host.pictures().into(sender.optString("avatar"),avatar);avatar.setContentDescription(sender.optString("nickname")+"的头像，点击艾特");u.click(avatar,()->mention(sender));
        TextView name=u.text((mine?"我 · ":"")+sender.optString("nickname")+" · UID "+sender.optLong("id"),12,u.accent,true);u.pad(name,9,0,0,0);name.setMaxLines(2);u.click(name,()->mention(sender));header.addView(name);outer.addView(header);outer.addView(u.text(time(message.optString("created_at")),10,u.muted,false));
        boolean tagged=false;JSONArray mentions=message.optJSONArray("mentions");if(mentions!=null)for(int i=0;i<mentions.length();i++)if(mentions.optJSONObject(i)!=null&&mentions.optJSONObject(i).optLong("id")==owner)tagged=true;
        JSONObject quote=message.optJSONObject("reply_to");if(quote!=null){JSONObject who=quote.optJSONObject("sender");if(who!=null&&who.optLong("id")==owner)tagged=true;TextView q=u.text("回复 "+(who==null?"":who.optString("nickname")+" · UID "+who.optLong("id"))+"："+(quote.optBoolean("has_image")?"[图片] ":"")+quote.optString("text"),12,u.muted,false);q.setMaxLines(3);u.pad(q,12,8,12,8);q.setBackground(u.round(u.soft,12));outer.addView(q);}
        if(tagged)outer.addView(u.text("有人提到了你",11,u.pink,true));
        if(message.optJSONObject("image")!=null)host.messageImages().image(outer,message.optJSONObject("image"),token);
        if(!message.optString("text").isEmpty()){TextView text=u.text(message.optString("text"),15,mine?android.graphics.Color.WHITE:u.text,false);text.setTextIsSelectable(true);text.setLineSpacing(u.dp(4),1.05f);u.pad(text,14,11,14,11);text.setBackground(u.round(mine?u.accent:u.surface,18));text.setMaxWidth(u.dp(Math.max(180,host.getResources().getConfiguration().screenWidthDp-80)));outer.addView(text);}
        TextView reply=u.text("回复",12,u.accent,false);u.pad(reply,4,8,4,8);u.click(reply,()->{if(!connected||composer==null||sendingNow())return;saveDraft();room().reply=message;draw();focusComposer();});outer.addView(reply);messages.addView(outer,new LinearLayout.LayoutParams(-1,-2));
    }
    private void mention(JSONObject sender){
        if(composer==null||!connected||sendingNow())return;Room state=room();long uid=sender.optLong("id");if(!state.mentions.containsKey(uid)&&state.mentions.size()>=5){host.toast("每条消息最多艾特5人");return;}
        String marker="@"+sender.optString("nickname")+"(UID:"+uid+") ";state.mentions.put(uid,marker);int at=Math.max(0,composer.getSelectionStart());composer.getText().insert(at,marker);focusComposer();
    }
    private void pickImage(){
        if(!connected||!socketReady)return;final String selected=channel;final long person=owner;final Room state=room();host.messageImages().pick("chat",selected,token,()->active&&owner==person&&channel.equals(selected),image->{saveDraft();state.image=image;draw();});
    }
    private boolean sendingNow(){boolean busy=room().pending!=null&&room().pending.inFlight;if(busy)host.toast("请等待当前消息发送完成");return busy;}
    private String excerpt(String text,int limit){return text.codePointCount(0,text.length())>limit?text.substring(0,text.offsetByCodePoints(0,limit))+"…":text;}
    private void focusComposer(){if(composer!=null){composer.requestFocus();((android.view.inputmethod.InputMethodManager)host.getSystemService(Context.INPUT_METHOD_SERVICE)).showSoftInput(composer,android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT);}}
    private String time(String iso){try{java.time.ZonedDateTime t=java.time.Instant.parse(iso).atZone(java.time.ZoneId.systemDefault());java.time.LocalDate today=java.time.LocalDate.now();return t.format(java.time.format.DateTimeFormatter.ofPattern(t.toLocalDate().equals(today)?"HH:mm":"MM-dd HH:mm"));}catch(Exception e){return "";}}

    private void configure(){
        if(connecting){host.toast("正在认证，请稍等");return;}Ui u=ui();LinearLayout box=u.column();u.pad(box,20,12,20,12);
        box.addView(u.text("仓库昵称："+(host.account()==null?"":host.account().optString("nickname"))+"\n仓库UID："+account(),16,u.text,true));u.space(box,14);
        box.addView(u.text("聊天室和私信使用同一仓库认证身份，不能自定义冒用他人的昵称、UID或头像。\n\n认证时当前官网会话临时交给你的Cloudflare服务向官网核验；不发送密码，不保存官网会话。认证有效7天；重新认证可同步最新昵称和头像。\n\n每条最多艾特5人；图片自动压缩，与私信共用每天10张的上传额度，发出后保留7天。",13,u.muted,false));
        dialog().setTitle("绑定仓库账号").setView(box).setNegativeButton("取消",null).setPositiveButton(token.isEmpty()?"认证并进入":"重新认证",(d,w)->{revision++;stopPolling();connected=false;connecting=false;connectNew();}).show();
    }
    private void connectNew(){
        if(client==null||connecting)return;connecting=true;draw();final int requested=revision;final long person=owner;final ChatClient target=client;final ApiClient site=host.client();
        sending.execute(()->{try{target.verify();JSONObject session=site.enablePrivateMessaging(person);main.post(()->{if(!same(requested,person))return;try{vault.save(person,target.origin,session);applySession(session);connecting=false;connected=true;if(active){draw();startPolling();}}catch(Exception e){connectionFailed("无法保存聊天身份，请重试");}});}catch(Exception e){main.post(()->{if(same(requested,person))connectionFailed(message(e));});}});
    }
    private void connectExisting(){
        if(client==null||connecting||token.isEmpty())return;connecting=true;if(active)status.setText("正在恢复聊天连接…");final int requested=revision;final long person=owner;final ChatClient target=client;final String secret=token;
        sending.execute(()->{try{target.verify();JSONObject me=target.request("/v1/me",null,secret,false);main.post(()->{if(!same(requested,person))return;try{applySession(new JSONObject().put("token",secret).put("user",me.getJSONObject("user")));connecting=false;connected=true;if(active){draw();startPolling();}}catch(Exception e){connectionFailed("聊天身份数据无效，请重新连接");}});}catch(Exception e){main.post(()->{if(same(requested,person)){if(e instanceof ChatClient.Failure&&((ChatClient.Failure)e).status==401){vault.clear(person);token="";}connectionFailed(message(e));}});}});
    }
    private void applySession(JSONObject session)throws Exception{token=session.getString("token");JSONObject user=session.getJSONObject("user");if(user.optLong("id")!=owner)throw new IOException("仓库认证身份不一致");identity=String.valueOf(owner);name=user.getString("nickname");}
    private boolean same(int requested,long person){return !closed&&requested==revision&&owner==person&&account()==person;}
    private void connectionFailed(String reason){connecting=false;connected=false;if(active){draw();status.setText(reason);}host.toast(reason);}
    private String message(Exception e){if(e instanceof java.net.SocketTimeoutException)return "聊天室连接超时，请稍后重试";if(e instanceof java.net.UnknownHostException)return "找不到聊天室地址，请检查网络和域名";return e.getMessage()==null?"聊天室连接失败":e.getMessage();}

    private void startPolling(){
        if(!active||!foreground||!connected||client==null||closed)return;stopPolling();final int requested=generation;final String selected=channel,secret=token;final ChatClient target=client;
        pollingJob=polling.submit(()->{int failures=0;
            while(valid(requested,selected)&&!Thread.currentThread().isInterrupted()){
                ChatSocket wire=null;
                try{
                    wire=new ChatSocket(target.origin,selected,secret);
                    synchronized(socketLock){if(!valid(requested,selected)){wire.close();return;}socket=wire;}
                    // Subscribe first, then load history; queued events cover the gap, IDs remove duplicates.
                    JSONObject history=target.request("/v1/channels/"+selected+"/messages?limit=30",null,secret,false);checkRoom(selected,history);
                    main.post(()->{if(!valid(requested,selected))return;merge(selected,history,false);refreshMessages(true,false);});
                    while(valid(requested,selected)){
                        String raw=wire.read();if(raw.equals("pong"))continue;JSONObject response=new JSONObject(raw);checkRoom(selected,response);String type=response.optString("type");
                        if(type.equals("ready")){failures=0;main.post(()->{if(valid(requested,selected)){socketReady=true;JSONObject profile=response.optJSONObject("user");if(profile!=null)profileChanged(profile);status.setText("已连接 · "+name+" · 频道消息独立");updateComposer();}});}
                        else if(type.equals("message")){main.post(()->{if(valid(requested,selected)){merge(selected,response,false);refreshMessages(false,false);updateComposer();}});}
                        else if(type.equals("profile")){JSONObject profile=response.optJSONObject("user");if(profile!=null)main.post(()->{if(valid(requested,selected))profileChanged(profile);});}
                        else if(type.equals("error")){main.post(()->{if(valid(requested,selected)){Pending p=room().pending;if(p!=null&&p.nonce.equals(response.optString("client_id")))p.inFlight=false;status.setText(response.optString("error","发送失败，请重试"));updateComposer();}});}
                    }
                }catch(Exception e){
                    if(!valid(requested,selected))return;
                    if((e instanceof ChatSocket.Failure&&(((ChatSocket.Failure)e).status==401||((ChatSocket.Failure)e).status==403||((ChatSocket.Failure)e).status==409))||(e instanceof ChatClient.Failure&&(((ChatClient.Failure)e).status==401||((ChatClient.Failure)e).status==403))){
                        main.post(()->{if(!valid(requested,selected))return;stopPolling();vault.clear(owner);token="";identity="";connected=false;connecting=false;draw();status.setText(message(e));});return;
                    }
                    main.post(()->{if(valid(requested,selected)){socketReady=false;Pending p=room().pending;if(p!=null)p.inFlight=false;status.setText(message(e)+" · 正在重连…");updateComposer();}});
                    failures++;try{Thread.sleep(Math.min(30000,1000L<<Math.min(failures-1,5)));}catch(InterruptedException stopped){Thread.currentThread().interrupt();return;}
                }finally{if(wire!=null)wire.close();synchronized(socketLock){if(socket==wire)socket=null;}}
            }
        });
    }
    private boolean valid(int requested,String selected){return !closed&&active&&foreground&&connected&&ChatRules.current(requested,generation,selected,channel);}
    void profileChanged(JSONObject profile){
        long uid=profile.optLong("id");if(uid<=0)return;profiles.put(uid,profile);if(uid==owner)name=profile.optString("nickname");
        for(Room state:rooms.values()){
            for(JSONObject m:state.messages.values())updateMessageProfile(m,profile);
            if(state.reply!=null)updateMessageProfile(state.reply,profile);
        }
        if(active&&connected){refreshMessages(false,false);if(status!=null)status.setText("已连接 · "+name+" · 频道消息独立");}
    }
    private void updateMessageProfile(JSONObject message,JSONObject profile){
        try{
            JSONObject sender=message.optJSONObject("sender");if(sender!=null&&sender.optLong("id")==profile.optLong("id"))message.put("sender",profile);
            JSONObject reply=message.optJSONObject("reply_to");if(reply!=null&&reply.optJSONObject("sender")!=null&&reply.optJSONObject("sender").optLong("id")==profile.optLong("id"))reply.put("sender",profile);
        }catch(JSONException ignored){}
    }
    private void checkRoom(String expected,JSONObject response)throws Exception{if(!ChatRules.accepts(expected,response.optString("channel")))throw new IOException("频道数据不一致");JSONArray data=response.optJSONArray("messages");if(data!=null)for(int i=0;i<data.length();i++)if(!ChatRules.accepts(expected,data.getJSONObject(i).optString("channel")))throw new IOException("频道数据不一致");}
    private void merge(String selected,JSONObject response,boolean older){
        Room state=rooms.get(selected);JSONArray data=response.optJSONArray("messages");if(data!=null)for(int i=0;i<data.length();i++){JSONObject m=data.optJSONObject(i);if(m!=null&&ChatRules.accepts(selected,m.optString("channel"))){state.messages.put(m.optLong("id"),m);Pending p=state.pending;if(p!=null&&identity.equals(m.optJSONObject("sender")==null?"":m.optJSONObject("sender").optString("id"))&&p.nonce.equals(m.optString("client_id"))){boolean sameImage=(state.image==null?"":state.image.optString("id")).equals(p.image),sameReply=(state.reply==null?0:state.reply.optLong("id"))==p.reply;if(state.draft.trim().equals(p.text)&&sameImage&&sameReply){state.draft="";if(selected.equals(channel)&&composer!=null)composer.setText("");}state.pending=null;if(sameImage)state.image=null;if(sameReply)state.reply=null;state.mentions.entrySet().removeIf(entry->!state.draft.contains(entry.getValue().trim()));final int drawGeneration=generation;if(!p.image.isEmpty()||p.reply>0)main.post(()->{if(active&&drawGeneration==generation&&selected.equals(channel)){draw();if(composer!=null)composer.requestFocus();}});}}}
        while(state.messages.size()>300)state.messages.pollFirstEntry();if(!older)state.cursor=Math.max(state.cursor,response.optLong("cursor"));if(older||!state.loaded)state.older=response.optBoolean("has_older");state.loaded=true;
    }
    private void loadOlder(){
        Room state=room();if(!connected||state.messages.isEmpty()||state.loadingOlder||state.messages.size()>=300)return;state.loadingOlder=true;final int requested=generation;final String selected=channel,secret=token;final ChatClient target=client;final long before=state.messages.firstKey();final int limit=Math.min(30,300-state.messages.size());refreshMessages(false,false);
        sending.execute(()->{try{JSONObject response=target.request("/v1/channels/"+selected+"/messages?before="+before+"&limit="+limit,null,secret,false);checkRoom(selected,response);main.post(()->{if(!valid(requested,selected))return;state.loadingOlder=false;merge(selected,response,true);refreshMessages(false,true);});}catch(Exception e){main.post(()->{if(valid(requested,selected)){state.loadingOlder=false;host.toast(message(e));}});}});
    }
    private void sendMessage(){
        if(!connected||composer==null||!socketReady)return;Room state=room();String text=composer.getText().toString().trim();if(text.isEmpty()&&state.image==null){host.toast("先写点内容或添加图片吧");return;}
        if(text.codePointCount(0,text.length())>300){host.toast("每条消息最多300字");return;}
        state.mentions.entrySet().removeIf(entry->!text.contains(entry.getValue().trim()));JSONArray tags=new JSONArray();for(long uid:state.mentions.keySet())tags.put(uid);String picture=state.image==null?"":state.image.optString("id");long reply=state.reply==null?0:state.reply.optLong("id");
        if(state.pending!=null&&state.pending.inFlight)return;if(state.pending==null||!text.equals(state.pending.text)||!picture.equals(state.pending.image)||reply!=state.pending.reply||!tags.toString().equals(state.pending.mentions.toString())){state.pending=new Pending(text);state.pending.image=picture;state.pending.reply=reply;state.pending.mentions=tags;}

        Pending pending=state.pending;pending.inFlight=true;updateComposer();final String selected=channel;final int requested=generation;final ChatSocket target=socket;
        sending.execute(()->{try{
            if(target==null)throw new IOException("连接中断，请等待重连");
            target.send(new JSONObject().put("type","send").put("channel",selected).put("text",pending.text).put("client_id",pending.nonce).put("mentions",pending.mentions).put("reply_to_id",pending.reply).put("image_id",pending.image).toString());
            main.postDelayed(()->{if(valid(requested,selected)&&state.pending==pending&&pending.inFlight){pending.inFlight=false;status.setText("尚未收到确认，点击重试不会重复发送");updateComposer();}},12000);
        }catch(Exception e){main.post(()->{if(valid(requested,selected)&&state.pending==pending){pending.inFlight=false;status.setText(message(e));updateComposer();}});}});
    }
}
