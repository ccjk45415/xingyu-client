package moe.cangku.reader;

import android.app.AlertDialog;
import android.content.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

/** Opt-in, website-verified private messaging. Public nickname chat identities cannot send DMs. */
final class PrivateScreens {
    private final MainActivity host;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ChatVault vault;
    private final ChatClient service=new ChatClient(ServiceEndpoint.origin());
    private final ExecutorService cleanup=Executors.newSingleThreadExecutor();
    private long owner=-1,peerId,cursor,lastRead,serial;
    private String token="",peerName="",peerAvatar="";
    private boolean active,foreground=true,closed,loading,loaded,hasOlder,loadingOlder,inboxHistory;
    private final TreeMap<Long,JSONObject> messages=new TreeMap<>();
    private final Map<Long,String> drafts=new HashMap<>();
    private final Map<Long,Pending> pending=new HashMap<>();
    private LinearLayout thread,olderSlot;
    private ScrollView timeline;
    private EditText composer;
    private TextView send,status,photo;
    private final Map<Long,JSONObject> images=new HashMap<>();
    private static final class Pending {final String text,image,nonce=UUID.randomUUID().toString();boolean inFlight;Pending(String s,String i){text=s;image=i;}}
    private final Runnable poll=this::pollNow;
    private void pollNow(){if(live()){if(host.currentKind().equals("dmConversation"))loadMessages(false);else if(host.currentKind().equals("privateMessages")&&!inboxHistory)loadInbox(false);}}
    PrivateScreens(MainActivity h){host=h;vault=new ChatVault(h,"privateIdentity","cangku.private.v1");}
    private Ui ui(){return host.design();}
    private long account(){return host.account()==null?0:host.account().optLong("id");}
    private boolean live(){return active&&foreground&&!closed&&owner==account()&&!token.isEmpty();}
    private boolean current(long request){return live()&&request==serial;}
    private void identify(){
        if(owner!=account()){
            leavePage();owner=account();messages.clear();drafts.clear();pending.clear();images.clear();peerId=cursor=lastRead=0;loaded=false;token="";
            JSONObject saved=vault.load(owner,ServiceEndpoint.origin());
            if(saved!=null&&saved.optJSONObject("user")!=null&&saved.optJSONObject("user").optLong("id")==owner){
                try{if(java.time.Instant.parse(saved.optString("expires_at")).toEpochMilli()>System.currentTimeMillis())token=saved.optString("token");}catch(Exception ignored){}
            }
            if(!token.matches("[a-f0-9]{64}"))token="";
        }
        JSONObject fresh=vault.load(owner,ServiceEndpoint.origin());token="";if(fresh!=null&&fresh.optJSONObject("user")!=null&&fresh.optJSONObject("user").optLong("id")==owner)try{if(java.time.Instant.parse(fresh.optString("expires_at")).toEpochMilli()>System.currentTimeMillis())token=fresh.optString("token");}catch(Exception ignored){}
        active=true;host.syncChatProfile(true);
    }
    void leavePage(){
        saveDraft();active=false;serial++;loading=false;loadingOlder=false;main.removeCallbacks(poll);
        for(Pending p:pending.values())p.inFlight=false;
        composer=null;send=null;status=null;thread=null;timeline=null;olderSlot=null;
    }
    void pause(){saveDraft();foreground=false;serial++;loading=false;loadingOlder=false;for(Pending p:pending.values())p.inFlight=false;main.removeCallbacks(poll);}
    void resume(){foreground=true;if(active&&!token.isEmpty())main.post(poll);}
    void close(){closed=true;leavePage();cleanup.shutdown();}
    void resetAccount(){
        long previous=owner>0?owner:account();String previousToken=token;
        if(previousToken.isEmpty()&&previous>0){JSONObject saved=vault.load(previous,ServiceEndpoint.origin());if(saved!=null)previousToken=saved.optString("token");}
        if(previous>0)vault.clear(previous);
        leavePage();owner=-1;token="";messages.clear();drafts.clear();pending.clear();images.clear();peerId=0;
        final String revoked=previousToken;
        if(!revoked.isEmpty()&&!cleanup.isShutdown())cleanup.execute(()->{try{service.request("/dm/v1/logout",new JSONObject(),revoked,false);}catch(Exception ignored){}});
    }
    private void saveDraft(){if(composer!=null&&peerId>0)drafts.put(peerId,composer.getText().toString());}
    private void later(){main.removeCallbacks(poll);if(live())main.postDelayed(poll,20000);}
    private void fail(String reason){loading=false;loadingOlder=false;if(reason.startsWith("私信身份已过期")){vault.clear(owner);token="";host.toast(reason);host.reloadNative();return;}if(status!=null)status.setText(reason+" · 可点击右上角重试");else host.toast(reason);later();}
    private void failure(Exception e)throws Exception{
        if(e instanceof ChatClient.Failure&&((ChatClient.Failure)e).status==401)throw new java.io.IOException("私信身份已过期，请重新验证开通");throw e;
    }
    private JSONObject request(String path,JSONObject body,String secret)throws Exception{
        try{return service.request(path,body,secret,false);}catch(Exception e){failure(e);return null;}
    }
    private boolean ready(){
        identify();if(!token.isEmpty())return true;
        LinearLayout body=host.content();Ui u=ui();u.space(body,20);body.addView(u.text("给喜欢的创作者，留一封信。",22,u.text,true));u.space(body,16);
        TextView info=u.text("聊天室和私信共用仓库认证身份。双方需安装并认证，官网网页不会收到这些私信。\n\n开通会把当前官网会话经加密连接交给你的 Cloudflare 服务，由服务向 cangku.moe 验证身份；密码不发送，官网会话不保存。私信令牌在本机加密保存，7天有效。\n\n消息保留7天，使用 HTTPS 传输，服务端可读取；仅在前台检查新消息，没有系统推送。",14,u.muted,false);info.setLineSpacing(u.dp(6),1.1f);body.addView(info);u.space(body,24);
        TextView enable=u.button("验证官网身份 · 开通私信",true,()->{});body.addView(enable);TextView result=u.text("",12,u.muted,false);u.space(body,12);body.addView(result);
        u.click(enable,()->{
            enable.setEnabled(false);enable.setText("正在验证…");long person=owner;ApiClient site=host.client();
            host.task(()->site.enablePrivateMessaging(person),session->{
                if(account()!=person)return;vault.save(person,ServiceEndpoint.origin(),session);token=session.getString("token");host.reloadNative();
            },message->{enable.setEnabled(true);enable.setText("重试身份验证");result.setText(message);});
        });return false;
    }
    void inbox(){
        inboxHistory=false;
        host.socialToolbar("我的私信",host::reloadNative);if(!ready())return;Ui u=ui();LinearLayout body=host.content();
        body.addView(u.button("＋ 选择收信人",true,()->host.navigateNative("dmPeople","选择收信人",0)));u.space(body,10);
        body.addView(u.button("拒收名单 / 私信设置",false,()->host.navigateNative("dmBlocks","私信设置",0)));u.space(body,12);
        body.addView(u.text("仅在前台同步 · 历史保留7天 · 对方需开通私信",11,u.muted,false));
        status=u.text("正在加载会话…",12,u.muted,false);u.space(body,14);body.addView(status);thread=u.column();body.addView(thread);loadInbox(true);
    }
    private void loadInbox(boolean first){
        if(!live()||loading||thread==null)return;loading=true;long requested=serial;String secret=token;
        host.task(()->request("/dm/v1/conversations",null,secret),response->{
            if(!current(requested))return;loading=false;thread.removeAllViews();JSONArray all=response.optJSONArray("conversations");
            status.setText("已同步 · 点击会话开始聊天");if(all==null||all.length()==0)thread.addView(ui().text("还没有私信，先选择一位收信人吧。",14,ui().muted,false));
            else for(int i=0;i<all.length();i++)conversationCard(thread,all.getJSONObject(i));
            if(response.optBoolean("has_more")&&all!=null&&all.length()>0){long before=all.getJSONObject(all.length()-1).getJSONObject("last_message").optLong("id");inboxMore(thread,before,requested,secret);}
            later();
        },message->{if(current(requested))fail(message);});
    }
    private void inboxMore(LinearLayout list,long before,long generation,String secret){
        TextView more=ui().button("加载更早的会话",false,()->{});list.addView(more);
        ui().click(more,()->{inboxHistory=true;main.removeCallbacks(poll);more.setEnabled(false);host.task(()->request("/dm/v1/conversations?before="+before,null,secret),r->{if(!current(generation))return;list.removeView(more);JSONArray a=r.optJSONArray("conversations");if(a!=null)for(int i=0;i<a.length();i++)conversationCard(list,a.getJSONObject(i));if(r.optBoolean("has_more")&&a!=null&&a.length()>0)inboxMore(list,a.getJSONObject(a.length()-1).getJSONObject("last_message").optLong("id"),generation,secret);main.removeCallbacks(poll);},m->{if(current(generation)){more.setEnabled(true);host.toast(m);}});});
    }
    private void conversationCard(LinearLayout parent,JSONObject data){
        JSONObject peer=data.optJSONObject("peer"),last=data.optJSONObject("last_message");if(peer==null)return;Ui u=ui();LinearLayout card=u.column();u.pad(card,16,16,16,16);card.setBackground(u.round(u.surface,18));
        card.addView(u.text(peer.optString("nickname","官网用户")+(data.optInt("unread")>0?"  ·  "+data.optInt("unread")+" 未读":""),16,u.text,true));u.space(card,7);TextView preview=u.text(last==null?"开始聊天":(last.optJSONObject("image")!=null?"[图片] ":"")+last.optString("text"),13,u.muted,false);preview.setMaxLines(2);preview.setEllipsize(TextUtils.TruncateAt.END);card.addView(preview);u.click(card,()->host.navigateNative("dmConversation","私信",peer.optLong("id")));parent.addView(card);u.space(parent,10);
    }
    void people(String query,int page){
        host.socialToolbar("选择收信人",host::reloadNative);if(!ready())return;Ui u=ui();LinearLayout body=host.content(),row=u.row();EditText input=edit("搜索昵称 / 直接输入 UID");input.setText(query);input.setSingleLine(true);row.addView(input,new LinearLayout.LayoutParams(0,u.dp(52),1));row.addView(u.button("查找",false,()->host.privateSearch(input.getText().toString().trim())),new LinearLayout.LayoutParams(-2,u.dp(48)));body.addView(row);u.space(body,14);
        body.addView(u.text("昵称可能重复，请核对 UID。仅已开通的用户可以收到消息。",12,u.muted,false));u.space(body,14);
        if(query.isEmpty())return;
        host.task(()->{if(query.matches("[1-9][0-9]{0,12}")){JSONObject data=host.client().get("user/info",ApiClient.params("id",query));return new JSONObject().put("data",new JSONArray().put(data.getJSONObject("data")));}return host.client().get("user/list",ApiClient.params("search",query,"page",String.valueOf(page),"per_page","20"));},response->{JSONArray all=response.optJSONArray("data");if(all==null||all.length()==0)body.addView(u.text("没有找到用户",14,u.muted,false));else for(int i=0;i<all.length();i++){JSONObject person=all.getJSONObject(i);long id=person.optLong("id");if(id==owner)continue;body.addView(u.button(person.optString("nickname")+"  ·  UID "+id,false,()->host.navigateNative("dmConversation","私信",id)));u.space(body,10);}JSONObject meta=response.optJSONObject("meta");if(meta!=null&&meta.optJSONObject("pagination")!=null)host.nativePagination(meta.getJSONObject("pagination"));},host::toast);
    }
    void conversation(long person){
        host.socialToolbar("私信",host::reloadNative);if(!ready())return;
        if(person<=0||person==owner){host.content().addView(ui().text("请选择其他用户",15,ui().muted,false));return;}
        if(peerId!=person){saveDraft();peerId=person;messages.clear();cursor=lastRead=0;loaded=false;hasOlder=false;peerName="";}
        long requested=serial;String secret=token;status=ui().text("正在确认收信人…",13,ui().muted,false);host.content().addView(status);
        host.task(()->request("/dm/v1/peer?id="+person,null,secret),response->{
            if(!current(requested))return;JSONObject peer=response.optJSONObject("user");
            if(!response.optBoolean("available")||peer==null){status.setText("这位作者尚未开通 APP 私信，暂时无法收信。");host.content().addView(ui().button("查看作者主页",false,()->host.navigateNative("profile","作者主页",person)));return;}
            peerName=peer.optString("nickname","官网用户");peerAvatar=peer.optString("avatar");buildConversation();loadMessages(false);
        },message->{if(current(requested))fail(message);});
    }
    private void buildConversation(){
        Ui u=ui();LinearLayout panel=u.column();u.pad(panel,16,10,16,6);LinearLayout row=u.row();TextView author=u.text(peerName+" · UID "+peerId,15,u.text,true);u.click(author,()->host.navigateNative("profile","作者主页",peerId));row.addView(author,new LinearLayout.LayoutParams(0,-2,1));row.addView(u.button("拒收",false,()->block(peerId,true)),new LinearLayout.LayoutParams(-2,u.dp(42)));panel.addView(row);
        status=u.text("正在同步 · 仅在前台接收",11,u.muted,false);u.pad(status,0,8,0,8);panel.addView(status);
        timeline=new ScrollView(host);timeline.setFillViewport(true);thread=u.column();timeline.addView(thread,new ScrollView.LayoutParams(-1,-2));panel.addView(timeline,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout tools=u.row();photo=u.button(images.containsKey(peerId)?"图片已添加 · 点击更换":"＋ 图片",false,this::pickImage);tools.addView(photo);if(images.containsKey(peerId))tools.addView(u.button("移除",false,()->{Pending in=pending.get(peerId);if(in!=null&&in.inFlight)return;saveDraft();images.remove(peerId);buildConversation();}));panel.addView(tools);
        LinearLayout compose=u.row();composer=edit("给 "+peerName+" 留言…");composer.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);composer.setMinLines(1);composer.setMaxLines(4);composer.setFilters(new InputFilter[]{new InputFilter.LengthFilter(1000)});composer.setText(drafts.getOrDefault(peerId,""));compose.addView(composer,new LinearLayout.LayoutParams(0,-2,1));send=u.button("发送",true,this::send);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(u.dp(72),u.dp(48));p.leftMargin=u.dp(8);compose.addView(send,p);panel.addView(compose);host.chatContent(panel);drawMessages(true,false);updateComposer();
    }
    private EditText edit(String hint){Ui u=ui();EditText input=new EditText(host);input.setHint(hint);input.setTextSize(15);input.setTextColor(u.text);input.setHintTextColor(u.muted);input.setBackground(u.round(u.surface,16));u.pad(input,14,10,14,10);return input;}
    private void loadMessages(boolean older){
        if(!live()||thread==null||composer==null||loading||loadingOlder)return;
        if(older&&(messages.isEmpty()||messages.size()>=300))return;
        if(older)loadingOlder=true;else loading=true;long requested=serial,person=peerId;String secret=token;
        String path="/dm/v1/messages?peer="+person+"&limit=30"+(older?"&before="+messages.firstKey():loaded?"&after="+cursor:"");
        host.task(()->request(path,null,secret),response->{
            if(!current(requested)||person!=peerId)return;loading=loadingOlder=false;JSONArray all=response.optJSONArray("messages");boolean initial=!loaded;
            if(all!=null)for(int i=0;i<all.length();i++)merge(all.getJSONObject(i));
            if(older||initial)hasOlder=response.optBoolean("has_older");loaded=true;
            while(messages.size()>300){if(older)messages.pollLastEntry();else messages.pollFirstEntry();}
            cursor=Math.max(cursor,response.optLong("cursor"));status.setText("已同步 · 历史保留7天 · 前台每20秒检查新消息");drawMessages(initial,older);updateComposer();markRead();
            later();if(!older&&response.optBoolean("has_more")){main.removeCallbacks(poll);main.postDelayed(poll,1000);}
        },message->{if(current(requested)){loading=loadingOlder=false;fail(message);}});
    }
    private void merge(JSONObject message){
        long sender=message.optLong("sender_id"),recipient=message.optLong("recipient_id");
        if(!((sender==owner&&recipient==peerId)||(sender==peerId&&recipient==owner)))return;
        // Only fetched batches advance the receive cursor. A send acknowledgement may
        // have a later ID than incoming messages that have not been polled yet.
        messages.put(message.optLong("id"),message);Pending p=pending.get(peerId);
        if(p!=null&&sender==owner&&p.nonce.equals(message.optString("client_id"))){pending.remove(peerId);boolean sameImage=(images.containsKey(peerId)?images.get(peerId).optString("id"):"").equals(p.image);if(sameImage){images.remove(peerId);if(photo!=null)photo.setText("＋ 图片");}if(sameImage&&composer!=null&&composer.getText().toString().trim().equals(p.text))composer.setText("");drafts.put(peerId,composer==null?"":composer.getText().toString());}
    }
    private void drawMessages(boolean bottom,boolean older){
        if(thread==null||timeline==null)return;Ui u=ui();int y=timeline.getScrollY(),height=thread.getHeight();boolean near=bottom||y+timeline.getHeight()>=height-u.dp(90);thread.removeAllViews();
        if(hasOlder&&messages.size()<300)thread.addView(u.button(loadingOlder?"正在加载…":"加载更早的私信",false,()->loadMessages(true)));
        if(messages.isEmpty()){TextView empty=u.text(loaded?"还没有消息，写下第一封信吧。":"正在载入私信…",14,u.muted,false);u.pad(empty,0,40,0,40);thread.addView(empty);}
        for(JSONObject message:messages.values()){
            boolean mine=message.optLong("sender_id")==owner;LinearLayout outer=u.column();outer.setGravity(mine?Gravity.RIGHT:Gravity.LEFT);u.pad(outer,0,9,0,8);
            LinearLayout author=u.row();ImageView avatar=new ImageView(host);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(u.round(u.soft,20));avatar.setClipToOutline(true);author.addView(avatar,new LinearLayout.LayoutParams(u.dp(34),u.dp(34)));host.pictures().into(mine?host.account().optString("avatar"):peerAvatar,avatar);
            TextView name=u.text((mine?host.account().optString("nickname"):peerName)+" · UID "+(mine?owner:peerId),12,u.accent,true);u.pad(name,8,0,0,0);name.setMaxLines(2);author.addView(name);outer.addView(author);outer.addView(u.text(time(message.optString("created_at")),10,u.muted,false));u.space(outer,5);
            if(message.optJSONObject("image")!=null)host.messageImages().image(outer,message.optJSONObject("image"),token);
            if(!message.optString("text").isEmpty()){TextView text=u.text(message.optString("text"),15,mine?android.graphics.Color.WHITE:u.text,false);text.setTextIsSelectable(true);u.pad(text,14,11,14,11);text.setBackground(u.round(mine?u.accent:u.surface,18));text.setMaxWidth(u.dp(Math.max(180,host.getResources().getConfiguration().screenWidthDp-80)));outer.addView(text);}thread.addView(outer);
        }
        ScrollView view=timeline;LinearLayout list=thread;long generation=serial;
        view.post(()->{if(!current(generation)||timeline!=view||thread!=list)return;if(older)view.scrollTo(0,Math.max(0,y+list.getHeight()-height));else if(near)view.fullScroll(View.FOCUS_DOWN);else view.scrollTo(0,y);});
    }
    private String time(String iso){try{return java.time.Instant.parse(iso).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm"));}catch(Exception e){return "";}}
    private void updateComposer(){if(composer==null||send==null)return;Pending p=pending.get(peerId);boolean busy=p!=null&&p.inFlight;composer.setEnabled(!busy);send.setEnabled(!busy&&!token.isEmpty());if(photo!=null)photo.setEnabled(!busy);send.setText(busy?"发送中":p==null?"发送":"重试");}
    private void pickImage(){
        if(!live())return;long person=peerId,account=owner;host.messageImages().pick("dm",String.valueOf(person),token,()->active&&owner==account&&peerId==person&&host.currentKind().equals("dmConversation"),image->{saveDraft();images.put(person,image);buildConversation();});
    }
    private void send(){
        if(!live()||composer==null)return;String text=composer.getText().toString().trim();String image=images.containsKey(peerId)?images.get(peerId).optString("id"):"";if(text.isEmpty()&&image.isEmpty())return;if(text.codePointCount(0,text.length())>500){host.toast("每条私信最多500字");return;}
        Pending p=pending.get(peerId);if(p!=null&&p.inFlight)return;if(p==null||!p.text.equals(text)||!p.image.equals(image)){p=new Pending(text,image);pending.put(peerId,p);}p.inFlight=true;updateComposer();Pending attempt=p;long person=peerId,requested=serial;String secret=token;drafts.put(person,text);
        host.task(()->request("/dm/v1/messages",new JSONObject().put("peer_id",person).put("text",attempt.text).put("client_id",attempt.nonce).put("image_id",attempt.image),secret),response->{
            if(!current(requested)||person!=peerId)return;attempt.inFlight=false;merge(response.getJSONObject("message"));drawMessages(true,false);updateComposer();status.setText("已发送");main.removeCallbacks(poll);main.post(poll);
        },message->{attempt.inFlight=false;if(current(requested)&&person==peerId){if(message.startsWith("私信身份已过期")){fail(message);return;}status.setText(message+" · 点击重试不会重复发送");updateComposer();}});
    }
    private void markRead(){
        if(!live()||messages.isEmpty())return;long received=0;for(JSONObject m:messages.values())if(m.optLong("recipient_id")==owner)received=Math.max(received,m.optLong("id"));if(received<=lastRead)return;
        long id=received,person=peerId,requested=serial;String secret=token;host.task(()->request("/dm/v1/read",new JSONObject().put("peer_id",person).put("last_id",id),secret),r->{if(current(requested)&&person==peerId)lastRead=Math.max(lastRead,id);},m->{});
    }
    private void block(long person,boolean blocked){
        new AlertDialog.Builder(host).setTitle(blocked?"拒收这位用户的私信？":"允许这位用户发送私信？").setMessage(blocked?"拒收后双方均无法继续发送私信。你可以在拒收名单中解除。":"解除后可以继续互相发送私信。").setNegativeButton("取消",null).setPositiveButton("确定",(d,w)->{String secret=token;host.task(()->request("/dm/v1/block",new JSONObject().put("peer_id",person).put("blocked",blocked),secret),r->{host.toast(blocked?"已拒收":"已解除拒收");host.reloadNative();},this::fail);}).show();
    }
    void blocks(){
        host.socialToolbar("私信设置",host::reloadNative);if(!ready())return;Ui u=ui();LinearLayout body=host.content();body.addView(u.text("拒收名单",21,u.text,true));u.space(body,12);String secret=token;
        host.task(()->request("/dm/v1/blocks",null,secret),r->{JSONArray a=r.optJSONArray("users");if(a==null||a.length()==0)body.addView(u.text("尚未拒收任何人",14,u.muted,false));else for(int i=0;i<a.length();i++){JSONObject peer=a.getJSONObject(i);body.addView(u.button(peer.optString("nickname")+" · 解除拒收",false,()->block(peer.optLong("id"),false)));u.space(body,8);}},this::fail);
        u.space(body,20);body.addView(u.text("消息保留7天。每条最多500字，3秒间隔，每分钟15条、每天100条，独立服务每天共2000条。每日最多联系10位新收信人。图片与聊天室共用：每账号每天10张、全站100张上传额度；每张自动压缩，发出后保留7天。额度北京时间08:00重置。",12,u.muted,false));u.space(body,18);
        body.addView(u.button("退出本机私信身份",false,()->new AlertDialog.Builder(host).setTitle("退出私信身份？").setMessage("会清除本机令牌。私信仍按7天保留规则处理，之后可重新验证开通。").setNegativeButton("取消",null).setPositiveButton("退出",(d,w)->{resetAccount();host.reloadNative();}).show()));
    }
}
