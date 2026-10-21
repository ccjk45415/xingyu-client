package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.net.Uri;
import android.os.*;
import android.text.*;
import android.text.method.LinkMovementMethod;
import android.text.style.*;
import android.view.*;
import android.view.inputmethod.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    private ApiClient api;
    private ImageLoader images;
    private LocalLibrary library;
    private Ui ui;
    private final ExecutorService network=Executors.newFixedThreadPool(3);
    private final Handler main=new Handler(Looper.getMainLooper());
    private final Deque<Route> history=new ArrayDeque<>();
    private JSONObject user;
    private JSONArray categories=new JSONArray();
    private LinearLayout root,body,top,bottom;
    private ScrollView scroll;
    private Route route=new Route("home","发现");
    private int epoch;
    private long pendingArticle;
    private boolean closed;
    private AuthoringScreens authoring;
    private ChatScreens chat;
    private AppUpdates updates;
    private SocialScreens social;
    private PrivateScreens direct;
    private HomeCarousel carousel;
    private MessageImages messageImages;
    private VerifiedProfileSync profileSync;
    private boolean qrBusy;
    private static final class Route {
        String kind,title,query="",period="daily";long id;int page=1,scrollY;
        Route(String k,String t){kind=k;title=t;}
        Route id(long value){id=value;return this;}
        Route query(String value){query=value;return this;}
        Route copy(){Route r=new Route(kind,title);r.query=query;r.period=period;r.id=id;r.page=page;r.scrollY=scrollY;return r;}
    }
    interface Work<T>{T run()throws Exception;}
    interface Done<T>{void accept(T result)throws Exception;}
    @Override public void onCreate(Bundle state){
        super.onCreate(state);api=new ApiClient(this);images=new ImageLoader();library=new LocalLibrary(this);authoring=new AuthoringScreens(this);chat=new ChatScreens(this);updates=new AppUpdates(this);social=new SocialScreens(this);direct=new PrivateScreens(this);messageImages=new MessageImages(this);profileSync=new VerifiedProfileSync(this);
        if(state!=null){route.kind=state.getString("kind","home");route.title=state.getString("title","发现");route.id=state.getLong("id");route.query=state.getString("query","");route.period=state.getString("period","daily");route.page=state.getInt("page",1);}
        readIntent(getIntent());
        if(api.sessions.hasSession()){
            shell(false);loading("正在连接你的仓库…");
            task(()->api.get("auth/me",ApiClient.params("include","roles,permissions,meta")).getJSONObject("data"),u->{user=u;library.setUser(u.optLong("id"));enter();},e->{api.clear();login(e);});
        }else login("");
    }
    @Override protected void onSaveInstanceState(Bundle s){super.onSaveInstanceState(s);s.putString("kind",route.kind);s.putString("title",route.title);s.putLong("id",route.id);s.putString("query",route.query);s.putString("period",route.period);s.putInt("page",route.page);}
    @Override public void onConfigurationChanged(android.content.res.Configuration config){super.onConfigurationChanged(config);if(authoring!=null&&authoring.keepDuringConfig())return;if(user!=null){route.scrollY=scroll==null?0:scroll.getScrollY();render();}else login("");}
    @Override protected void onNewIntent(Intent i){super.onNewIntent(i);setIntent(i);readIntent(i);if(user!=null&&pendingArticle>0){go(new Route("article","文章").id(pendingArticle));pendingArticle=0;}}
    private void readIntent(Intent i){if(i!=null&&i.getData()!=null)pendingArticle=UrlPolicy.articleId(i.getData().toString());}
    private void enter(){
        history.clear();if(pendingArticle>0){route=new Route("article","文章").id(pendingArticle);pendingArticle=0;}
        render();loadCategories();
    }
    private void loadCategories(){
        network.execute(()->{try{JSONArray result=api.get("category/list",ApiClient.params("all","1","type","post")).getJSONArray("data");main.post(()->{categories=result;if(!closed&&route.kind.equals("categories"))render();});}catch(Exception ignored){}});
    }
    <T> void task(Work<T> work,Done<T> done,java.util.function.Consumer<String> error){
        int token=epoch;
        network.execute(()->{try{T value=work.run();main.post(()->{if(closed||token!=epoch)return;try{done.accept(value);}catch(Exception e){error.accept("数据格式发生变化，请重试");}});}catch(Exception e){main.post(()->{
            if(closed||token!=epoch)return;
            if(e instanceof ApiClient.ApiException&&user!=null&&(((ApiClient.ApiException)e).status==401||((ApiClient.ApiException)e).status==419||((ApiClient.ApiException)e).status==302||((ApiClient.ApiException)e).status==303)){
                authoring.suspend();chat.resetAccount();direct.resetAccount();if(messageImages!=null)messageImages.clear();api.clear();user=null;history.clear();login("登录已过期，请重新登录");return;
            }
            String message=e instanceof java.net.UnknownHostException?"网络连接失败，请检查网络后重试":e instanceof java.net.SocketTimeoutException?"连接超时，请稍后重试":e.getMessage();
            error.accept(message==null?"连接失败，请稍后重试":message);
        });}});
    }
    private void shell(boolean nav){
        if(messageImages!=null)messageImages.leavePage();
        if(chat!=null)chat.leavePage();
        if(direct!=null)direct.leavePage();
        if(carousel!=null){carousel.close();carousel=null;}
        epoch++;ui=new Ui(this,library.dark());
        getWindow().setStatusBarColor(android.graphics.Color.TRANSPARENT);getWindow().setNavigationBarColor(ui.bg);
        getWindow().getDecorView().setSystemUiVisibility(library.dark()?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        root=ui.column();root.setBackgroundColor(ui.bg);root.setFitsSystemWindows(false);
        root.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        top=ui.row();ui.pad(top,20,8,20,8);root.addView(top,new LinearLayout.LayoutParams(-1,ui.dp(64)));
        scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.setVerticalScrollBarEnabled(route.kind.equals("article"));scroll.setVerticalScrollbarPosition(View.SCROLLBAR_POSITION_RIGHT);scroll.setScrollbarFadingEnabled(false);scroll.setScrollBarStyle(View.SCROLLBARS_INSIDE_INSET);
        body=ui.column();ui.pad(body,20,12,20,24);scroll.addView(body,new ScrollView.LayoutParams(-1,-2));root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        bottom=ui.row();if(nav){bottom.setBackground(ui.round(ui.surface,24));ui.pad(bottom,8,6,8,5);root.addView(bottom,new LinearLayout.LayoutParams(-1,ui.dp(72)));navbar();}
        setContentView(root);root.requestApplyInsets();
    }
    void toolbar(String title,boolean back,Runnable refresh){
        if(back){top.addView(ui.iconButton("返回",this::back),new LinearLayout.LayoutParams(ui.dp(44),ui.dp(44)));}
        TextView heading=ui.text(title,23,ui.text,true);ui.pad(heading,back?12:0,0,0,0);heading.setMaxLines(1);heading.setEllipsize(TextUtils.TruncateAt.END);top.addView(heading,new LinearLayout.LayoutParams(0,-2,1));
        String icon=refresh==null?"搜索":"刷新";top.addView(ui.iconButton(icon,refresh==null?()->go(new Route("search","搜索")):refresh),new LinearLayout.LayoutParams(ui.dp(44),ui.dp(44)));
    }
    private void navbar(){
        String selected=route.kind.equals("home")?"home":route.kind.equals("categories")||route.kind.equals("category")?"categories":route.kind.equals("rank")?"rank":route.kind.equals("chat")?"chat":"mine";
        String[] names={"首页","分类","排行","聊天室","我的"},kinds={"home","categories","rank","chat","mine"};
        for(int i=0;i<names.length;i++){
            String name=names[i],kind=kinds[i];boolean active=selected.equals(kind);
            LinearLayout item=ui.column();item.setGravity(Gravity.CENTER);item.setContentDescription(name);
            FrameLayout iconSlot=new FrameLayout(this);iconSlot.addView(ui.icon(name,active?ui.accent:ui.muted),new FrameLayout.LayoutParams(ui.dp(24),ui.dp(24),Gravity.CENTER));item.addView(iconSlot,new LinearLayout.LayoutParams(ui.dp(28),ui.dp(28)));
            ui.space(item,3);TextView label=ui.text(name,11,active?ui.accent:ui.muted,active);label.setSingleLine(true);label.setIncludeFontPadding(false);label.setGravity(Gravity.CENTER);item.addView(label,new LinearLayout.LayoutParams(-1,ui.dp(17)));
            if(active)item.setBackground(ui.round(ui.soft,18));ui.click(item,()->authoring.leave(()->{history.clear();route=new Route(kind,name.equals("首页")?"发现":name);render();}));
            LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-1,1);p.setMargins(ui.dp(2),0,ui.dp(2),0);bottom.addView(item,p);
        }
    }
    private void go(Route next){authoring.leave(()->{route.scrollY=scroll==null?0:scroll.getScrollY();history.push(route.copy());route=next;render();});}
    private void back(){authoring.leave(()->{if(history.isEmpty()){if(!route.kind.equals("home")){route=new Route("home","发现");render();}else super.onBackPressed();}else{route=history.pop();render();}});}
    @Override public void onBackPressed(){back();}
    private void render(){
        shell(true);
        switch(route.kind){
            case "article":article();break;
            case "comments":social.comments(route.id,route.page,commentFocus());break;
            case "myComments":social.mineComments(route.page);break;
            case "notifications":social.notifications(route.period,route.page);break;
            case "privateMessages":direct.inbox();break;
            case "dmPeople":direct.people(route.query,route.page);break;
            case "dmConversation":direct.conversation(route.id);break;
            case "dmBlocks":direct.blocks();break;
            case "mine":mine();break;
            case "categories":categoryPage();break;
            case "search":search();break;
            case "history":toolbar("阅读足迹",true,()->render());showCards(library.history(),null);break;
            case "settings":settingsHub();break;
            case "appearance":settings();break;
            case "profile":profile();break;
            case "manage":authoring.manage(route.period,route.query,route.page);break;
            case "editor":authoring.editor(route.id);break;
            case "editProfile":authoring.profile();break;
            case "security":authoring.security();break;
            case "accountLogs":authoring.logs(route.page);break;
            case "chat":chat.show();break;
            default:feed();
        }
    }
    private void login(String message){
        if(chat!=null)chat.resetAccount();
        shell(false);top.addView(ui.text("CANGKU  /  星屿",14,ui.accent,true));
        FrameLayout banner=new FrameLayout(this);banner.addView(new Ui.Aurora(this),new FrameLayout.LayoutParams(-1,-1));LinearLayout words=ui.column();ui.pad(words,25,30,25,24);words.addView(ui.text("✦",34,android.graphics.Color.WHITE,false));ui.space(words,12);words.addView(ui.text("与热爱，再次相遇。",25,android.graphics.Color.WHITE,true));ui.space(words,8);words.addView(ui.text("把喜欢的世界，装进口袋。",14,0xEEFFFFFF,false));banner.addView(words);body.addView(banner,new LinearLayout.LayoutParams(-1,ui.dp(215)));
        ui.space(body,30);body.addView(ui.text("欢迎回来",27,ui.text,true));ui.space(body,8);body.addView(ui.text("登录你的仓库账号，开始探索",14,ui.muted,false));ui.space(body,24);
        EditText account=input("用户名 / 邮箱",false);account.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);body.addView(account,new LinearLayout.LayoutParams(-1,ui.dp(58)));ui.space(body,12);
        EditText password=input("密码",true);body.addView(password,new LinearLayout.LayoutParams(-1,ui.dp(58)));ui.space(body,12);
        CheckBox remember=new CheckBox(this);remember.setText("保持登录（仅加密保存会话）");remember.setTextColor(ui.muted);remember.setTextSize(13);remember.setButtonTintList(android.content.res.ColorStateList.valueOf(ui.accent));body.addView(remember);ui.space(body,12);
        TextView status=ui.text(message,13,ui.pink,false);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        TextView submit=ui.button("开启探索  →",true,()->{});
        Runnable action=()->{
            String a=account.getText().toString().trim(),p=password.getText().toString();if(a.isEmpty()||p.isEmpty()){status.setText("请输入账号和密码");return;}
            submit.setEnabled(false);submit.setText("正在登录…");status.setText("");hideKeyboard();
            task(()->api.login(a,p,remember.isChecked()),u->{password.setText("");user=u;library.setUser(u.optLong("id"));route=new Route("home","发现");enter();},e->{submit.setEnabled(true);submit.setText("开启探索  →");status.setText(e);});
        };
        ui.click(submit,action);body.addView(submit,new LinearLayout.LayoutParams(-1,ui.dp(54)));ui.space(body,12);body.addView(status);password.setImeOptions(EditorInfo.IME_ACTION_DONE);password.setOnEditorActionListener((v,a,event)->{if(a==EditorInfo.IME_ACTION_DONE){action.run();return true;}return false;});
        ui.space(body,24);TextView footer=ui.text("账号信息仅发送至 cangku.moe\n非官方客户端 · 仓库 / 星屿",12,ui.muted,false);footer.setGravity(Gravity.CENTER);footer.setLineSpacing(ui.dp(6),1);body.addView(footer,new LinearLayout.LayoutParams(-1,-2));
        ui.space(body,8);TextView official=ui.button("注册 / 忘记密码 · 前往官网",false,()->external(UrlPolicy.ORIGIN+"/login"));body.addView(official);
    }
    private EditText input(String hint,boolean password){
        EditText e=new EditText(this);e.setSingleLine(true);e.setTextSize(15);e.setTextColor(ui.text);e.setHintTextColor(ui.muted);e.setHint(hint);ui.pad(e,18,8,18,8);e.setBackground(ui.round(ui.surface,17));
        e.setInputType(android.text.InputType.TYPE_CLASS_TEXT|(password?android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD:0));return e;
    }
    private void hideKeyboard(){((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(root.getWindowToken(),0);root.clearFocus();}
    private void loading(String label){LinearLayout box=ui.column();box.setGravity(Gravity.CENTER);ui.pad(box,0,64,0,50);ProgressBar p=new ProgressBar(this);p.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(ui.accent));box.addView(p,new LinearLayout.LayoutParams(ui.dp(30),ui.dp(30)));ui.space(box,18);box.addView(ui.text(label,14,ui.muted,false));body.addView(box,new LinearLayout.LayoutParams(-1,-2));}
    private void error(String message,Runnable retry){body.removeAllViews();ui.space(body,60);TextView icon=ui.text("✧",52,ui.pink,false);icon.setGravity(Gravity.CENTER);body.addView(icon,new LinearLayout.LayoutParams(-1,-2));TextView text=ui.text(message,15,ui.muted,false);text.setGravity(Gravity.CENTER);ui.pad(text,15,20,15,24);body.addView(text);body.addView(ui.button("重新连接",true,retry));}
    private void empty(String text){ui.space(body,30);TextView t=ui.text("✦\n\n"+text,16,ui.muted,false);t.setGravity(Gravity.CENTER);t.setLineSpacing(ui.dp(5),1);body.addView(t,new LinearLayout.LayoutParams(-1,ui.dp(180)));}
    private void section(String title,String subtitle){ui.space(body,18);body.addView(ui.text(title,21,ui.text,true));if(!subtitle.isEmpty()){ui.space(body,6);body.addView(ui.text(subtitle,12,ui.muted,false));}ui.space(body,16);}
    private void chips(String[] labels,String[] values,String selected,java.util.function.Consumer<String> onClick){
        HorizontalScrollView s=new HorizontalScrollView(this);s.setHorizontalScrollBarEnabled(false);LinearLayout row=ui.row();
        for(int i=0;i<labels.length;i++){String value=values[i];TextView chip=ui.chip(labels[i],selected.equals(value),()->onClick.accept(value));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,-2);p.setMargins(0,0,ui.dp(8),0);row.addView(chip,p);}s.addView(row);body.addView(s,new LinearLayout.LayoutParams(-1,-2));ui.space(body,14);
    }
    private void categoryChips(){
        ArrayList<String> labels=new ArrayList<>(),ids=new ArrayList<>();labels.add("全部");ids.add("0");for(int i=0;i<categories.length();i++){JSONObject o=categories.optJSONObject(i);if(o!=null){labels.add(o.optString("name"));ids.add(o.optString("id"));}}
        chips(labels.toArray(new String[0]),ids.toArray(new String[0]),String.valueOf(route.id),value->{route.id=Long.parseLong(value);route.page=1;route.scrollY=0;render();});
    }
    private void feed(){
        boolean home=route.kind.equals("home"),rank=route.kind.equals("rank"),favorite=route.kind.equals("favorites");
        toolbar(route.title,!home&&!rank,()->{route.scrollY=0;render();});
        if(home){
            carousel=new HomeCarousel(this);body.addView(carousel.view(),new LinearLayout.LayoutParams(-1,-2));carousel.start();ui.space(body,18);
            TextView search=ui.button("⌕   搜索作品、作者与关键词",false,()->go(new Route("search","搜索")));search.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);body.addView(search,new LinearLayout.LayoutParams(-1,ui.dp(50)));
            section("新鲜发现","来自仓库的最新投稿");
        }
        if(rank){section("热爱，正在发生","按网站热度排行 · 每次打开同步更新");chips(new String[]{"日榜","周榜","月榜"},new String[]{"daily","weekly","monthly"},route.period,value->{route.period=value;route.page=1;route.scrollY=0;render();});categoryChips();}
        if(route.kind.equals("category")){showChildCategories(route.id);section(route.title,"这里是属于你的兴趣频道");}
        LinearLayout content=ui.column();body.addView(content);LinearLayout previous=body;body=content;loading("正在寻找下一份喜欢…");body=previous;
        Map<String,String> p=ApiClient.params("page",String.valueOf(route.page),"per_page","20","simple","1","with[0]","user","with[1]","categories","include","user,categories:simple");
        String path="post/list";
        if(rank){path="post/rank";Calendar now=Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"));now.setFirstDayOfWeek(Calendar.SUNDAY);now.setMinimalDaysInFirstWeek(1);p.put("year",String.valueOf(now.get(Calendar.YEAR)));p.put("date_type",route.period);p.put("date_value",String.valueOf(route.period.equals("daily")?now.get(Calendar.DAY_OF_YEAR):route.period.equals("weekly")?now.get(Calendar.WEEK_OF_YEAR):now.get(Calendar.MONTH)+1));}
        if(route.kind.equals("category")||rank)if(route.id>0)p.put("category_in[0]",String.valueOf(route.id));
        if(favorite){path="user/favoritePost";p.put("id",String.valueOf(user.optLong("id")));}
        if(route.kind.equals("authorPosts")){path="user/post";p.put("id",String.valueOf(route.id));}
        String endpoint=path;
        task(()->api.get(endpoint,p),result->{content.removeAllViews();LinearLayout old=body;body=content;showCards(result.optJSONArray("data"),result.optJSONObject("meta"));body=old;restoreScroll();},message->{LinearLayout old=body;body=content;error(message,()->render());body=old;});
    }
    private void search(){
        toolbar("寻找你的心动",true,()->render());
        LinearLayout row=ui.row();EditText query=input("搜索作品、作者昵称",false);query.setText(route.query);query.setImeOptions(EditorInfo.IME_ACTION_SEARCH);row.addView(query,new LinearLayout.LayoutParams(0,ui.dp(54),1));
        Runnable run=()->{String value=query.getText().toString().trim();if(value.isEmpty())return;route.query=value;route.page=1;route.scrollY=0;hideKeyboard();render();};
        LinearLayout.LayoutParams btn=new LinearLayout.LayoutParams(ui.dp(48),ui.dp(48));btn.setMargins(ui.dp(8),0,0,0);row.addView(ui.iconButton("搜索",run),btn);body.addView(row);ui.space(body,16);query.setOnEditorActionListener((v,action,event)->{if(action==EditorInfo.IME_ACTION_SEARCH){run.run();return true;}return false;});
        boolean authors=route.period.equals("authors");chips(new String[]{"作品","作者"},new String[]{"posts","authors"},authors?"authors":"posts",kind->{route.period=kind;route.page=1;route.scrollY=0;render();});
        if(route.query.isEmpty()){section("灵感导航",authors?"输入作者昵称后开始查找":"选择一个频道，或者输入关键词");if(!authors)categoryTiles();return;}
        if(!authors)categoryChips();LinearLayout results=ui.column();body.addView(results);results.addView(ui.text("正在寻找「"+route.query+"」…",14,ui.muted,false));
        if(authors){
            task(()->api.get("user/list",ApiClient.params("search",route.query,"page",String.valueOf(route.page),"per_page","20")),response->{
                results.removeAllViews();JSONArray people=response.optJSONArray("data");if(people==null||people.length()==0)results.addView(ui.text("未找到作者，试试其他昵称",14,ui.muted,false));
                else for(int i=0;i<people.length();i++){JSONObject person=people.getJSONObject(i);LinearLayout author=ui.row();ui.pad(author,16,16,16,16);author.setBackground(ui.round(ui.surface,16));ImageView avatar=new ImageView(this);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(ui.round(ui.soft,24));avatar.setClipToOutline(true);author.addView(avatar,new LinearLayout.LayoutParams(ui.dp(48),ui.dp(48)));images.into(person.optString("avatar"),avatar);LinearLayout names=ui.column();ui.pad(names,14,0,0,0);names.addView(ui.text(person.optString("nickname","作者"),17,ui.text,true));names.addView(ui.text("UID "+person.optLong("id")+"  ·  "+person.optInt("post_count")+" 篇投稿",12,ui.muted,false));author.addView(names,new LinearLayout.LayoutParams(0,-2,1));ui.click(author,()->go(new Route("profile","作者主页").id(person.optLong("id"))));results.addView(author);ui.space(results,12);}
                JSONObject meta=response.optJSONObject("meta");if(meta!=null&&meta.optJSONObject("pagination")!=null){LinearLayout old=body;body=results;pagination(meta.getJSONObject("pagination"));body=old;}restoreScroll();
            },message->{results.removeAllViews();results.addView(ui.text(message,14,ui.muted,false));results.addView(ui.button("重试",false,()->render()));});return;
        }
        Map<String,String> p=ApiClient.params("search",route.query,"page",String.valueOf(route.page),"per_page","20","include","user,categories:simple","simple","1","with[0]","user","with[1]","categories");if(route.id>0)p.put("category_in[0]",String.valueOf(route.id));
        task(()->api.get("post/search",p),result->{results.removeAllViews();LinearLayout old=body;body=results;section("搜索结果","关键词 · "+route.query);showCards(result.optJSONArray("data"),result.optJSONObject("meta"));body=old;restoreScroll();},message->{results.removeAllViews();results.addView(ui.text(message,14,ui.muted,false));results.addView(ui.button("重试",false,()->render()));});
    }
    private void categoryPage(){toolbar("兴趣宇宙",false,()->{loadCategories();render();});section("总有一个世界属于你","按主题发现更多喜欢的作品");if(categories.length()==0){loading("正在载入频道…");return;}categoryTiles();}
    private void categoryTiles(){
        String[] symbols={"映画","文库","日常","秘境","GAME","漫画","画集","旋律","灵感","ANIME"};int[] colors={0xFFE7ABCE,0xFFA69CE9,0xFF8CC7BF,0xFFAB96CE,0xFF8BA5E5,0xFFE6A3AF,0xFF8DBAD4,0xFFC8A8DA,0xFFD9B68C,0xFF9DA6E5};
        for(int i=0;i<categories.length();i+=2){LinearLayout row=ui.row();for(int j=i;j<Math.min(i+2,categories.length());j++){
            JSONObject category=categories.optJSONObject(j);if(category==null)continue;LinearLayout tile=ui.column();ui.pad(tile,18,22,18,20);tile.setBackground(ui.gradient(ui.surface,ui.soft,22));TextView mark=ui.text(symbols[j%symbols.length],13,colors[j%colors.length],true);tile.addView(mark);ui.space(tile,20);tile.addView(ui.text(category.optString("name"),22,ui.text,true));ui.space(tile,6);tile.addView(ui.text("进入频道  ↗",12,ui.muted,false));ui.click(tile,()->go(new Route("category",category.optString("name")).id(category.optLong("id"))));
            LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,ui.dp(155),1);p.setMargins(j==i?0:ui.dp(6),0,j==i?ui.dp(6):0,ui.dp(12));row.addView(tile,p);
        }if(row.getChildCount()==1)row.addView(new View(this),new LinearLayout.LayoutParams(0,1,1));body.addView(row);}
    }
    private void showChildCategories(long parent){
        JSONObject category=findCategory(categories,parent);if(category==null)return;JSONArray children=category.optJSONArray("children");if(children==null||children.length()==0)return;
        String[] names=new String[children.length()],ids=new String[children.length()];for(int i=0;i<children.length();i++){names[i]=children.optJSONObject(i).optString("name");ids[i]=children.optJSONObject(i).optString("id");}
        chips(names,ids,"",id->{JSONObject selected=findCategory(categories,Long.parseLong(id));if(selected!=null)go(new Route("category",selected.optString("name")).id(Long.parseLong(id)));});
    }
    private JSONObject findCategory(JSONArray all,long id){for(int i=0;i<all.length();i++){JSONObject o=all.optJSONObject(i);if(o==null)continue;if(o.optLong("id")==id)return o;JSONArray children=o.optJSONArray("children");if(children!=null){JSONObject found=findCategory(children,id);if(found!=null)return found;}}return null;}
    private void showCards(JSONArray posts,JSONObject meta){
        if(posts==null||posts.length()==0){empty(route.kind.equals("favorites")?"还没有收藏，去发现喜欢的作品吧":"这里暂时没有内容");return;}
        int columns=Math.max(2,Math.min(4,(int)(getResources().getConfiguration().screenWidthDp/180)));
        for(int i=0;i<posts.length();i+=columns){LinearLayout row=ui.row();row.setGravity(Gravity.TOP);
            for(int j=i;j<i+columns;j++){
                LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-2,1);p.setMargins(j==i?0:ui.dp(6),0,j==i+columns-1?0:ui.dp(6),ui.dp(14));
                if(j>=posts.length()){row.addView(new View(this),p);continue;}JSONObject post=posts.optJSONObject(j);if(post==null)continue;row.addView(card(post,j),p);
            }body.addView(row,new LinearLayout.LayoutParams(-1,-2));
        }
        if(meta!=null){JSONObject page=meta.optJSONObject("pagination");if(page!=null)pagination(page);}
    }
    private View card(JSONObject post,int index){
        LinearLayout card=ui.column();card.setBackground(ui.round(ui.surface,18));card.setClipToOutline(true);card.setElevation(ui.dp(1));
        FrameLayout cover=new FrameLayout(this);cover.setBackground(ui.gradient(ui.soft,ui.line,0));ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);cover.addView(image,new FrameLayout.LayoutParams(-1,-1));
        TextView fallback=ui.text("✦",24,ui.pink,false);fallback.setGravity(Gravity.CENTER);cover.addView(fallback,new FrameLayout.LayoutParams(-1,-1));
        String url=post.optString("thumb");images.load(url,bitmap->{if(bitmap!=null){image.setImageBitmap(bitmap);fallback.setVisibility(View.GONE);}});
        String badge=route.kind.equals("rank")?String.format(Locale.ROOT,"%02d",index+1+(route.page-1)*20):post.optBoolean("is_sticky")?"置顶":post.optBoolean("is_recommended")?"推荐":"";
        if(!badge.isEmpty()){TextView tag=ui.text(badge,11,android.graphics.Color.WHITE,true);ui.pad(tag,9,5,9,5);tag.setBackground(ui.round(ui.accent,10));FrameLayout.LayoutParams b=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.LEFT);b.setMargins(ui.dp(8),ui.dp(8),0,0);cover.addView(tag,b);}
        int col=Math.max(2,Math.min(4,getResources().getConfiguration().screenWidthDp/180));int width=(getResources().getConfiguration().screenWidthDp-40-(col-1)*12)/col;
        card.addView(cover,new LinearLayout.LayoutParams(-1,ui.dp(width*.92f)));LinearLayout info=ui.column();ui.pad(info,12,12,12,13);TextView title=ui.text(post.optString("title"),14,ui.text,true);title.setMaxLines(3);title.setMinLines(3);title.setEllipsize(TextUtils.TruncateAt.END);title.setLineSpacing(ui.dp(2),1);info.addView(title);ui.space(info,9);JSONObject author=post.optJSONObject("user");String nickname=author==null?"仓库作者":author.optString("nickname","仓库作者");TextView metadata=ui.text(nickname+"\n"+formatCount(post.optLong("view_count"))+" 围观",11,ui.muted,false);metadata.setMaxLines(2);metadata.setLineSpacing(ui.dp(4),1);metadata.setEllipsize(TextUtils.TruncateAt.END);info.addView(metadata);card.addView(info);card.setContentDescription(post.optString("title"));ui.click(card,()->go(new Route("article","文章").id(post.optLong("id"))));return card;
    }
    private String formatCount(long n){return n>=10000?String.format(Locale.CHINA,"%.1f万",n/10000.0):String.valueOf(n);}
    private void pagination(JSONObject page){
        int current=page.optInt("current_page",route.page),total=page.optInt("total_pages",1);ui.space(body,8);LinearLayout row=ui.row();
        TextView prev=ui.button("← 上一页",false,()->{route.page=Math.max(1,current-1);route.scrollY=0;render();});prev.setEnabled(current>1);prev.setAlpha(current>1?1:.35f);row.addView(prev,new LinearLayout.LayoutParams(0,-2,1));
        TextView label=ui.text(current+" / "+total,12,ui.muted,false);label.setGravity(Gravity.CENTER);row.addView(label,new LinearLayout.LayoutParams(ui.dp(85),-2));TextView next=ui.button("下一页 →",false,()->{route.page=current+1;route.scrollY=0;render();});next.setEnabled(current<total);next.setAlpha(current<total?1:.35f);row.addView(next,new LinearLayout.LayoutParams(0,-2,1));body.addView(row);
        ui.space(body,14);TextView count=ui.text("共 "+formatCount(page.optLong("total"))+" 项 · 与官网实时同步",11,ui.muted,false);count.setGravity(Gravity.CENTER);body.addView(count,new LinearLayout.LayoutParams(-1,-2));
    }
    private void restoreScroll(){int y=route.scrollY;if(y>0)scroll.post(()->scroll.scrollTo(0,y));}

    private void article(){
        toolbar("作品详情",true,()->render());loading("正在打开这一页故事…");long id=route.id;
        task(()->api.get("post/info",ApiClient.params("id",String.valueOf(id),"include","user,tags,categories,favorited,upvoted")).getJSONObject("data"),post->{
            body.removeAllViews();library.visit(post);
            String thumb=post.optString("thumb");if(UrlPolicy.isImage(thumb)){ImageView cover=new ImageView(this);cover.setScaleType(ImageView.ScaleType.CENTER_CROP);cover.setBackground(ui.round(ui.soft,22));cover.setClipToOutline(true);body.addView(cover,new LinearLayout.LayoutParams(-1,ui.dp(220)));images.into(thumb,cover);ui.space(body,22);}
            JSONArray cats=post.optJSONArray("categories");if(cats!=null&&cats.length()>0){HorizontalScrollView wrap=new HorizontalScrollView(this);wrap.setHorizontalScrollBarEnabled(false);LinearLayout row=ui.row();for(int i=0;i<cats.length();i++){JSONObject cat=cats.optJSONObject(i);if(cat==null)continue;TextView chip=ui.chip(cat.optString("name"),false,()->go(new Route("category",cat.optString("name")).id(cat.optLong("id"))));LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-2,-2);cp.setMargins(0,0,ui.dp(8),0);row.addView(chip,cp);}wrap.addView(row);body.addView(wrap);ui.space(body,14);}
            TextView title=ui.text(post.optString("title"),24,ui.text,true);title.setLineSpacing(ui.dp(4),1);title.setTextIsSelectable(true);body.addView(title);ui.space(body,16);
            JSONObject author=post.optJSONObject("user");LinearLayout authorRow=ui.row();
            if(author!=null){ImageView avatar=new ImageView(this);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(ui.round(ui.soft,24));avatar.setClipToOutline(true);authorRow.addView(avatar,new LinearLayout.LayoutParams(ui.dp(40),ui.dp(40)));images.into(author.optString("avatar"),avatar);LinearLayout names=ui.column();ui.pad(names,12,0,0,0);names.addView(ui.text(author.optString("nickname"),14,ui.text,true));names.addView(ui.text("Lv."+author.optInt("level")+"  ·  查看作者主页",11,ui.muted,false));authorRow.addView(names,new LinearLayout.LayoutParams(0,-2,1));ui.click(authorRow,()->go(new Route("profile",author.optString("nickname")).id(author.optLong("id"))));}
            body.addView(authorRow);ui.space(body,14);body.addView(ui.text(date(post.optString("created_at"))+"   ·   "+formatCount(post.optLong("view_count"))+" 围观",12,ui.muted,false));ui.space(body,18);
            LinearLayout actions=ui.row();TextView favorite=ui.button(post.optBoolean("favorited")?"★ 已收藏":"☆ 收藏",post.optBoolean("favorited"),()->{});
            ui.click(favorite,()->{
                boolean was=post.optBoolean("favorited");Runnable mutate=()->{
                    favorite.setEnabled(false);
                    task(()->api.post(was?"post/unfavorite":"post/favorite",new JSONObject().put("id",id)),result->{post.put("favorited",!was);favorite.setText(!was?"★ 已收藏":"☆ 收藏");favorite.setTextColor(!was?android.graphics.Color.WHITE:ui.accent);favorite.setBackground(ui.round(!was?ui.accent:ui.soft,16));favorite.setEnabled(true);toast(!was?"已收藏到你的仓库":"已取消收藏");},message->{favorite.setEnabled(true);toast(message);});
                };
                if(was)new AlertDialog.Builder(this).setTitle("取消收藏？").setMessage("这篇文章将从你的官网收藏中移除。").setNegativeButton("保留",null).setPositiveButton("取消收藏",(d,w)->mutate.run()).show();else mutate.run();
            });
            actions.addView(favorite,new LinearLayout.LayoutParams(0,-2,1));TextView comment=ui.button("吐槽 "+post.optInt("comment_count"),false,()->go(new Route("comments","吐槽").id(id)));LinearLayout.LayoutParams ap=new LinearLayout.LayoutParams(0,-2,1);ap.setMargins(ui.dp(8),0,ui.dp(8),0);actions.addView(comment,ap);actions.addView(ui.iconButton("分享",()->share(id)),new LinearLayout.LayoutParams(ui.dp(46),ui.dp(46)));body.addView(actions);
            ui.space(body,24);ReaderContent content=ReaderContent.parse(post.optString("content"));
            LinearLayout articleCard=ui.column();ui.pad(articleCard,18,20,18,20);articleCard.setBackground(ui.round(ui.surface,20));nativeHtml(articleCard,content.html,library.textSize());body.addView(articleCard,new LinearLayout.LayoutParams(-1,-2));
            if(!content.resources.isEmpty()){section("资源入口","作者提供的链接与提取说明");for(ReaderContent.Resource resource:content.resources)resource(resource);}
            if(content.hasUnsupportedShortcodes){ui.space(body,14);body.addView(ui.text("部分特殊组件请在原文中查看。",12,ui.muted,false));}
            ui.space(body,22);body.addView(ui.button("在官网打开原文  ↗",false,()->external(UrlPolicy.ORIGIN+"/archives/"+id)));ui.space(body,12);body.addView(ui.button("阅读设置 · 字号与主题",false,()->go(new Route("appearance","阅读与外观"))));restoreScroll();
            if(user!=null&&post.optLong("user_id")==user.optLong("id")){ui.space(body,12);body.addView(ui.button("编辑这篇投稿",false,()->go(new Route("editor","编辑投稿").id(id))));}
            social.attachArticle(post,body);
        },message->error(message,()->render()));
    }
    private String date(String value){return value.length()>=10?value.substring(0,10):value;}
    private void nativeHtml(LinearLayout parent,String html,int size){
        html=ReaderContent.nativeCodeBlocks(html);
        TextView t=ui.text("",size,ui.text,false);t.setLineSpacing(ui.dp(7),1.15f);t.setLinkTextColor(ui.accent);t.setTextIsSelectable(true);t.setMovementMethod(LinkMovementMethod.getInstance());
        int token=epoch;int width=ui.dp(getResources().getConfiguration().screenWidthDp-80);
        Html.ImageGetter getter=source->{
            String resolved=source.startsWith("/")?UrlPolicy.ORIGIN+source:source;
            AsyncDrawable placeholder=new AsyncDrawable(ui.soft);placeholder.setBounds(0,0,width,ui.dp(140));
            images.load(resolved,bitmap->{
                if(bitmap==null||token!=epoch||closed)return;
                int height=(int)Math.min(ui.dp(2400),width*(bitmap.getHeight()/(float)Math.max(1,bitmap.getWidth())));
                BitmapDrawable d=new BitmapDrawable(getResources(),bitmap);d.setBounds(0,0,width,height);placeholder.content=d;placeholder.setBounds(0,0,width,height);t.setText(t.getText());t.requestLayout();
            });return placeholder;
        };
        Spanned parsed=Html.fromHtml(html,Html.FROM_HTML_MODE_COMPACT,getter,null);SpannableStringBuilder safe=new SpannableStringBuilder(parsed);
        final ImageSpan[] pressed={null};
        t.setOnTouchListener((v,event)->{
            if(event.getActionMasked()==MotionEvent.ACTION_DOWN){
                pressed[0]=null;Layout layout=t.getLayout();
                if(layout!=null){float x=event.getX()-t.getTotalPaddingLeft()+t.getScrollX();float y=event.getY()-t.getTotalPaddingTop()+t.getScrollY();
                    if(y>=0&&y<layout.getHeight()){int line=layout.getLineForVertical((int)y);
                        if(x>=layout.getLineLeft(line)&&x<=layout.getLineRight(line)){int offset=layout.getOffsetForHorizontal(line,x);
                            ImageSpan[] spans=safe.getSpans(Math.max(0,offset-1),Math.min(safe.length(),offset+1),ImageSpan.class);
                            for(ImageSpan span:spans){int a=safe.getSpanStart(span),b=safe.getSpanEnd(span);float left=layout.getPrimaryHorizontal(a),right=layout.getLineForOffset(b)==line?layout.getPrimaryHorizontal(b):layout.getLineRight(line);if(x>=Math.min(left,right)&&x<=Math.max(left,right)){pressed[0]=span;break;}}
                        }
                    }
                }
            }else if(event.getActionMasked()==MotionEvent.ACTION_CANCEL)pressed[0]=null;
            return false;
        });
        t.setOnLongClickListener(v->{ImageSpan span=pressed[0];if(span==null)return false;
            android.graphics.drawable.Drawable drawable=span.getDrawable();if(drawable instanceof AsyncDrawable)drawable=((AsyncDrawable)drawable).content;
            if(drawable instanceof BitmapDrawable)recognizeQr(((BitmapDrawable)drawable).getBitmap());else toast("图片尚未加载完成，请稍后长按");return true;
        });
        for(URLSpan url:safe.getSpans(0,safe.length(),URLSpan.class)){
            int start=safe.getSpanStart(url),end=safe.getSpanEnd(url);safe.removeSpan(url);String link=url.getURL();
            safe.setSpan(new ClickableSpan(){@Override public void onClick(View widget){openLink(link);}@Override public void updateDrawState(TextPaint ds){ds.setColor(ui.accent);ds.setUnderlineText(false);}},start,end,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
        t.setText(safe);parent.addView(t,new LinearLayout.LayoutParams(-1,-2));
    }
    private static final class AsyncDrawable extends android.graphics.drawable.Drawable {
        android.graphics.drawable.Drawable content;final android.graphics.Paint paint=new android.graphics.Paint(3);
        AsyncDrawable(int color){paint.setColor(color);}
        @Override public void draw(android.graphics.Canvas canvas){if(content!=null){content.setBounds(getBounds());content.draw(canvas);}else canvas.drawRoundRect(new android.graphics.RectF(getBounds()),18,18,paint);}
        @Override public void setAlpha(int a){paint.setAlpha(a);}
        @Override public void setColorFilter(android.graphics.ColorFilter f){paint.setColorFilter(f);}
        @Override public int getOpacity(){return android.graphics.PixelFormat.TRANSLUCENT;}
    }
    private void resource(ReaderContent.Resource resource){
        LinearLayout card=ui.column();ui.pad(card,18,18,18,18);card.setBackground(ui.round(ui.surface,20));card.addView(ui.text(resource.title,17,ui.text,true));
        if(!resource.info.isEmpty()){ui.space(card,8);TextView info=ui.text(resource.info,14,ui.muted,false);info.setTextIsSelectable(true);card.addView(info);}
        if(resource.links.isEmpty()){ui.space(card,12);card.addView(ui.text("该资源使用特殊格式，请前往官网原文查看。",13,ui.muted,false));}
        for(Map.Entry<String,String> link:resource.links.entrySet()){
            ui.space(card,12);LinearLayout row=ui.row();String url=link.getValue();TextView open=ui.button(link.getKey()+"  ↗",false,()->openLink(url));row.addView(open,new LinearLayout.LayoutParams(0,-2,1));TextView copy=ui.button("复制",false,()->copy(url));LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-2,-2);cp.setMargins(ui.dp(8),0,0,0);row.addView(copy,cp);card.addView(row);
        }
        body.addView(card,new LinearLayout.LayoutParams(-1,-2));ui.space(body,12);
    }
    private void openLink(String value){
        if(value.startsWith("/"))value=UrlPolicy.ORIGIN+value;
        long id=UrlPolicy.articleId(value);if(id>0){go(new Route("article","文章").id(id));return;}
        if(!UrlPolicy.canOpen(value)){toast("此链接格式暂不支持，请在官网查看");return;}
        String lower=value.toLowerCase(Locale.ROOT);if(UrlPolicy.isImage(value)&&lower.matches(".*\\.(png|jpe?g|webp|gif)(?:[?#].*)?$")){preview(value);return;}
        external(value);
    }
    private void preview(String url){
        LinearLayout wrap=ui.column();ui.pad(wrap,20,20,20,16);ImageView image=new ImageView(this);image.setAdjustViewBounds(true);image.setScaleType(ImageView.ScaleType.FIT_CENTER);wrap.addView(image,new LinearLayout.LayoutParams(-1,ui.dp(330)));images.into(url,image);image.setOnLongClickListener(v->{if(image.getDrawable() instanceof BitmapDrawable)recognizeQr(((BitmapDrawable)image.getDrawable()).getBitmap());else toast("图片尚未加载完成");return true;});ui.space(wrap,14);TextView note=ui.text("长按图片识别二维码。识别在本机完成，可复制结果或确认打开链接。",13,ui.muted,false);wrap.addView(note);ui.space(wrap,12);wrap.addView(ui.button("复制图片链接",false,()->copy(url)));
        new AlertDialog.Builder(this).setTitle("查看资源图片").setView(wrap).setPositiveButton("浏览器打开",(d,w)->external(url)).setNegativeButton("返回",null).show();
    }
    void recognizeQr(Bitmap bitmap){
        if(qrBusy){toast("正在识别二维码…");return;}qrBusy=true;toast("正在本机识别二维码…");
        task(()->{try{float scale=Math.min(1,2048f/Math.max(bitmap.getWidth(),bitmap.getHeight()));Bitmap work=scale<1?Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bitmap.getWidth()*scale)),Math.max(1,(int)(bitmap.getHeight()*scale)),true):bitmap;
            try{int[] pixels=new int[work.getWidth()*work.getHeight()];work.getPixels(pixels,0,work.getWidth(),0,0,work.getWidth(),work.getHeight());return QrDecoder.decode(pixels,work.getWidth(),work.getHeight());}finally{if(work!=bitmap)work.recycle();}
        }catch(OutOfMemoryError e){throw new java.io.IOException("图片过大，无法识别");}finally{main.post(()->qrBusy=false);}},value->{
            if(value==null){toast("未识别到二维码，请尝试清晰的原图");return;}
            TextView result=ui.text(value,15,ui.text,false);result.setTextIsSelectable(true);ui.pad(result,22,18,22,18);ScrollView content=new ScrollView(this);content.addView(result);
            AlertDialog.Builder dialog=new AlertDialog.Builder(this).setTitle("二维码识别结果").setView(content).setNegativeButton("关闭",null).setNeutralButton("复制内容",(d,w)->copy(value));
            if(UrlPolicy.canOpen(value))dialog.setPositiveButton("打开链接",(d,w)->openLink(value));dialog.show();
        },error->{qrBusy=false;toast(error);});
    }
    private void mine(){
        toolbar("我的星屿",false,()->refreshUser());
        if(user==null){login("");return;}LinearLayout card=ui.column();ui.pad(card,22,24,22,24);card.setBackground(ui.gradient(ui.soft,ui.surface,24));LinearLayout row=ui.row();ImageView avatar=new ImageView(this);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(ui.round(ui.surface,32));avatar.setClipToOutline(true);row.addView(avatar,new LinearLayout.LayoutParams(ui.dp(64),ui.dp(64)));images.into(user.optString("avatar"),avatar);LinearLayout names=ui.column();ui.pad(names,16,0,0,0);names.addView(ui.text(user.optString("nickname"),24,ui.text,true));ui.space(names,5);names.addView(ui.text("Lv."+user.optInt("level")+"    ✦  "+user.optLong("point")+" 积分",12,ui.accent,true));row.addView(names,new LinearLayout.LayoutParams(0,-2,1));card.addView(row);ui.space(card,18);String description=user.optString("description");card.addView(ui.text(description.isEmpty()?"把喜欢的世界，好好收藏。":description,13,ui.muted,false));ui.space(card,22);
        LinearLayout stats=ui.row();String[] labels={"投稿","吐槽","收藏"};String[] values={user.optString("post_count","0"),user.optString("comment_count","0"),user.optString("favorite_post_count","0")};for(int i=0;i<labels.length;i++){LinearLayout stat=ui.column();stat.setGravity(Gravity.CENTER);stat.addView(ui.text(values[i],23,ui.text,true));ui.space(stat,4);stat.addView(ui.text(labels[i],12,ui.muted,false));stats.addView(stat,new LinearLayout.LayoutParams(0,-2,1));}card.addView(stats);body.addView(card);ui.space(body,22);
        menu("收藏","我的收藏","与官网的收藏同步",()->go(new Route("favorites","我的收藏")));
        menu("历史","阅读足迹","在这台设备上，遇见过的故事",()->go(new Route("history","阅读足迹")));
        menu("作者","我的投稿","查看已发布的作品",()->go(new Route("authorPosts","我的投稿").id(user.optLong("id"))));
        menu("作者","我的评论","查看已发评论、回复与删除管理",()->go(new Route("myComments","我的评论")));
        menu("历史","通知","回复我的 / 收到的赞 / 系统通知",()->{Route next=new Route("notifications","通知");next.period="reply";go(next);});
        TextView badge=ui.text("正在同步通知数量…",11,ui.muted,false);body.addView(badge);ui.space(body,10);social.loadMineBadge(badge);
        menu("聊天室","我的私信","选择收信人、未读会话与拒收名单",()->go(new Route("privateMessages","我的私信")));
        menu("作者","投稿与管理","新建投稿 / 草稿 / 审核 / 回收站",()->go(new Route("manage","投稿与管理")));
        menu("历史","积分与经验记录","查看账号的积分与经验变动",()->go(new Route("accountLogs","积分与经验")));
        menu("设置","设置","个人资料 / 账号安全 / 阅读与外观 / 更新",()->go(new Route("settings","设置")));
        menu("首页","官网入口","站外社区与更多网站功能",()->external(UrlPolicy.ORIGIN));
        ui.space(body,26);TextView exit=ui.button("退出当前账号",false,()->new AlertDialog.Builder(this).setTitle("退出登录？").setMessage("将清除这台设备上的登录会话。").setNegativeButton("取消",null).setPositiveButton("退出",(d,w)->logout()).show());body.addView(exit);
    }
    private void refreshUser(){task(()->api.get("auth/me",ApiClient.params("include","roles,permissions,meta")).getJSONObject("data"),u->{updateAccount(u);render();},this::toast);}
    private void profile(){
        toolbar("作者主页",true,()->render());loading("正在载入作者…");long id=route.id;
        task(()->api.get("user/info",ApiClient.params("id",String.valueOf(id))).getJSONObject("data"),author->{body.removeAllViews();ImageView avatar=new ImageView(this);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(ui.round(ui.soft,40));avatar.setClipToOutline(true);LinearLayout.LayoutParams av=new LinearLayout.LayoutParams(ui.dp(80),ui.dp(80));av.gravity=Gravity.CENTER;body.addView(avatar,av);images.into(author.optString("avatar"),avatar);ui.space(body,16);TextView name=ui.text(author.optString("nickname"),27,ui.text,true);name.setGravity(Gravity.CENTER);body.addView(name);ui.space(body,6);LinearLayout uidRow=ui.row();uidRow.setGravity(Gravity.CENTER);uidRow.addView(ui.text("UID  ",12,ui.muted,false));long authorUid=author.optLong("id",id);TextView uid=ui.text(String.valueOf(authorUid),14,ui.accent,true);uid.setGravity(Gravity.CENTER);uid.setMinHeight(ui.dp(44));ui.pad(uid,8,0,8,0);uid.setContentDescription("作者UID "+authorUid+"，点击复制");ui.click(uid,()->{((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("作者UID",String.valueOf(authorUid)));toast("已复制UID");});uidRow.addView(uid);uidRow.addView(ui.text("点击复制",10,ui.muted,false));body.addView(uidRow);ui.space(body,8);TextView description=ui.text(author.optString("description"),14,ui.muted,false);description.setGravity(Gravity.CENTER);body.addView(description);section("创作档案","Lv."+author.optInt("level")+" · "+author.optInt("post_count")+" 篇投稿");body.addView(ui.button("浏览作者的投稿  →",true,()->go(new Route("authorPosts",author.optString("nickname")+"的投稿").id(id))));ui.space(body,14);if(user!=null&&id!=user.optLong("id")){body.addView(ui.button("给作者发私信  ✉",true,()->go(new Route("dmConversation","私信").id(id))));ui.space(body,14);}body.addView(ui.button("在官网查看作者主页",false,()->external(UrlPolicy.ORIGIN+"/user/"+id)));},message->error(message,()->render()));
    }
    private void settingsHub(){
        toolbar("设置",true,()->render());section("账号与偏好","");
        menu("我的","编辑个人资料","昵称 / 简介 / 头像 / 空间背景",()->go(new Route("editProfile","编辑个人资料")));
        menu("设置","账号安全","更改邮箱与密码",()->go(new Route("security","账号安全")));
        menu("设置","阅读与外观","夜间主题 / 正文字号",()->go(new Route("appearance","阅读与外观")));
        menu("设置","检查更新","当前版本 0.6.2",()->updates.check(true));
    }
    private void settings(){
        toolbar("阅读与外观",true,()->render());section("让阅读更合心意","设置保存在这台设备上");
        menu("设置",library.dark()?"夜间星空 · 已开启":"日间晴空 · 已开启","点击切换明暗主题",()->{library.dark(!library.dark());render();});
        ui.space(body,16);TextView size=ui.text("正文字号  "+library.textSize()+" sp",16,ui.text,true);body.addView(size);SeekBar slider=new SeekBar(this);slider.setMax(10);slider.setProgress(library.textSize()-14);body.addView(slider,new LinearLayout.LayoutParams(-1,ui.dp(56)));TextView preview=ui.text("把喜欢的世界，装进口袋。\n每一次翻页，都是新的相遇。",library.textSize(),ui.text,false);preview.setLineSpacing(ui.dp(8),1.2f);ui.pad(preview,20,22,20,22);preview.setBackground(ui.round(ui.surface,20));body.addView(preview);slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean from){library.textSize(p+14);size.setText("正文字号  "+(p+14)+" sp");preview.setTextSize(p+14);}public void onStartTrackingTouch(SeekBar s){}public void onStopTrackingTouch(SeekBar s){}});
        section("本地数据","");body.addView(ui.button("清空阅读足迹",false,()->new AlertDialog.Builder(this).setTitle("清空阅读足迹？").setMessage("将删除这个账号在当前设备上的阅读记录。").setNegativeButton("取消",null).setPositiveButton("清空",(d,w)->{library.clearHistory();toast("阅读足迹已清空");}).show()));
        section("关于星屿","仓库 · 星屿  0.6.2");TextView about=ui.text("非官方安卓客户端。网站内容与账号服务由 cangku.moe 提供。\n\n聊天室与私信共用仓库认证，显示官网昵称、UID和头像；认证时临时使用官网会话核验，不保存该会话或密码。\n\n开通独立私信时，经你同意会把官网会话临时发送至 Cloudflare 服务验证身份，不保存该会话；官网密码不会发送。私信双方需安装并开通，消息保留7天。\n\n密码不落盘，本机会话与私信令牌由 Android Keystore 加密。\n\n网站可能调整接口。遇到特殊内容，可以通过文章底部的原文入口查看。",13,ui.muted,false);about.setLineSpacing(ui.dp(5),1.1f);body.addView(about);
    }
    private void menu(String icon,String title,String subtitle,Runnable action){
        LinearLayout item=ui.row();ui.pad(item,16,16,16,16);item.setBackground(ui.round(ui.surface,20));FrameLayout mark=new FrameLayout(this);mark.setBackground(ui.round(ui.soft,14));FrameLayout.LayoutParams ip=new FrameLayout.LayoutParams(ui.dp(23),ui.dp(23),Gravity.CENTER);mark.addView(ui.icon(icon,ui.accent),ip);item.addView(mark,new LinearLayout.LayoutParams(ui.dp(44),ui.dp(44)));LinearLayout words=ui.column();ui.pad(words,14,0,0,0);words.addView(ui.text(title,16,ui.text,true));ui.space(words,5);words.addView(ui.text(subtitle,11,ui.muted,false));item.addView(words,new LinearLayout.LayoutParams(0,-2,1));item.addView(ui.text("›",25,ui.muted,false));ui.click(item,action);body.addView(item,new LinearLayout.LayoutParams(-1,-2));ui.space(body,10);
    }
    private void logout(){
        epoch++;authoring.suspend();chat.resetAccount();direct.resetAccount();if(messageImages!=null)messageImages.clear();api.clear();user=null;library.setUser(0);history.clear();route=new Route("home","发现");login("");
    }
    private void copy(String text){((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("仓库链接",text));toast("已复制链接");}
    private void share(long id){Intent i=new Intent(Intent.ACTION_SEND);i.setType("text/plain");i.putExtra(Intent.EXTRA_TEXT,UrlPolicy.ORIGIN+"/archives/"+id);startActivity(Intent.createChooser(i,"分享作品"));}
    private void external(String value){if(!UrlPolicy.canOpen(value)){toast("此链接格式暂不支持");return;}try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(value)));}catch(ActivityNotFoundException e){toast("没有可以打开此链接的应用，可复制链接后使用");}}
    void toast(String text){Toast.makeText(this,text,Toast.LENGTH_LONG).show();}
    MessageImages messageImages(){return messageImages;}
    Ui design(){return ui;}
    LinearLayout content(){return body;}
    JSONObject account(){return user;}
    JSONArray categoryTree(){return categories;}
    ApiClient client(){return api;}
    ImageLoader pictures(){return images;}
    String currentKind(){return route.kind;}
    void reloadNative(){render();}
    void navigateNative(String kind,String title,long id){go(new Route(kind,title).id(id));}
    void manageFilter(String status,String query){route.period=status;route.query=query;route.page=1;route.scrollY=0;render();}
    void nativePagination(JSONObject page){pagination(page);}
    void renderHtml(LinearLayout parent,String html,int size){nativeHtml(parent,html,size);}
    void updateAccount(JSONObject value){
        if(user==null){user=value;return;}
        Iterator<String> keys=value.keys();while(keys.hasNext()){String key=keys.next();try{user.put(key,value.opt(key));}catch(JSONException ignored){}}
        syncChatProfile(false);
    }
    void syncChatProfile(boolean refreshSite){if(profileSync!=null)profileSync.request(refreshSite);}
    void chatProfileChanged(JSONObject profile){if(chat!=null)chat.profileChanged(profile);}
    void editorRoute(long id){route.id=id;render();}
    void afterPostSubmitted(String status){if(!history.isEmpty()&&history.peek().kind.equals("manage"))history.pop();route=new Route("manage","投稿与管理");route.period=status;render();}
    void sessionChanged(){authoring.suspend();chat.resetAccount();direct.resetAccount();if(messageImages!=null)messageImages.clear();api.clear();user=null;history.clear();route=new Route("home","发现");login("账号信息已更新，请重新登录");}
    void authorToolbar(String title,Runnable preview){
        toolbar(title,true,()->authoring.leave(()->render()));
        top.removeViewAt(top.getChildCount()-1);top.addView(ui.button("预览",false,preview),new LinearLayout.LayoutParams(-2,ui.dp(44)));
    }
    void chatToolbar(Runnable configure){toolbar("聊天室",false,configure);top.removeViewAt(top.getChildCount()-1);top.addView(ui.iconButton("设置",configure),new LinearLayout.LayoutParams(ui.dp(44),ui.dp(44)));}
    void chatContent(View panel){root.removeViewAt(1);root.addView(panel,1,new LinearLayout.LayoutParams(-1,0,1));}
    void socialToolbar(String title,Runnable refresh){toolbar(title,true,refresh);}
    void socialFilter(String type){route.period=type;route.page=1;route.scrollY=0;render();}
    void openComment(long postId,long commentId){go(new Route("comments","评论").id(postId).query(String.valueOf(commentId)));}
    private long commentFocus(){try{return Long.parseLong(route.query);}catch(Exception ignored){return 0;}}
    void privateSearch(String query){route.query=query;route.page=1;route.scrollY=0;render();}
    @Override protected void onResume(){super.onResume();if(chat!=null)chat.resume();if(direct!=null)direct.resume();if(carousel!=null)carousel.start();if(updates!=null)updates.autoCheck();}
    @Override protected void onPause(){if(authoring!=null)authoring.persist();if(chat!=null)chat.pause();if(direct!=null)direct.pause();if(carousel!=null)carousel.pause();super.onPause();}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(messageImages!=null&&messageImages.onFileResult(request,result,data))return;if(authoring!=null)authoring.onFileResult(request,result,data);}
    @Override protected void onDestroy(){closed=true;epoch++;if(profileSync!=null)profileSync.close();if(authoring!=null)authoring.persist();if(chat!=null)chat.close();if(direct!=null)direct.close();if(carousel!=null)carousel.close();if(updates!=null)updates.close();network.shutdownNow();images.close();super.onDestroy();}
}
