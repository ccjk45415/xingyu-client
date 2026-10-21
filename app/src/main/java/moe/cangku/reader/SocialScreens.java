package moe.cangku.reader;

import android.app.AlertDialog;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import org.json.*;
import java.util.*;

/** Native website comments and notifications. Writes happen only after an explicit user action. */
final class SocialScreens {
    private final MainActivity host;
    private long generation;
    private long focusPost, focusId;
    private JSONObject focusSeed;
    private final WeakHashMap<LinearLayout,Long> requests=new WeakHashMap<>();
    private long requestNumber;
    private long request(LinearLayout view){long n=++requestNumber;requests.put(view,n);return n;}
    private boolean latest(LinearLayout view,long n){return Objects.equals(requests.get(view),n);}
    SocialScreens(MainActivity host){this.host=host;}
    private Ui ui(){return host.design();}
    private long uid(){return host.account()==null?0:host.account().optLong("id");}
    private boolean muted(){return host.account()!=null&&(host.account().optBoolean("is_muted")||host.account().optBoolean("is_banned"));}
    private AlertDialog.Builder dialog(){return new AlertDialog.Builder(new android.view.ContextThemeWrapper(host,ui().dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert));}
    private boolean current(long token){return token==generation;}
    private static JSONObject object(JSONObject x,String name){JSONObject o=x==null?null:x.optJSONObject(name);return o==null?new JSONObject():o;}
    private static JSONObject pagination(JSONObject x){return object(object(x,"meta"),"pagination");}
    private static JSONArray data(JSONObject x){JSONArray a=x==null?null:x.optJSONArray("data");return a==null?new JSONArray():a;}
    private String name(JSONObject user){String s=user.optString("nickname","");return s.isEmpty()?"已注销用户":s;}
    private String date(String raw){return raw.replace('T',' ').replace(".000000Z","").replace("Z","");}
    private void note(LinearLayout target,String text){TextView v=ui().text(text,13,ui().muted,false);ui().pad(v,4,12,4,12);target.addView(v);}
    private void loading(LinearLayout target){target.removeAllViews();ProgressBar p=new ProgressBar(host);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(ui().dp(30),ui().dp(30));lp.gravity=Gravity.CENTER;lp.topMargin=ui().dp(16);lp.bottomMargin=ui().dp(16);target.addView(p,lp);}
    private void fail(LinearLayout target,String error,Runnable retry){target.removeAllViews();note(target,error);target.addView(ui().button("重新载入",false,retry));}
    private LinearLayout card(LinearLayout target,boolean child){LinearLayout box=ui().column();ui().pad(box,child?12:16,14,child?12:16,14);box.setBackground(ui().round(child?ui().soft:ui().surface,18));target.addView(box,new LinearLayout.LayoutParams(-1,-2));ui().space(target,12);return box;}

    void attachArticle(JSONObject post,LinearLayout parent){
        long token=++generation;long id=post.optLong("id");
        ui().space(parent,22);parent.addView(ui().text("作品评论",21,ui().text,true));ui().space(parent,12);
        LinearLayout panel=ui().column();parent.addView(panel,new LinearLayout.LayoutParams(-1,-2));
        rootPanel(panel,id,post.optBoolean("is_locked"),1,5,false,token);
    }
    void comments(long post,int page,long focus){
        long token=++generation;host.socialToolbar("作品评论",()->host.reloadNative());
        LinearLayout panel=ui().column();host.content().addView(panel,new LinearLayout.LayoutParams(-1,-2));loading(panel);
        host.task(()->host.client().get("post/info",ApiClient.params("id",String.valueOf(post),"exclude_view","1")).getJSONObject("data"),p->{
            if(!current(token))return;
            if(focus>0&&focus==focusId&&post==focusPost&&focusSeed!=null)focusPanel(panel,p,focusSeed,token);
            else {if(focus>0)host.toast("该评论的定位信息已失效，已打开作品评论");rootPanel(panel,post,p.optBoolean("is_locked"),page,20,true,token);}
        },error->{if(current(token))fail(panel,error,()->host.reloadNative());});
    }
    private void rootPanel(LinearLayout panel,long post,boolean locked,int page,int perPage,boolean full,long token){
        long request=request(panel);panel.removeAllViews();
        if(locked)note(panel,"作者已关闭这篇作品的评论。");
        else if(muted())note(panel,"当前账号暂时无法发言。");
        else {panel.addView(ui().button("写评论  ✎",false,()->compose(post,0,0,locked,()->rootPanel(panel,post,locked,1,perPage,full,token))));ui().space(panel,12);}
        LinearLayout list=ui().column();panel.addView(list,new LinearLayout.LayoutParams(-1,-2));loading(list);
        Map<String,String> params=commentParams(post,0,page,perPage);
        host.task(()->withLikes(host.client().get("comment/list",params)),result->{
            if(!current(token)||!latest(panel,request))return;list.removeAllViews();JSONArray rows=data(result);
            if(rows.length()==0)note(list,"还没有评论，留下第一份想法吧。");
            Runnable refresh=()->rootPanel(panel,post,locked,page,perPage,full,token);
            for(int i=0;i<rows.length();i++){JSONObject c=rows.optJSONObject(i);if(c!=null)commentCard(list,c,post,locked,false,token,refresh);}
            JSONObject pg=pagination(result);
            if(full&&pg.optInt("total_pages",1)>1){
                int now=pg.optInt("current_page",page),total=pg.optInt("total_pages",1);LinearLayout nav=ui().row();
                TextView prev=ui().button("上一页",false,()->rootPanel(panel,post,locked,now-1,perPage,true,token));prev.setEnabled(now>1);nav.addView(prev,new LinearLayout.LayoutParams(0,-2,1));
                nav.addView(ui().text(now+" / "+total,12,ui().muted,false));TextView next=ui().button("下一页",false,()->rootPanel(panel,post,locked,now+1,perPage,true,token));next.setEnabled(now<total);nav.addView(next,new LinearLayout.LayoutParams(0,-2,1));panel.addView(nav);
            }
            if(!full){ui().space(panel,4);panel.addView(ui().button("查看全部评论  ·  "+pg.optInt("total",rows.length()),false,()->host.openComment(post,0)));}
        },error->{if(current(token)&&latest(panel,request))fail(list,error,()->rootPanel(panel,post,locked,page,perPage,full,token));});
    }
    private Map<String,String> commentParams(long post,long root,int page,int count){
        Map<String,String> p=ApiClient.params("post_id",String.valueOf(post),"parent_id",String.valueOf(root),"page",String.valueOf(Math.max(1,page)),"per_page",String.valueOf(count),"order_by","created_at","order",root==0?"desc":"asc");
        if(root==0){p.put("include","children:include(user):per_page(6),user");p.put("with[0]","children");p.put("with[1]","user");p.put("sticky","1");}
        else {p.put("include","user");p.put("with[0]","user");}
        return p;
    }
    /** Fetch the exact website upvote state before enabling a toggle. A failed lookup never guesses. */
    private JSONObject withLikes(JSONObject response){
        ArrayList<JSONObject> comments=new ArrayList<>();collect(data(response),comments);
        if(uid()==0||comments.isEmpty())return response;
        try{
            Map<String,String> p=ApiClient.params("relation","upvote","type","comment");int n=0;for(JSONObject c:comments)p.put("ids["+(n++)+"]",String.valueOf(c.optLong("id")));
            JSONArray liked=host.client().get("user/followableIdList",p).optJSONArray("data");
            if(liked==null)return response;Set<Long> ids=new HashSet<>();for(int i=0;i<liked.length();i++)ids.add(liked.optLong(i));
            for(JSONObject c:comments){c.put("_likeKnown",true);c.put("_liked",ids.contains(c.optLong("id")));}
        }catch(Exception ignored){}return response;
    }
    private void collect(JSONArray rows,List<JSONObject> out){for(int i=0;i<rows.length();i++){JSONObject c=rows.optJSONObject(i);if(c==null)continue;out.add(c);collect(data(c.optJSONObject("children")),out);}}
    private void commentCard(LinearLayout target,JSONObject c,long post,boolean locked,boolean child,long token,Runnable refresh){
        LinearLayout box=card(target,child);JSONObject author=object(c,"user");LinearLayout header=ui().row();
        TextView who=ui().text(name(author),14,ui().accent,true);header.addView(who,new LinearLayout.LayoutParams(0,-2,1));
        if(author.optLong("id")>0)ui().click(who,()->host.navigateNative("profile","作者主页",author.optLong("id")));
        header.addView(ui().text(date(c.optString("created_at")),10,ui().muted,false));box.addView(header);ui().space(box,8);
        if(c.optBoolean("is_sticky"))note(box,"置顶评论");
        JSONObject replyUser=object(object(c,"reply_to_meta"),"user");if(replyUser.optLong("id")>0)box.addView(ui().text("回复 @"+name(replyUser),12,ui().muted,false));
        host.renderHtml(box,c.optString("content"),15);ui().space(box,6);
        LinearLayout actions=ui().row();TextView like=ui().button(likeLabel(c),false,()->{});like.setEnabled(c.optBoolean("_likeKnown"));
        // A dedicated listener keeps the toggle disabled while its request is outstanding.
        like.setOnClickListener(v->{if(!c.optBoolean("_likeKnown"))return;boolean was=c.optBoolean("_liked");like.setEnabled(false);
            host.task(()->host.client().post(was?"comment/unvote":"comment/vote",new JSONObject().put("id",c.optLong("id"))),r->{
                if(!current(token))return;try{c.put("_liked",!was);c.put("vote_count",Math.max(0,c.optInt("vote_count")+(was?-1:1)));}catch(JSONException ignored){}
                like.setText(likeLabel(c));like.setEnabled(true);
            },error->{if(current(token)){like.setEnabled(true);host.toast(error);}});
        });actions.addView(like,new LinearLayout.LayoutParams(0,-2,1));
        if(!locked&&!muted()){long root=SocialRules.rootId(c.optLong("id"),c.optLong("parent_id"));TextView reply=ui().button("回复",false,()->compose(post,root,c.optLong("id"),locked,refresh));actions.addView(reply,new LinearLayout.LayoutParams(0,-2,1));}
        if(SocialRules.ownComment(uid(),c.optLong("user_id")))actions.addView(ui().button("删除",false,()->delete(c,refresh)),new LinearLayout.LayoutParams(0,-2,1));box.addView(actions);
        if(!child){JSONObject children=c.optJSONObject("children");JSONArray rows=data(children);LinearLayout replies=ui().column();box.addView(replies,new LinearLayout.LayoutParams(-1,-2));
            for(int i=0;i<rows.length();i++){JSONObject reply=rows.optJSONObject(i);if(reply!=null)commentCard(replies,reply,post,locked,true,token,refresh);}
            JSONObject pg=pagination(children);if(pg.optInt("total")>rows.length()){TextView all=ui().button("查看全部 "+pg.optInt("total")+" 条回复",false,()->loadChildren(replies,post,c.optLong("id"),locked,1,token,refresh));replies.addView(all);}
        }
    }
    private String likeLabel(JSONObject c){return (c.optBoolean("_liked")?"已赞 ":"赞 ")+c.optInt("vote_count");}
    private void loadChildren(LinearLayout panel,long post,long root,boolean locked,int page,long token,Runnable refresh){
        long request=request(panel);loading(panel);host.task(()->withLikes(host.client().get("comment/list",commentParams(post,root,page,6))),result->{
            if(!current(token)||!latest(panel,request))return;panel.removeAllViews();JSONArray rows=data(result);if(rows.length()==0)note(panel,"暂无回复，或回复已被删除。");
            for(int i=0;i<rows.length();i++){JSONObject c=rows.optJSONObject(i);if(c!=null)commentCard(panel,c,post,locked,true,token,refresh);}
            JSONObject pg=pagination(result);int now=pg.optInt("current_page",page),total=pg.optInt("total_pages",1);if(total>1){LinearLayout nav=ui().row();
                TextView prev=ui().button("上一页",false,()->loadChildren(panel,post,root,locked,now-1,token,refresh));prev.setEnabled(now>1);nav.addView(prev,new LinearLayout.LayoutParams(0,-2,1));
                nav.addView(ui().text(now+" / "+total,12,ui().muted,false));TextView next=ui().button("下一页",false,()->loadChildren(panel,post,root,locked,now+1,token,refresh));next.setEnabled(now<total);nav.addView(next,new LinearLayout.LayoutParams(0,-2,1));panel.addView(nav);}
        },error->{if(current(token)&&latest(panel,request))fail(panel,error,()->loadChildren(panel,post,root,locked,page,token,refresh));});
    }
    private void compose(long post,long parent,long reply,boolean locked,Runnable refresh){
        if(locked||muted()){host.toast("当前无法发表评论");return;}long token=generation;
        EditText input=new EditText(host);input.setTextColor(ui().text);input.setHintTextColor(ui().muted);input.setTextSize(15);input.setHint(parent>0?"写下你的回复…":"写下你的评论…");input.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE);input.setMinLines(4);input.setMaxLines(10);input.setGravity(Gravity.TOP);input.setFilters(new InputFilter[]{new InputFilter.LengthFilter(5000)});
        LinearLayout wrap=ui().column();ui().pad(wrap,20,12,20,4);wrap.addView(input,new LinearLayout.LayoutParams(-1,ui().dp(170)));
        AlertDialog d=dialog().setTitle(parent>0?"回复评论":"发表评论").setView(wrap).setNegativeButton("取消",null).setPositiveButton("发布",null).create();
        d.setOnShowListener(x->d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{String text=input.getText().toString().trim();if(text.isEmpty()){input.setError("请输入内容");return;}d.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);d.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);d.setCancelable(false);
            host.task(()->{JSONObject body=new JSONObject().put("post_id",post).put("content",text).put("include","user");if(parent>0)body.put("parent_id",parent).put("reply_to_id",reply);return host.client().post("comment/create",body);},result->{d.dismiss();if(current(token)){host.toast("评论已发布");refresh.run();}},error->{if(!d.isShowing())return;d.setCancelable(true);d.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);d.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(true);host.toast(error);});
        }));d.show();
    }
    private void delete(JSONObject c,Runnable refresh){
        if(!SocialRules.ownComment(uid(),c.optLong("user_id")))return;long token=generation;
        AlertDialog d=dialog().setTitle("删除这条评论？").setMessage("删除后无法恢复。只能管理自己发布的评论。").setNegativeButton("取消",null).setPositiveButton("删除",null).create();
        d.setOnShowListener(x->d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{d.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);d.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);d.setCancelable(false);
            host.task(()->host.client().post("comment/delete",new JSONObject().put("id",c.optLong("id"))),r->{d.dismiss();if(current(token)){host.toast("评论已删除");if(focusSeed!=null&&(focusId==c.optLong("id")||focusSeed.optLong("parent_id")==c.optLong("id"))){long post=focusPost;focusSeed=null;focusId=0;host.openComment(post,0);}else refresh.run();}},e->{if(!d.isShowing())return;d.setCancelable(true);d.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);d.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(true);host.toast(e);});
        }));d.show();
    }
    void mineComments(int page){
        long token=++generation;host.socialToolbar("我的评论",()->host.reloadNative());note(host.content(),"与官网同步。可以查看原文、定位回复，或删除自己的评论。");
        LinearLayout list=ui().column();host.content().addView(list,new LinearLayout.LayoutParams(-1,-2));loading(list);
        Map<String,String> params=ApiClient.params("id",String.valueOf(uid()),"page",String.valueOf(page),"per_page","20","include","post:simple,user","with[0]","post","with[1]","user");
        host.task(()->host.client().get("user/comment",params),result->{if(!current(token))return;list.removeAllViews();JSONArray rows=data(result);int count=0;
            for(int i=0;i<rows.length();i++){JSONObject c=rows.optJSONObject(i);if(c==null||c.optLong("user_id")!=uid())continue;count++;JSONObject post=object(c,"post");LinearLayout box=card(list,false);
                TextView title=ui().text(post.optString("title","原作品已删除或不可见"),16,ui().text,true);box.addView(title);if(post.optLong("id")>0)ui().click(title,()->host.navigateNative("article","作品详情",post.optLong("id")));
                note(box,date(c.optString("created_at"))+"  ·  "+(c.optLong("parent_id")>0?"回复":"评论")+"  ·  "+c.optInt("vote_count")+" 赞");host.renderHtml(box,c.optString("content"),15);ui().space(box,8);
                LinearLayout actions=ui().row();TextView view=ui().button("查看讨论",false,()->openFocused(c,c.optLong("post_id")));view.setEnabled(post.optLong("id")>0);actions.addView(view,new LinearLayout.LayoutParams(0,-2,1));actions.addView(ui().button("删除评论",false,()->delete(c,()->host.reloadNative())),new LinearLayout.LayoutParams(0,-2,1));box.addView(actions);
            }if(count==0)note(list,"还没有发布过评论。");JSONObject pg=pagination(result);if(pg.length()>0)host.nativePagination(pg);
        },error->{if(current(token))fail(list,error,()->host.reloadNative());});
    }
    private void openFocused(JSONObject c,long post){if(post<=0||c==null||c.optLong("id")<=0){host.toast("原内容已删除或暂不可见");return;}focusPost=post;focusId=c.optLong("id");focusSeed=c;host.openComment(post,focusId);}
    private void focusPanel(LinearLayout panel,JSONObject post,JSONObject seed,long token){
        panel.removeAllViews();long id=post.optLong("id");boolean locked=post.optBoolean("is_locked");note(panel,"已定位到评论 #"+seed.optLong("id")+"。以下显示这条评论及所在讨论的回复。");panel.addView(ui().button("查看作品全部评论",false,()->host.openComment(id,0)));ui().space(panel,12);
        LinearLayout focused=ui().column();panel.addView(focused);Runnable refresh=()->host.reloadNative();
        // A seed from a notification lacks user data; its actor is attached before navigation.
        commentCard(focused,seed,id,locked,true,token,refresh);long root=SocialRules.rootId(seed.optLong("id"),seed.optLong("parent_id"));
        note(panel,"讨论回复");LinearLayout replies=ui().column();panel.addView(replies);loadChildren(replies,id,root,locked,1,token,refresh);
        // Resolve the target's like state independently from the discussion list.
        host.task(()->withLikes(new JSONObject().put("data",new JSONArray().put(seed))),r->{if(!current(token))return;focused.removeAllViews();commentCard(focused,seed,id,locked,true,token,refresh);},error->{});
    }

    void loadMineBadge(TextView label){
        host.task(()->host.client().get("user/unreadNotificationCount",null).getJSONObject("data"),counts->{int n=counts.optInt("reply")+counts.optInt("vote")+counts.optInt("system");label.setText(n>0?"通知  ·  "+(n>99?"99+":n)+" 条未读":"暂无未读通知");},error->label.setText("通知数量暂时无法同步，进入通知页可重试"));
    }
    void notifications(String kind,int page){
        final String type=Arrays.asList("reply","vote","system").contains(kind)?kind:"reply";long token=++generation;host.socialToolbar("通知",()->host.reloadNative());
        LinearLayout tabs=ui().row();String[] keys={"reply","vote","system"},labels={"回复","点赞","系统"};TextView[] chips=new TextView[3];
        for(int i=0;i<3;i++){String key=keys[i];TextView chip=ui().chip(labels[i],type.equals(key),()->host.socialFilter(key));chips[i]=chip;LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);lp.setMargins(0,0,ui().dp(5),0);tabs.addView(chip,lp);}host.content().addView(tabs);ui().space(host.content(),12);
        TextView markAll=ui().button("将本分类全部标为已读",false,()->markAll(type));host.content().addView(markAll);note(host.content(),type.equals("system")?"系统公告使用上方按钮统一标为已读。打开列表不会自动修改未读状态。":"打开列表不会自动标为已读。查看讨论或使用已读按钮后同步到官网。");
        LinearLayout list=ui().column();host.content().addView(list,new LinearLayout.LayoutParams(-1,-2));loading(list);
        host.task(()->host.client().get("user/unreadNotificationCount",null).getJSONObject("data"),counts->{if(current(token))for(int i=0;i<3;i++)chips[i].setText(labels[i]+(counts.optInt(keys[i])>0?" ("+counts.optInt(keys[i])+")":""));},error->{});
        Map<String,String> p=ApiClient.params("page",String.valueOf(page),"per_page","12");if(!type.equals("system")){p.put("action",type);p.put("include","user,causer,subject");p.put("with[0]","user");p.put("with[1]","causer");p.put("with[2]","subject");}
        host.task(()->host.client().get(type.equals("system")?"announce/list":"user/notification",p),result->{if(!current(token))return;list.removeAllViews();JSONArray rows=data(result);if(rows.length()==0)note(list,"暂时没有这类通知。");
            for(int i=0;i<rows.length();i++){JSONObject n=rows.optJSONObject(i);if(n==null)continue;if(type.equals("system"))announcement(list,n);else notification(list,n,type,token);}
            JSONObject pg=pagination(result);if(pg.length()>0)host.nativePagination(pg);
        },error->{if(current(token))fail(list,error,()->host.reloadNative());});
    }
    private void announcement(LinearLayout list,JSONObject n){LinearLayout box=card(list,false);box.addView(ui().text(n.optString("title","系统公告"),17,ui().text,true));note(box,date(n.optString("created_at")));host.renderHtml(box,n.optString("content"),14);}
    private void notification(LinearLayout list,JSONObject n,String type,long token){
        LinearLayout box=card(list,false);JSONObject actor=object(n,"user"),subject=object(n,"subject"),causer=object(n,"causer");boolean unread=n.isNull("read_at")||n.optString("read_at").isEmpty();
        boolean subjectPost=n.optString("subject_type").equals("post");
        String action=type.equals("vote")?(subjectPost?"赞了你的作品":"赞了你的评论"):n.optString("subject_type").equals("post")?"回复了你的作品":"回复了你的评论";
        TextView heading=ui().text((unread?"● ":"")+name(actor)+" "+action,15,ui().text,true);box.addView(heading);note(box,date(n.optString("created_at")));
        if(actor.optLong("id")>0)ui().click(heading,()->host.navigateNative("profile","作者主页",actor.optLong("id")));
        if(!type.equals("vote")){if(causer.optLong("id")>0)host.renderHtml(box,causer.optString("content"),15);else note(box,"这条回复已删除或不可见。");}
        if(subject.optLong("id")>0){LinearLayout quote=ui().column();ui().pad(quote,12,10,12,10);quote.setBackground(ui().round(ui().soft,12));quote.addView(ui().text(type.equals("vote")?(subjectPost?"我的作品":"我的评论"):"原内容",11,ui().muted,true));String text=subject.optString("title","");if(text.isEmpty())text=subject.optString("content");host.renderHtml(quote,text,13);box.addView(quote);}else note(box,"原内容已删除或不可见。");
        ui().space(box,10);LinearLayout actions=ui().row();JSONObject target=type.equals("vote")?subject:causer;
        long post=SocialRules.notificationPostId(n.optString("subject_type"),subject.optLong("id"),subject.optLong("post_id"));
        boolean articleVote=type.equals("vote")&&subjectPost;long targetId=SocialRules.notificationCommentId(type,n.optString("subject_type"),subject.optLong("id"),causer.optLong("id"));
        TextView view=ui().button(articleVote?"查看作品":"查看讨论",false,()->{});
        view.setOnClickListener(v->{view.setEnabled(false);markOne(n,type,()->{if(type.equals("vote")&&subjectPost){host.navigateNative("article","作品详情",post);return;}try{target.put("user",type.equals("vote")?host.account():actor);}catch(JSONException ignored){}openFocused(target,post);},token,()->view.setEnabled(true));});view.setEnabled(post>0&&(articleVote||(targetId>0&&target.optLong("id")==targetId)));actions.addView(view,new LinearLayout.LayoutParams(0,-2,1));
        if(unread){TextView read=ui().button("标为已读",false,()->{});read.setOnClickListener(v->{read.setEnabled(false);markOne(n,type,()->{read.setText("已读");heading.setText(name(actor)+" "+action);},token,()->read.setEnabled(true));});actions.addView(read,new LinearLayout.LayoutParams(0,-2,1));}box.addView(actions);
    }
    private void markOne(JSONObject n,String type,Runnable done,long token){markOne(n,type,done,token,()->{});}
    private void markOne(JSONObject n,String type,Runnable done,long token,Runnable failed){
        if(!n.isNull("read_at")&&!n.optString("read_at").isEmpty()){done.run();return;}
        host.task(()->host.client().post("user/makeNotificationAsRead",new JSONObject().put("ids",new JSONArray().put(n.optString("id"))).put("action",type)),r->{if(current(token)){try{n.put("read_at","read");}catch(JSONException ignored){}done.run();}},e->{if(current(token)){failed.run();host.toast(e);}});
    }
    private void markAll(String type){
        long token=generation;dialog().setTitle("全部标为已读？").setMessage("将同步更新官网中本分类的未读状态。").setNegativeButton("取消",null).setPositiveButton("标为已读",(d,w)->host.task(()->host.client().post(type.equals("system")?"user/makeAnnounceAsRead":"user/makeNotificationAsRead",type.equals("system")?new JSONObject():new JSONObject().put("all",true).put("action",type)),r->{if(current(token)){host.toast("已标为已读");host.reloadNative();}},host::toast)).show();
    }
}
