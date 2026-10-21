package moe.cangku.reader;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.text.*;
import java.util.*;

/** Native own-post management, editor and account forms. All writes require an explicit button. */
final class AuthoringScreens {
    private final MainActivity host;
    private final android.content.SharedPreferences drafts;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private Editor edit;
    private AiScreens aiScreen;
    private boolean dirty,busy;
    private final IdentityHashMap<View,Boolean> frozen=new IdentityHashMap<>();
    private String formKind="";
    private java.util.function.Consumer<String> uploaded;
    private String uploadType;
    private EditText contentInput,titleInput,tagsInput,thumbInput;
    private final LinkedHashMap<String,GridLayout> toolbarGroups=new LinkedHashMap<>();
    private final LinkedHashMap<String,TextView> toolbarTabs=new LinkedHashMap<>();
    private CheckBox htmlToggle;
    private EditorBuffer.History editHistory;
    private Editor historyOwner;
    private boolean applyingEdit;
    private int sourceFontSize=14;
    private TextView sourceStats;
    private View undoTool,redoTool;

    private final Runnable autosave=()->persist();
    static final String[] STATUSES={"publish","future","draft","pending","rejected","trash"};
    static final String[] STATUS_LABELS={"已发布","定时发布","草稿","待审核","已退回","回收站"};
    private static final class Editor {
        long id,user;boolean html=true;String title="",source="",thumb="",tags="",status="pending",oldStatus="",created="",version="",baseline="";
        LinkedHashSet<Long> categories=new LinkedHashSet<>();
        JSONObject json()throws JSONException{return new JSONObject().put("id",id).put("user",user).put("html",html).put("title",title).put("source",source).put("thumb",thumb).put("tags",tags).put("status",status).put("oldStatus",oldStatus).put("created",created).put("version",version).put("baseline",baseline).put("categories",new JSONArray(categories));}
        static Editor fromLocal(JSONObject x)throws JSONException{Editor e=new Editor();e.id=x.optLong("id");e.user=x.optLong("user");e.html=x.optBoolean("html",true);e.title=x.optString("title");e.source=x.optString("source");e.thumb=x.optString("thumb");e.tags=x.optString("tags");e.status=x.optString("status","pending");e.oldStatus=x.optString("oldStatus");e.created=x.optString("created");e.version=x.optString("version");e.baseline=x.optString("baseline");JSONArray cats=x.optJSONArray("categories");if(cats!=null)for(int i=0;i<cats.length();i++)e.categories.add(cats.optLong(i));return e;}
    }
    AuthoringScreens(MainActivity h){host=h;drafts=h.getSharedPreferences("authoringDrafts",Context.MODE_PRIVATE);}
    private Ui ui(){return host.design();}
    private LinearLayout body(){return host.content();}
    private AlertDialog.Builder dialog(){return new AlertDialog.Builder(new android.view.ContextThemeWrapper(host,ui().dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert));}
    private long uid(){return host.account()==null?0:host.account().optLong("id");}
    private boolean permission(String name){JSONArray p=host.account()==null?null:host.account().optJSONArray("permissions");if(p!=null)for(int i=0;i<p.length();i++){JSONObject o=p.optJSONObject(i);if(o!=null&&name.equals(o.optString("name")))return true;}return false;}
    private void setBusy(boolean value){
        if(value){if(busy)return;busy=true;freeze(body());}
        else{busy=false;for(Map.Entry<View,Boolean> entry:frozen.entrySet())entry.getKey().setEnabled(entry.getValue());frozen.clear();}
    }
    private void freeze(View view){frozen.put(view,view.isEnabled());view.setEnabled(false);if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)freeze(group.getChildAt(i));}}
    private void start(String kind){if(!kind.equals(formKind)){dirty=false;formKind=kind;}setBusy(false);}
    boolean keepDuringConfig(){return busy||dirty;}
    private void changed(){dirty=true;handler.removeCallbacks(autosave);if(formKind.equals("editor"))handler.postDelayed(autosave,650);}
    void closeAi(){if(aiScreen!=null){aiScreen.close();aiScreen=null;}}
    void persist(){handler.removeCallbacks(autosave);if(edit!=null&&formKind.equals("editor")&&dirty){try{drafts.edit().putString("user."+edit.user+".post."+edit.id,edit.json().toString()).commit();}catch(Exception ignored){}}}
    void suspend(){closeAi();persist();setBusy(false);dirty=false;formKind="";edit=null;uploaded=null;contentInput=null;editHistory=null;historyOwner=null;sourceStats=null;}
    private String key(long id){return "user."+uid()+".post."+id;}
    void leave(Runnable next){
        if(busy){host.toast("正在提交，请等待结果后再离开");return;}
        if(!dirty){formKind="";next.run();return;}
        boolean editor=formKind.equals("editor");
        dialog().setTitle(editor?"保留未提交的内容？":"离开未保存的表单？")
                .setMessage(editor?"可以保存到本机，下次继续编辑。不会提交到网站。":"当前修改尚未保存到网站。")
                .setNegativeButton("继续编辑",null).setPositiveButton(editor?"存本机并离开":"放弃修改并离开",(d,w)->{if(editor)persist();dirty=false;formKind="";edit=null;next.run();}).show();
    }
    private void title(String s){Ui u=ui();u.space(body(),18);body().addView(u.text(s,20,u.text,true));u.space(body(),12);}
    private void note(String s){TextView t=ui().text(s,13,ui().muted,false);t.setLineSpacing(ui().dp(5),1.1f);body().addView(t);ui().space(body(),12);}
    private void loading(){ProgressBar p=new ProgressBar(host);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(ui().dp(32),ui().dp(32));lp.gravity=Gravity.CENTER;lp.topMargin=ui().dp(40);body().addView(p,lp);}
    private void fail(String message){setBusy(false);note(message);body().addView(ui().button("重新载入",false,()->host.reloadNative()));}
    private EditText field(String label,String value,int lines,int max,java.util.function.Consumer<String> update){
        Ui u=ui();body().addView(u.text(label,13,u.muted,true));u.space(body(),8);EditText e=new EditText(host);e.setTextSize(15);e.setTextColor(u.text);e.setHintTextColor(u.muted);e.setHint(label);e.setText(value);e.setGravity(Gravity.TOP|Gravity.LEFT);u.pad(e,16,14,16,14);e.setBackground(u.round(u.surface,16));e.setSingleLine(lines==1);if(lines>1){e.setMinLines(lines);e.setMaxLines(Math.max(lines,18));e.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE|android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);}e.setFilters(new InputFilter[]{new InputFilter.LengthFilter(max)});body().addView(e,new LinearLayout.LayoutParams(-1,lines==1?u.dp(54):-2));u.space(body(),16);
        e.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int f){}public void onTextChanged(CharSequence s,int st,int before,int count){update.accept(s.toString());changed();}public void afterTextChanged(Editable s){}});return e;
    }
    private TextView button(String label,Runnable action){TextView b=ui().button(label,false,action);body().addView(b,new LinearLayout.LayoutParams(-1,-2));ui().space(body(),10);return b;}

    void manage(String status,String query,int page){
        start("manage");host.toolbar("投稿与管理",true,()->host.reloadNative());
        if(!Arrays.asList(STATUSES).contains(status))status="publish";final String selected=status;
        note("管理自己的作品，查看草稿、审核进度与退回原因。");button("＋ 新建投稿",()->host.navigateNative("editor","新建投稿",0));
        HorizontalScrollView scroller=new HorizontalScrollView(host);scroller.setHorizontalScrollBarEnabled(false);LinearLayout chips=ui().row();for(int i=0;i<STATUSES.length;i++){String value=STATUSES[i];TextView c=ui().chip(STATUS_LABELS[i],status.equals(value),()->host.manageFilter(value,query));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,-2);p.setMargins(0,0,ui().dp(8),0);chips.addView(c,p);}scroller.addView(chips);body().addView(scroller);ui().space(body(),16);
        EditText search=new EditText(host);search.setSingleLine(true);search.setText(query);search.setHint("搜索自己的投稿");search.setTextColor(ui().text);search.setHintTextColor(ui().muted);ui().pad(search,14,10,14,10);search.setBackground(ui().round(ui().surface,16));search.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);body().addView(search,new LinearLayout.LayoutParams(-1,ui().dp(52)));search.setOnEditorActionListener((v,action,event)->{if(action==android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH){host.manageFilter(selected,search.getText().toString().trim());return true;}return false;});ui().space(body(),16);
        LinearLayout list=ui().column();body().addView(list);ProgressBar spinner=new ProgressBar(host);list.addView(spinner,new LinearLayout.LayoutParams(ui().dp(30),ui().dp(30)));
        Map<String,String> params=ApiClient.params("user_id",String.valueOf(uid()),"status",status,"page",String.valueOf(page),"per_page","15","include","categories:simple,meta:include(reject_reason)","simple","1");if(!query.isEmpty())params.put("search",query);
        host.task(()->host.client().get("post/list",params),result->{list.removeAllViews();JSONArray posts=result.optJSONArray("data");int count=0;if(posts!=null)for(int i=0;i<posts.length();i++){JSONObject post=posts.optJSONObject(i);if(post!=null&&post.optLong("user_id")==uid()){managedCard(list,post,selected);count++;}}if(count==0){TextView empty=ui().text("✦  这个状态下还没有投稿",15,ui().muted,false);ui().pad(empty,10,32,10,32);list.addView(empty);}JSONObject meta=result.optJSONObject("meta");if(meta!=null&&meta.optJSONObject("pagination")!=null)host.nativePagination(meta.getJSONObject("pagination"));},message->{list.removeAllViews();list.addView(ui().text(message,14,ui().muted,false));});
    }
    private void managedCard(LinearLayout parent,JSONObject post,String status){
        Ui u=ui();LinearLayout card=u.column();u.pad(card,16,18,16,16);card.setBackground(u.round(u.surface,20));TextView name=u.text(post.optString("title"),17,u.text,true);name.setMaxLines(3);name.setEllipsize(TextUtils.TruncateAt.END);card.addView(name);u.space(card,8);card.addView(u.text(label(status)+" · "+date(post.optString("created_at")),12,u.muted,false));
        if(status.equals("rejected")){JSONArray meta=post.optJSONArray("meta");if(meta!=null)for(int i=0;i<meta.length();i++){JSONObject m=meta.optJSONObject(i);if(m!=null&&m.optString("key").equals("reject_reason")){u.space(card,10);card.addView(u.text("退回说明："+m.optString("value"),13,u.pink,false));}}}
        u.space(card,14);LinearLayout actions=u.row();long id=post.optLong("id");TextView editButton=u.button(status.equals("trash")?"恢复投稿":"继续编辑",false,()->{if(status.equals("trash"))mutatePost(post,"post/restore","恢复这篇投稿？");else host.navigateNative("editor","编辑投稿",id);});actions.addView(editButton,new LinearLayout.LayoutParams(0,-2,1));
        if(!status.equals("trash")){TextView delete=u.button("移入回收站",false,()->mutatePost(post,"post/delete","将这篇投稿移入回收站？"));delete.setEnabled(permission("delete_posts"));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-2,1);p.leftMargin=u.dp(8);actions.addView(delete,p);}else editButton.setEnabled(permission("restore_posts"));card.addView(actions);
        if(status.equals("publish")){u.space(card,8);TextView read=u.button("查看文章",false,()->host.navigateNative("article","文章",id));card.addView(read);}
        parent.addView(card,new LinearLayout.LayoutParams(-1,-2));u.space(parent,12);
    }
    private void mutatePost(JSONObject post,String endpoint,String question){
        if(post.optLong("user_id")!=uid())return;
        dialog().setTitle(question).setMessage(post.optString("title")).setNegativeButton("取消",null).setPositiveButton("确认",(d,w)->{setBusy(true);host.task(()->host.client().post(endpoint,new JSONObject().put("id",post.optLong("id"))),result->{setBusy(false);host.toast("操作成功");host.reloadNative();},message->{setBusy(false);host.toast(message);});}).show();
    }
    private String label(String status){for(int i=0;i<STATUSES.length;i++)if(STATUSES[i].equals(status))return STATUS_LABELS[i];return status;}
    private String date(String s){return s.length()>10?s.substring(0,10):s;}

    void editor(long id){
        boolean same=edit!=null&&edit.id==id&&edit.user==uid()&&formKind.equals("editor");start("editor");
        host.authorToolbar(id==0?"新建投稿":"编辑投稿",this::previewEditor);
        if(same){editorForm();return;}
        edit=null;dirty=false;
        if(id==0){edit=new Editor();edit.user=uid();edit.html=false;edit.status=permission("publish_posts")?"publish":"pending";editorForm();offerRestore(0);return;}
        loading();host.task(()->host.client().get("post/info",ApiClient.params("id",String.valueOf(id),"include","user,categories:simple,tags","exclude_view","1")).getJSONObject("data"),post->{
            if(post.optLong("user_id")!=uid()){body().removeAllViews();note("只能在这里编辑自己的投稿。");return;}
            edit=new Editor();edit.id=id;edit.user=uid();edit.title=post.optString("title");edit.source=post.optString("content");edit.thumb=post.optString("thumb","");edit.status=post.optString("status");edit.oldStatus=edit.status;edit.created=siteDate(post.optString("created_at"));edit.version=post.optString("updated_at");edit.baseline=fingerprint(post);
            JSONArray cats=post.optJSONArray("categories");if(cats!=null)for(int i=0;i<cats.length();i++)edit.categories.add(cats.getJSONObject(i).optLong("id"));JSONArray tags=post.optJSONArray("tags");ArrayList<String> names=new ArrayList<>();if(tags!=null)for(int i=0;i<tags.length();i++)names.add(tags.getJSONObject(i).optString("name"));edit.tags=String.join(", ",names);
            body().removeAllViews();editorForm();offerRestore(id);
        },this::fail);
    }
    private String siteDate(String iso){
        try{SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd HH:mm:ss",Locale.ROOT);f.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));return f.format(java.util.Date.from(java.time.Instant.parse(iso)));}catch(Exception e){return iso.matches("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}")?iso:"";}
    }
    private void offerRestore(long id){
        String saved=drafts.getString(key(id),null);if(saved==null)return;
        try{Editor local=Editor.fromLocal(new JSONObject(saved));if(local.user!=uid()||local.id!=id)return;
            dialog().setTitle("发现本机草稿").setMessage("是否恢复上次未提交的编辑？\n"+local.title).setNegativeButton("使用网站内容",(d,w)->drafts.edit().remove(key(id)).apply()).setPositiveButton("恢复本机草稿",(d,w)->{edit=local;dirty=true;body().removeAllViews();editorForm();}).show();
        }catch(Exception ignored){}
    }
    private void editorForm(){
        if(edit==null)return;
        note(edit.id==0?"在这里创作新投稿。内容会自动保存在本机，点击提交后才会同步至网站。":"编辑保留原始 HTML 与下载短代码。点击预览可查看正文效果。");
        titleInput=field("标题（最多500字）",edit.title,2,500,s->edit.title=s);
        CheckBox html=new CheckBox(host);htmlToggle=html;html.setText("使用 HTML 源码编辑");html.setTextColor(ui().muted);html.setChecked(edit.html);body().addView(html);
        html.setOnCheckedChangeListener((view,checked)->{
            if(checked==edit.html)return;
            if(!checked){view.setChecked(true);host.toast("已有 HTML 排版时保留源码模式，可新建纯文本投稿");return;}
            applyEdit(captureEdit().asHtml());
        });
        buildToolbar();
        sourceStats=ui().text("",11,ui().muted,false);body().addView(sourceStats);ui().space(body(),8);
        contentInput=field("正文",edit.source,12,1000000,s->edit.source=s);contentInput.setTypeface(Typeface.MONOSPACE);sourceFontSize=drafts.getInt("editor.font."+uid(),14);contentInput.setTextSize(sourceFontSize);
        if(historyOwner!=edit||editHistory==null||!editHistory.current.text.equals(edit.source)){editHistory=new EditorBuffer.History(captureEdit());historyOwner=edit;}
        contentInput.addTextChangedListener(new TextWatcher(){
            public void beforeTextChanged(CharSequence value,int start,int count,int after){if(!applyingEdit&&editHistory!=null)editHistory.select(new EditorBuffer.State(value.toString(),Math.max(0,contentInput.getSelectionStart()),Math.max(0,contentInput.getSelectionEnd()),edit.html));}
            public void onTextChanged(CharSequence value,int start,int before,int count){}
            public void afterTextChanged(Editable value){if(!applyingEdit&&editHistory!=null)editHistory.record(captureEdit(),true,android.os.SystemClock.uptimeMillis());refreshEditorTools();}
        });
        contentInput.setOnTouchListener((v,event)->{handler.post(this::refreshEditorTools);return false;});refreshEditorTools();
        EditText thumb=field("封面图片 URL",edit.thumb,1,3000,s->edit.thumb=s);thumbInput=thumb;
        button("上传封面图片",()->chooseImage("post",url->{edit.thumb=url;thumb.setText(url);changed();}));
        TextView categories=ui().button(categorySummary(),false,()->selectCategories());body().addView(categories,new LinearLayout.LayoutParams(-1,-2));ui().space(body(),16);
        tagsInput=field("标签（用逗号分隔）",edit.tags,2,2000,s->edit.tags=s);
        ArrayList<String> values=new ArrayList<>(),labels=new ArrayList<>();values.add("draft");labels.add("草稿");values.add("pending");labels.add("提交审核");if(permission("publish_posts")){values.add("publish");labels.add("发布 / 更新");values.add("future");labels.add("定时发布");}if(edit.oldStatus.equals("rejected")){values.clear();labels.clear();values.add("pending");labels.add("修改并重新提交审核");}
        if(!values.contains(edit.status)){edit.status=edit.oldStatus.equals("rejected")?"pending":"draft";}
        body().addView(ui().text("投稿状态",13,ui().muted,true));ui().space(body(),8);Spinner status=new Spinner(host);ArrayAdapter<String> adapter=new ArrayAdapter<>(host,android.R.layout.simple_spinner_dropdown_item,labels);status.setAdapter(adapter);status.setSelection(values.indexOf(edit.status));status.setBackground(ui().round(ui().surface,16));body().addView(status,new LinearLayout.LayoutParams(-1,ui().dp(54)));ui().space(body(),16);
        status.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){public void onItemSelected(android.widget.AdapterView<?> p,View view,int position,long id){String value=values.get(position);if(!value.equals(edit.status)){edit.status=value;changed();}}public void onNothingSelected(android.widget.AdapterView<?> p){}});
        EditText date=field("定时发布时间（上海时间，可选）",edit.status.equals("future")?edit.created:"",1,19,s->{edit.created=s;});date.setHint("yyyy-MM-dd HH:mm:ss");button("选择定时发布时间",()->pickDate(date));
        note("定时投稿请选择未来时间；普通发布不填写时保留原发布时间。回收站中的内容需先恢复。");
        TextView local=ui().button("保存到本机",false,()->{dirty=true;persist();host.toast("已保存到本机，尚未提交网站");});body().addView(local,new LinearLayout.LayoutParams(-1,-2));ui().space(body(),10);
        TextView submit=ui().button(edit.id==0?"提交投稿":"保存修改",true,this::submitEditor);body().addView(submit,new LinearLayout.LayoutParams(-1,ui().dp(54)));ui().space(body(),18);
    }
    private EditorBuffer.State captureEdit(){String source=contentInput==null?edit.source:contentInput.getText().toString();return new EditorBuffer.State(source,contentInput==null?source.length():Math.max(0,contentInput.getSelectionStart()),contentInput==null?source.length():Math.max(0,contentInput.getSelectionEnd()),edit.html);}
    private void renderEdit(EditorBuffer.State next){
        applyingEdit=true;edit.source=next.text;edit.html=next.html;if(htmlToggle!=null)htmlToggle.setChecked(edit.html);contentInput.setText(next.text);contentInput.setSelection(next.a,next.b);applyingEdit=false;changed();refreshEditorTools();
    }
    private void applyEdit(EditorBuffer.State next){
        if(busy||edit==null||contentInput==null)return;if(next.text.length()>1000000){host.toast("正文请控制在100万字符以内");return;}
        if(editHistory!=null){editHistory.select(captureEdit());editHistory.record(next,false,android.os.SystemClock.uptimeMillis());}renderEdit(next);
    }
    private void format(String before,String after){format(before,after,"文字");}
    private void format(String before,String after,String placeholder){applyEdit(EditorBuffer.wrap(captureEdit(),before,after,placeholder));}
    private void insert(String html){applyEdit(EditorBuffer.insert(captureEdit(),html));}
    private void undoEdit(boolean redo){if(editHistory==null||busy)return;editHistory.select(captureEdit());EditorBuffer.State next=redo?editHistory.redo():editHistory.undo();if(next!=null)renderEdit(next);}
    private void refreshEditorTools(){
        if(sourceStats!=null&&edit!=null&&contentInput!=null){EditorBuffer.State s=captureEdit();sourceStats.setText("源码 "+s.text.codePointCount(0,s.text.length())+" 字符 · 选中 "+(s.b-s.a)+" · 编辑字号 "+sourceFontSize);}
        if(undoTool!=null){undoTool.setEnabled(editHistory!=null&&editHistory.canUndo());undoTool.setAlpha(undoTool.isEnabled()?1f:.35f);}
        if(redoTool!=null){redoTool.setEnabled(editHistory!=null&&editHistory.canRedo());redoTool.setAlpha(redoTool.isEnabled()?1f:.35f);}
    }
    private String toolGroup(String glyph){
        if(Arrays.asList("ai","undo","redo","bold","italic","link","image","size").contains(glyph))return "常用";
        if(Arrays.asList("underline","strike","h1","h2","h3","paragraph","list","ordered","quote","textColor","fillColor","left","center","right","justify").contains(glyph))return "排版";
        if(Arrays.asList("return","imageUrl","download","table","code","codeBlock","rule","entity","date").contains(glyph))return "插入";
        return "更多";
    }
    private void chooseToolGroup(String name){for(Map.Entry<String,GridLayout> e:toolbarGroups.entrySet())e.getValue().setVisibility(e.getKey().equals(name)?View.VISIBLE:View.GONE);for(Map.Entry<String,TextView> e:toolbarTabs.entrySet()){boolean selected=e.getKey().equals(name);e.getValue().setTextColor(selected?ui().accent:ui().muted);e.getValue().setBackground(ui().round(selected?ui().soft:ui().surface,12));e.getValue().setSelected(selected);}}
    private FrameLayout editorTool(GridLayout ignored,String label,String glyph,Runnable action){
        GridLayout grid=toolbarGroups.get(toolGroup(glyph));FrameLayout button=new FrameLayout(host);button.setContentDescription(label);button.setTooltipText(label);button.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x227D69EB),ui().round(ui().surface,10),null));
        EditorToolIcon icon=new EditorToolIcon(host,glyph,ui().text);FrameLayout.LayoutParams iconParams=new FrameLayout.LayoutParams(ui().dp(23),ui().dp(23),Gravity.TOP|Gravity.CENTER_HORIZONTAL);iconParams.topMargin=ui().dp(10);button.addView(icon,iconParams);
        TextView caption=ui().text(label,11,ui().text,false);caption.setGravity(Gravity.CENTER);caption.setMaxLines(2);caption.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,ui().dp((int)(34*Math.max(1,host.getResources().getConfiguration().fontScale))),Gravity.BOTTOM);cp.bottomMargin=ui().dp(3);button.addView(caption,cp);ui().click(button,()->{if(!busy)action.run();});button.setOnLongClickListener(v->{host.toast(label+"："+toolDescription(glyph));return true;});
        int index=grid.getChildCount(),columns=grid.getColumnCount();GridLayout.LayoutParams params=new GridLayout.LayoutParams(GridLayout.spec(index/columns),GridLayout.spec(index%columns,1f));params.width=0;params.height=ui().dp((int)(78*Math.max(1,host.getResources().getConfiguration().fontScale)));params.setMargins(ui().dp(2),ui().dp(2),ui().dp(2),ui().dp(2));grid.addView(button,params);return button;
    }
    private String toolDescription(String glyph){switch(glyph){case "ai":return "从作品链接整理草稿，预览后自行导入";case "undo":return "恢复上一步正文修改";case "redo":return "重新应用已撤销的正文修改";case "size":return "调整选中文字在文章中的字号";case "zoomIn":case "zoomOut":return "仅改变本机编辑框显示字号";case "image":return "选择本机图片上传并插入正文";case "imageUrl":return "通过HTTPS图片链接插入图片";case "codeBlock":return "选择编程语言，插入多行代码";case "code":return "将选中文字标记为行内代码";case "clear":return "移除选中内容的排版格式";case "find":return "在正文查找文字，或替换当前/全部匹配";case "date":return "插入上海时区的今天日期";case "entity":return "插入HTML特殊字符示例，避免尖括号被当成标签";case "return":return "在光标处插入换行";case "rule":return "在段落间插入水平分隔线";case "table":return "插入可编辑的表格模板";case "textColor":return "选择选中文字的颜色";case "fillColor":return "为选中文字添加背景色";case "download":return "填写下载地址及提取信息生成下载卡片";default:return "应用到选中文字；未选中时插入对应格式";}}
    private void aiAssistant(){final Editor target=edit;if(busy||target==null)return;aiScreen=new AiScreens(host,value->{if(edit!=target||uid()!=target.user||contentInput==null)return;try{JSONObject d=value.draft;String incoming=value.body?AiClient.body(d):null;if(incoming!=null&&value.append&&!edit.source.isEmpty())incoming=edit.source+"\n"+incoming;if(incoming!=null&&incoming.length()>1000000)throw new java.io.IOException("导入后超出编辑器容量，现有内容未修改");if(value.title)titleInput.setText(d.getString("title"));if(value.tags){JSONArray t=d.getJSONArray("tags");ArrayList<String> tags=new ArrayList<>();for(int i=0;i<t.length();i++)tags.add(t.getString(i));tagsInput.setText(String.join(", ",tags));}if(value.cover){JSONArray list=d.getJSONArray("sources");for(int i=0;i<list.length();i++){String cover=list.getJSONObject(i).optString("cover");if(!cover.isEmpty()){thumbInput.setText(cover);break;}}}if(incoming!=null){applyEdit(new EditorBuffer.State(incoming,incoming.length(),incoming.length(),true));}changed();persist();host.toast("已导入本机草稿，尚未提交网站");}catch(Exception e){host.toast(e instanceof java.io.IOException?e.getMessage():"导入失败，请检查草稿");}});aiScreen.show();}
    private void buildToolbar(){
        toolbarGroups.clear();toolbarTabs.clear();LinearLayout panel=ui().column();panel.setBackground(ui().round(ui().surface,16));ui().pad(panel,8,10,8,8);LinearLayout tabs=ui().row();panel.addView(tabs,new LinearLayout.LayoutParams(-1,-2));
        int columns=Math.max(3,Math.min(6,(host.getResources().getConfiguration().screenWidthDp-48)/(int)(78*Math.max(1,host.getResources().getConfiguration().fontScale))));
        for(String name:new String[]{"常用","排版","插入","更多"}){TextView tab=ui().text(name,13,ui().muted,true);tab.setGravity(Gravity.CENTER);tab.setMinHeight(ui().dp(42));tab.setContentDescription(name+"工具组");tabs.addView(tab,new LinearLayout.LayoutParams(0,-2,1));toolbarTabs.put(name,tab);ui().click(tab,()->chooseToolGroup(name));GridLayout group=new GridLayout(host);group.setColumnCount(columns);toolbarGroups.put(name,group);panel.addView(group,new LinearLayout.LayoutParams(-1,-2));}
        GridLayout grid=toolbarGroups.get("常用");body().addView(panel,new LinearLayout.LayoutParams(-1,-2));editorTool(grid,"AI助手","ai",this::aiAssistant);
        undoTool=editorTool(grid,"撤销","undo",()->undoEdit(false));redoTool=editorTool(grid,"重做","redo",()->undoEdit(true));
        editorTool(grid,"加粗","bold",()->format("<strong>","</strong>","加粗文字"));editorTool(grid,"斜体","italic",()->format("<em>","</em>","斜体文字"));
        editorTool(grid,"下划线","underline",()->format("<u>","</u>"));editorTool(grid,"删除线","strike",()->format("<del>","</del>"));
        for(int n=1;n<=3;n++){final int level=n;editorTool(grid,n+"级标题","h"+n,()->format("<h"+level+">","</h"+level+">","标题"));}
        editorTool(grid,"段落","paragraph",()->format("<p>","</p>","段落文字"));editorTool(grid,"插入换行","return",()->insert("<br>"));
        editorTool(grid,"无序列表","list",()->applyEdit(EditorBuffer.list(captureEdit(),false)));editorTool(grid,"有序列表","ordered",()->applyEdit(EditorBuffer.list(captureEdit(),true)));editorTool(grid,"引用","quote",()->format("<blockquote>","</blockquote>","引用文字"));
        editorTool(grid,"插入链接","link",this::insertLink);editorTool(grid,"上传正文图片","image",()->chooseImage("post",url->insert("<p><img src=\""+ReaderContent.escape(url)+"\"></p>")));editorTool(grid,"插入网络图片","imageUrl",this::insertNetworkImage);editorTool(grid,"下载卡片","download",this::insertDownload);
        editorTool(grid,"插入表格","table",()->insert(EditorHints.ITEMS[10][2]));editorTool(grid,"行内代码","code",()->format("<code>","</code>","code"));editorTool(grid,"插入代码块","codeBlock",this::insertCode);editorTool(grid,"水平分隔线","rule",()->insert("\n<hr>\n"));
        editorTool(grid,"正文字号","size",this::chooseFontSize);editorTool(grid,"文字颜色","textColor",()->chooseColor(false));editorTool(grid,"文字背景色","fillColor",()->chooseColor(true));
        editorTool(grid,"左对齐","left",()->format("<p style=\"text-align:left\">","</p>"));editorTool(grid,"居中","center",()->format("<p style=\"text-align:center\">","</p>"));editorTool(grid,"右对齐","right",()->format("<p style=\"text-align:right\">","</p>"));editorTool(grid,"两端对齐","justify",()->format("<p style=\"text-align:justify\">","</p>"));
        editorTool(grid,"上标","sup",()->format("<sup>","</sup>"));editorTool(grid,"下标","sub",()->format("<sub>","</sub>"));editorTool(grid,"增加缩进","indent",()->applyEdit(EditorBuffer.indent(captureEdit(),false)));editorTool(grid,"减少缩进","outdent",()->applyEdit(EditorBuffer.indent(captureEdit(),true)));
        editorTool(grid,"清除选区格式","clear",()->{EditorBuffer.State v=captureEdit();if(v.a==v.b){host.toast("请先选择需要清除格式的正文");return;}if(!v.html)return;String plain=Html.fromHtml(v.text.substring(v.a,v.b),Html.FROM_HTML_MODE_COMPACT).toString();String replacement=ReaderContent.escape(plain).replace("\n","<br>");applyEdit(new EditorBuffer.State(v.text.substring(0,v.a)+replacement+v.text.substring(v.b),v.a,v.a+replacement.length(),v.html));});
        editorTool(grid,"HTML特殊字符","entity",()->insert("&lt;标签&gt; &amp; 文本"));editorTool(grid,"插入当前日期","date",()->{SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd",Locale.ROOT);f.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));insert(f.format(new Date()));});editorTool(grid,"查找与替换","find",this::findReplace);
        editorTool(grid,"减小编辑字号","zoomOut",()->editorZoom(-1));editorTool(grid,"增大编辑字号","zoomIn",()->editorZoom(1));chooseToolGroup("常用");ui().space(body(),8);note("点击分组选择工具，长按按钮查看说明。正文字号影响文章；编辑字号仅调整本机输入框。");
    }
    private void editorZoom(int delta){sourceFontSize=Math.max(10,Math.min(28,sourceFontSize+delta));contentInput.setTextSize(sourceFontSize);drafts.edit().putInt("editor.font."+uid(),sourceFontSize).apply();refreshEditorTools();}
    private void chooseFontSize(){String[] labels={"12 px","14 px","16 px","18 px","20 px","24 px","28 px","32 px","36 px","48 px"};int[] sizes={12,14,16,18,20,24,28,32,36,48};dialog().setTitle("正文字号 · 应用于选区").setItems(labels,(d,i)->format("<span style=\"font-size:"+sizes[i]+"px\">","</span>","调整字号的文字")).setNegativeButton("取消",null).show();}
    private void chooseColor(boolean highlight){
        String[] colors={"#322c48","#8a6adb","#e797b7","#e05252","#e58b32","#9b8435","#3a926c","#278da0","#4078ce","#795aaf","#777777","#ffffff"};
        GridLayout grid=new GridLayout(host);grid.setColumnCount(4);ui().pad(grid,20,16,20,16);AlertDialog picker=dialog().setTitle(highlight?"文字背景色":"文字颜色").setView(grid).setNegativeButton("取消",null).create();
        for(int i=0;i<colors.length;i++){final String color=colors[i];View swatch=new View(host);android.graphics.drawable.GradientDrawable shape=ui().round(Color.parseColor(color),8);shape.setStroke(ui().dp(1),ui().line);swatch.setBackground(shape);swatch.setContentDescription(color);swatch.setTooltipText(color);ui().click(swatch,()->{format("<span style=\""+(highlight?"background-color":"color")+":"+color+"\">","</span>");picker.dismiss();});GridLayout.LayoutParams p=new GridLayout.LayoutParams(GridLayout.spec(i/4),GridLayout.spec(i%4,1f));p.width=0;p.height=ui().dp(48);p.setMargins(ui().dp(5),ui().dp(5),ui().dp(5),ui().dp(5));grid.addView(swatch,p);}picker.show();
    }
    private void insertNetworkImage(){LinearLayout box=ui().column();ui().pad(box,20,12,20,12);EditText alt=dialogInput(box,"图片说明"),url=dialogInput(box,"HTTPS 图片地址");AlertDialog d=dialog().setTitle("插入网络图片").setView(box).setNegativeButton("取消",null).setPositiveButton("插入",null).create();d.setOnShowListener(x->d.getButton(-1).setOnClickListener(v->{String link=url.getText().toString().trim();if(!UrlPolicy.isImage(link)){url.setError("请输入有效HTTPS图片地址");return;}insert("<p><img src=\""+ReaderContent.escape(link)+"\" alt=\""+ReaderContent.escape(alt.getText().toString())+"\"></p>");d.dismiss();}));d.show();}
    private void findReplace(){
        LinearLayout box=ui().column();ui().pad(box,20,12,20,12);EditText find=dialogInput(box,"查找文字"),replacement=dialogInput(box,"替换为");find.setFilters(new InputFilter[]{new InputFilter.LengthFilter(300)});replacement.setFilters(new InputFilter[]{new InputFilter.LengthFilter(2000)});TextView status=ui().text("区分大小写，仅修改当前本机正文",12,ui().muted,false);box.addView(status);TextView all=ui().button("全部替换",false,()->{});box.addView(all);
        java.util.function.Consumer<String> run=mode->{String needle=find.getText().toString(),replace=replacement.getText().toString();if(needle.isEmpty()){status.setText("请填写查找文字");return;}try{EditorBuffer.State v=captureEdit();if(mode.equals("all")){String result=EditorBuffer.replaceAll(v.text,needle,replace);int count=0,at=0;while((at=v.text.indexOf(needle,at))>=0){count++;at+=needle.length();}applyEdit(new EditorBuffer.State(result,0,0,v.html));status.setText("已替换 "+count+" 处，可使用撤销恢复");return;}
            if(mode.equals("one")&&v.text.substring(v.a,v.b).equals(needle)){applyEdit(new EditorBuffer.State(v.text.substring(0,v.a)+replace+v.text.substring(v.b),v.a,v.a+replace.length(),v.html));status.setText("已替换当前匹配");return;}int at=v.text.indexOf(needle,v.b);if(at<0)at=v.text.indexOf(needle);if(at<0){status.setText("没有找到匹配内容");return;}contentInput.setSelection(at,at+needle.length());refreshEditorTools();status.setText("已选中第 "+(at+1)+" 个字符处的匹配");
        }catch(Exception error){status.setText(error.getMessage());}};
        ui().click(all,()->run.accept("all"));AlertDialog d=dialog().setTitle("查找与替换").setView(box).setNegativeButton("关闭",null).setNeutralButton("替换当前",null).setPositiveButton("查找下一个",null).create();d.setOnShowListener(x->{d.getButton(-1).setOnClickListener(v->run.accept("find"));d.getButton(-3).setOnClickListener(v->run.accept("one"));});d.show();
    }
    private void insertLink(){
        LinearLayout box=ui().column();ui().pad(box,20,8,20,8);EditText name=dialogInput(box,"链接文字"),url=dialogInput(box,"https://...");
        AlertDialog d=dialog().setTitle("插入链接").setView(box).setNegativeButton("取消",null).setPositiveButton("插入",null).create();d.setOnShowListener(x->d.getButton(-1).setOnClickListener(v->{String link=url.getText().toString().trim();if(!UrlPolicy.canOpen(link)){url.setError("请输入有效链接");return;}insert("<a href=\""+ReaderContent.escape(link)+"\">"+ReaderContent.escape(name.getText().toString())+"</a>");d.dismiss();}));d.show();
    }
    private void insertCode(){
        LinearLayout box=ui().column();ui().pad(box,20,12,20,12);Spinner language=new Spinner(host);language.setAdapter(new ArrayAdapter<String>(host,android.R.layout.simple_spinner_dropdown_item,EditorHints.LANGUAGE_NAMES));box.addView(language);
        EditText code=new EditText(host);code.setHint("粘贴代码，例如 #include <iostream>");code.setTextColor(ui().text);code.setHintTextColor(ui().muted);code.setGravity(Gravity.TOP);code.setTypeface(android.graphics.Typeface.MONOSPACE);code.setTextSize(14);code.setMinLines(6);code.setMaxLines(12);box.addView(code,new LinearLayout.LayoutParams(-1,-2));
        AlertDialog d=dialog().setTitle("插入代码块").setView(box).setNegativeButton("取消",null).setPositiveButton("插入",null).create();d.setOnShowListener(x->d.getButton(-1).setOnClickListener(v->{String value=code.getText().toString();if(value.trim().isEmpty()){code.setError("请先输入代码");return;}if(value.length()>100000){code.setError("代码块请控制在10万字以内");return;}insert(EditorHints.codeBlock(EditorHints.LANGUAGES[language.getSelectedItemPosition()],value));d.dismiss();}));d.show();
    }
    private void insertDownload(){
        LinearLayout box=ui().column();ui().pad(box,20,8,20,8);EditText name=dialogInput(box,"资源标题"),platform=dialogInput(box,"网盘名称"),url=dialogInput(box,"下载链接 / 二维码图片 URL"),info=dialogInput(box,"提取码与资源说明");
        AlertDialog d=dialog().setTitle("插入下载卡片").setView(box).setNegativeButton("取消",null).setPositiveButton("插入",null).create();d.setOnShowListener(x->d.getButton(-1).setOnClickListener(v->{String link=url.getText().toString().trim();if(!UrlPolicy.canOpen(link)){url.setError("请输入有效链接");return;}String title=name.getText().toString().replace("]","］");String description=info.getText().toString().replace("]","］");String label=platform.getText().toString().replace("|"," ").replace("]","］");insert("<p>[dlbox title=\""+ReaderContent.escape(title)+"\" info=\""+ReaderContent.escape(description)+"\" link1=\""+ReaderContent.escape(label+"|"+link)+"\"][/dlbox]</p>");d.dismiss();}));d.show();
    }
    private EditText dialogInput(LinearLayout box,String hint){EditText e=new EditText(host);e.setHint(hint);e.setTextColor(ui().text);e.setHintTextColor(ui().muted);e.setTextSize(14);e.setSingleLine(true);box.addView(e,new LinearLayout.LayoutParams(-1,ui().dp(54)));return e;}
    private String categorySummary(){if(edit==null||edit.categories.isEmpty())return "选择分类与子分类";return "已选 "+edit.categories.size()+" 个分类 · 点击修改";}
    private void flatten(JSONArray source,String prefix,List<JSONObject> out,List<String> labels){if(source==null)return;for(int i=0;i<source.length();i++){JSONObject c=source.optJSONObject(i);if(c==null)continue;out.add(c);labels.add(prefix+c.optString("name"));flatten(c.optJSONArray("children"),prefix+"  › ",out,labels);}}
    private void selectCategories(){
        if(edit==null)return;
        if(host.categoryTree().length()==0){host.task(()->host.client().get("category/list",ApiClient.params("all","1","type","post")).getJSONArray("data"),list->categoryDialog(list),host::toast);return;}
        categoryDialog(host.categoryTree());
    }
    private void categoryDialog(JSONArray tree){List<JSONObject> list=new ArrayList<>();List<String> labels=new ArrayList<>();flatten(tree,"",list,labels);boolean[] selected=new boolean[list.size()];for(int i=0;i<selected.length;i++)selected[i]=edit.categories.contains(list.get(i).optLong("id"));dialog().setTitle("选择分类").setMultiChoiceItems(labels.toArray(new String[0]),selected,(d,index,value)->selected[index]=value).setNegativeButton("取消",null).setPositiveButton("确定",(d,w)->{edit.categories.clear();for(int i=0;i<selected.length;i++)if(selected[i])edit.categories.add(list.get(i).optLong("id"));changed();body().removeAllViews();editorForm();}).show();}
    private void pickDate(EditText field){Calendar now=Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"));new DatePickerDialog(host,(v,year,month,day)->new TimePickerDialog(host,(clock,hour,minute)->field.setText(String.format(Locale.ROOT,"%04d-%02d-%02d %02d:%02d:00",year,month+1,day,hour,minute)),now.get(Calendar.HOUR_OF_DAY),now.get(Calendar.MINUTE),true).show(),now.get(Calendar.YEAR),now.get(Calendar.MONTH),now.get(Calendar.DAY_OF_MONTH)).show();}
    private void previewEditor(){
        if(edit==null)return;ReaderContent parsed=ReaderContent.parse(AuthoringRules.bodyHtml(edit.source,edit.html));ScrollView scroll=new ScrollView(host);LinearLayout content=ui().column();ui().pad(content,22,20,22,22);scroll.addView(content);content.addView(ui().text(edit.title,23,ui().text,true));ui().space(content,18);host.renderHtml(content,parsed.html,17);for(ReaderContent.Resource resource:parsed.resources){ui().space(content,16);content.addView(ui().text(resource.title+"\n"+resource.info,15,ui().accent,true));for(Map.Entry<String,String> link:resource.links.entrySet())content.addView(ui().text(link.getKey()+" · "+link.getValue(),12,ui().muted,false));}
        dialog().setTitle("本机预览 · 尚未提交").setView(scroll).setPositiveButton("继续编辑",null).show();
    }
    private void submitEditor(){
        if(edit==null||busy)return;
        if(edit.title.trim().isEmpty()){host.toast("请填写标题");return;}if(edit.source.trim().isEmpty()){host.toast("请填写正文");return;}
        if(!edit.thumb.isEmpty()&&!UrlPolicy.isImage(edit.thumb)){host.toast("封面请填写有效的 HTTPS 图片地址");return;}
        if(edit.status.equals("future")){try{if(AuthoringRules.scheduleMillis(edit.created)<=System.currentTimeMillis())throw new IllegalArgumentException("定时发布时间必须晚于现在");}catch(IllegalArgumentException e){host.toast(e.getMessage());return;}}
        final Editor snapshot;try{snapshot=Editor.fromLocal(edit.json());}catch(Exception e){host.toast("无法读取编辑内容");return;}
        dialog().setTitle(snapshot.id==0?"确认提交投稿？":"确认保存修改？").setMessage(snapshot.title+"\n状态："+label(snapshot.status)+(snapshot.categories.isEmpty()?"\n尚未选择分类":"")+(snapshot.status.equals("future")?"\n上海时间："+snapshot.created:"")).setNegativeButton("继续编辑",null).setPositiveButton("确认提交",(d,w)->{
            setBusy(true);persist();host.task(()->{
                if(snapshot.user!=uid())throw new IOException("账号已变化，请重新打开编辑器");
                if(snapshot.id>0){
                    JSONObject latest=host.client().get("post/info",ApiClient.params("id",String.valueOf(snapshot.id),"include","categories:simple,tags","exclude_view","1")).getJSONObject("data");
                    if(latest.optLong("user_id")!=uid())throw new IOException("无法修改其他人的投稿");
                    if(AuthoringRules.conflict(snapshot.version,latest.optString("updated_at"))||AuthoringRules.conflict(snapshot.baseline,fingerprint(latest)))throw new IOException("这篇文章已在别处更新。请先保留本机草稿，再重新载入网站内容，避免覆盖其他修改。");
                    host.client().post("post/editLock/refresh",new JSONObject().put("id",snapshot.id));
                }
                JSONObject payload=new JSONObject().put("title",snapshot.title.trim()).put("content",AuthoringRules.bodyHtml(snapshot.source,snapshot.html)).put("thumb",snapshot.thumb).put("tags",new JSONArray(AuthoringRules.tags(snapshot.tags))).put("categories",new JSONArray(snapshot.categories));
                String endpoint=snapshot.id==0?"post/create":snapshot.oldStatus.equals("rejected")?"post/review":"post/update";
                if(snapshot.id>0)payload.put("id",snapshot.id);
                if(!endpoint.equals("post/review"))payload.put("status",snapshot.status);
                if(snapshot.status.equals("future"))payload.put("created_at",snapshot.created);
                JSONObject result=host.client().post(endpoint,payload);return result;
            },result->{
                setBusy(false);dirty=false;drafts.edit().remove(key(snapshot.id)).apply();edit=null;formKind="";host.toast("已同步至网站");host.afterPostSubmitted(snapshot.oldStatus.equals("rejected")?"pending":snapshot.status);
            },message->{setBusy(false);host.toast(message+"\n内容已保存在本机；如提交超时，请先到管理列表核实，避免重复提交。");});
        }).show();
    }

    void profile(){
        start("profile");host.toolbar("编辑个人资料",true,()->leave(()->host.reloadNative()));loading();
        host.task(()->host.client().get("auth/me",ApiClient.params("include","roles,permissions,meta")).getJSONObject("data"),account->{
            host.updateAccount(account);body().removeAllViews();dirty=false;
            LinkedHashMap<String,String> values=new LinkedHashMap<>();values.put("nickname",account.optString("nickname"));values.put("description",account.optString("description"));values.put("sex",account.optString("sex","secret"));values.put("website",meta(account,"website"));values.put("location",meta(account,"location"));values.put("avatar",account.optString("avatar"));values.put("banner",account.optString("banner"));Map<String,String> original=new LinkedHashMap<>(values);
            note("保存后会同步至官网。头像和背景支持选择本机图片，并在上传前预览。");
            ImageView avatar=new ImageView(host);avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.setBackground(ui().round(ui().soft,42));avatar.setClipToOutline(true);LinearLayout.LayoutParams av=new LinearLayout.LayoutParams(ui().dp(84),ui().dp(84));av.gravity=Gravity.CENTER;body().addView(avatar,av);host.pictures().into(values.get("avatar"),avatar);ui().space(body(),14);
            button("更换头像",()->chooseImage("avatar",url->{values.put("avatar",url);host.pictures().into(url,avatar);changed();}));
            field("昵称（1–30字）",values.get("nickname"),1,30,s->values.put("nickname",s));field("个人简介（最多255字）",values.get("description"),4,255,s->values.put("description",s));
            String[] labels={"秘密","男","女","伪娘","扶她"},sex={"secret","male","female","otokonoko","futa"};body().addView(ui().text("性别",13,ui().muted,true));Spinner select=new Spinner(host);select.setAdapter(new ArrayAdapter<>(host,android.R.layout.simple_spinner_dropdown_item,labels));int selected=Arrays.asList(sex).indexOf(values.get("sex"));select.setSelection(Math.max(0,selected));body().addView(select,new LinearLayout.LayoutParams(-1,ui().dp(54)));ui().space(body(),14);select.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){public void onItemSelected(android.widget.AdapterView<?> p,View v,int pos,long id){if(!sex[pos].equals(values.get("sex"))){values.put("sex",sex[pos]);changed();}}public void onNothingSelected(android.widget.AdapterView<?> p){}});
            field("个人网站（可选，http/https）",values.get("website"),1,2000,s->values.put("website",s));field("所在地（可选）",values.get("location"),1,255,s->values.put("location",s));
            title("空间背景");ImageView banner=new ImageView(host);banner.setScaleType(ImageView.ScaleType.CENTER_CROP);banner.setBackground(ui().round(ui().soft,20));banner.setClipToOutline(true);body().addView(banner,new LinearLayout.LayoutParams(-1,ui().dp(150)));host.pictures().into(values.get("banner"),banner);ui().space(body(),12);button("从相册上传背景",()->chooseImage("banner",url->{values.put("banner",url);host.pictures().into(url,banner);changed();}));button("选择官网预设背景",()->{String[] options={"星屿 01","星屿 02","星屿 03","星屿 04","星屿 05","星屿 06"};dialog().setTitle("官网预设背景").setItems(options,(d,index)->{String url=UrlPolicy.ORIGIN+"/images/banner/user-banner_"+(index+1)+".webp";values.put("banner",url);host.pictures().into(url,banner);changed();}).show();});
            TextView save=ui().button("保存个人资料",true,()->{
                if(busy)return;String nickname=values.get("nickname").trim(),website=values.get("website").trim();if(nickname.isEmpty()){host.toast("昵称不能为空");return;}if(!website.isEmpty()&&(!UrlPolicy.canOpen(website)||website.startsWith("magnet:"))){host.toast("个人网站请填写有效的 http/https 地址");return;}
                LinkedHashMap<String,String> changes=new LinkedHashMap<>();for(Map.Entry<String,String> value:values.entrySet())if(!value.getValue().equals(original.get(value.getKey())))changes.put(value.getKey(),value.getValue());if(changes.isEmpty()){host.toast("没有需要保存的修改");return;}
                dialog().setTitle("保存个人资料？").setMessage("将同步到 cangku.moe："+String.join("、",profileLabels(changes.keySet()))).setNegativeButton("继续编辑",null).setPositiveButton("保存",(d,w)->{setBusy(true);host.task(()->{JSONObject payload=new JSONObject(changes).put("id",uid());host.client().post("user/update",payload);return host.client().get("auth/me",ApiClient.params("include","roles,permissions,meta")).getJSONObject("data");},result->{setBusy(false);dirty=false;host.updateAccount(result);host.toast("个人资料已更新");host.reloadNative();},message->{setBusy(false);host.toast(message);});}).show();
            });body().addView(save,new LinearLayout.LayoutParams(-1,ui().dp(54)));
        },this::fail);
    }
    private List<String> profileLabels(Set<String> keys){List<String> out=new ArrayList<>();Map<String,String> labels=new HashMap<>();labels.put("nickname","昵称");labels.put("description","简介");labels.put("sex","性别");labels.put("website","个人网站");labels.put("location","所在地");labels.put("avatar","头像");labels.put("banner","背景");for(String key:keys)out.add(labels.getOrDefault(key,key));return out;}
    private String fingerprint(JSONObject post)throws Exception {
        StringBuilder b=new StringBuilder();for(String key:new String[]{"title","content","thumb","status","created_at"})b.append(post.optString(key)).append('\0');
        List<String> cats=new ArrayList<>(),tags=new ArrayList<>();JSONArray c=post.optJSONArray("categories"),t=post.optJSONArray("tags");if(c!=null)for(int i=0;i<c.length();i++)cats.add(c.getJSONObject(i).optString("id"));if(t!=null)for(int i=0;i<t.length();i++)tags.add(t.getJSONObject(i).optString("name"));Collections.sort(cats);Collections.sort(tags);b.append(cats).append('\0').append(tags);
        byte[] hash=java.security.MessageDigest.getInstance("SHA-256").digest(b.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));return android.util.Base64.encodeToString(hash,android.util.Base64.NO_WRAP);
    }
    private String meta(JSONObject user,String key){
        JSONArray all=user.optJSONArray("meta");if(all!=null)for(int i=0;i<all.length();i++){JSONObject x=all.optJSONObject(i);if(x!=null&&key.equals(x.optString("key")))return x.optString("value");}
        JSONObject obj=user.optJSONObject("meta");return obj==null?"":obj.optString(key);
    }
    void security(){
        start("security");host.toolbar("账号安全",true,()->leave(()->host.reloadNative()));note("由你在本机输入并提交。密码仅用于本次请求，不保存在本机草稿或日志中。");
        title("更改邮箱");EditText current=passwordField("当前密码"),email=field("新邮箱","",1,180,s->{});email.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        button("更改绑定邮箱",()->{if(busy)return;String p=current.getText().toString(),e=email.getText().toString().trim();if(p.length()<6||!android.util.Patterns.EMAIL_ADDRESS.matcher(e).matches()){host.toast("请填写当前密码与有效的新邮箱");return;}
            dialog().setTitle("更改绑定邮箱？").setMessage("新邮箱："+e+"\n保存后可能需要重新验证邮箱和登录。").setNegativeButton("取消",null).setPositiveButton("确认更改",(d,w)->{setBusy(true);host.task(()->host.client().post("user/updateEmail",new JSONObject().put("password",p).put("email",e)),result->{setBusy(false);dirty=false;current.setText("");email.setText("");dirty=false;host.sessionChanged();},message->{setBusy(false);current.setText("");host.toast(message);});}).show();});
        title("更改密码");EditText old=passwordField("当前密码"),password=passwordField("新密码（6–60位）"),confirm=passwordField("再次输入新密码");
        button("更新密码",()->{if(busy)return;String o=old.getText().toString(),p=password.getText().toString(),c=confirm.getText().toString();if(o.length()<6||p.length()<6||p.length()>60||!p.equals(c)||p.equals(o)){host.toast("新密码需为6–60位、与旧密码不同，且两次输入一致");return;}
            dialog().setTitle("确认更新密码？").setMessage("完成后会清除本机登录会话，需要使用新密码重新登录。").setNegativeButton("取消",null).setPositiveButton("更新密码",(d,w)->{setBusy(true);host.task(()->host.client().post("user/updatePassword",new JSONObject().put("old_password",o).put("password",p)),result->{setBusy(false);dirty=false;old.setText("");password.setText("");confirm.setText("");dirty=false;host.sessionChanged();},message->{setBusy(false);old.setText("");password.setText("");confirm.setText("");host.toast(message);});}).show();});
    }
    private EditText passwordField(String label){EditText e=field(label,"",1,60,s->{});e.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD);e.setSaveEnabled(false);e.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);return e;}
    void logs(int page){
        start("logs");host.toolbar("积分与经验",true,()->host.reloadNative());note("查看自己账号的积分与经验变动。");loading();host.task(()->host.client().get("user/creditLog",ApiClient.params("page",String.valueOf(page),"per_page","20")),result->{body().removeViewAt(body().getChildCount()-1);JSONArray data=result.optJSONArray("data");if(data==null||data.length()==0){note("暂无记录");return;}for(int i=0;i<data.length();i++){JSONObject entry=data.getJSONObject(i);LinearLayout card=ui().column();ui().pad(card,16,16,16,16);card.setBackground(ui().round(ui().surface,18));card.addView(ui().text("积分 "+signed(entry.optLong("point"))+"  ·  经验 "+signed(entry.optLong("exp")),17,ui().accent,true));ui().space(card,8);card.addView(ui().text(entry.optString("description"),14,ui().text,false));ui().space(card,6);card.addView(ui().text(entry.optString("created_at"),11,ui().muted,false));body().addView(card);ui().space(body(),12);}JSONObject meta=result.optJSONObject("meta");if(meta!=null&&meta.optJSONObject("pagination")!=null)host.nativePagination(meta.getJSONObject("pagination"));},this::fail);
    }
    private String signed(long value){return (value>=0?"+":"")+value;}
    private void chooseImage(String type,java.util.function.Consumer<String> done){
        if(busy)return;uploadType=type;uploaded=done;Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT);pick.setType("image/*");pick.addCategory(Intent.CATEGORY_OPENABLE);try{host.startActivityForResult(pick,6201);}catch(ActivityNotFoundException e){host.toast("设备没有可用的图片选择器");uploaded=null;}
    }
    void onFileResult(int request,int result,Intent data){
        if(request!=6201)return;if(result!=Activity.RESULT_OK||data==null||data.getData()==null){uploaded=null;return;}if(uploaded==null)return;
        final Uri uri=data.getData();final String type=uploadType;final java.util.function.Consumer<String> done=uploaded;uploaded=null;setBusy(true);
        host.task(()->{try{return prepareImage(uri,type);}catch(OutOfMemoryError e){throw new IOException("图片尺寸过大，请选择较小的图片");}},bytes->{setBusy(false);ImageView preview=new ImageView(host);preview.setAdjustViewBounds(true);preview.setScaleType(ImageView.ScaleType.FIT_CENTER);preview.setImageBitmap(BitmapFactory.decodeByteArray(bytes,0,bytes.length));LinearLayout box=ui().column();ui().pad(box,20,12,20,12);box.addView(preview,new LinearLayout.LayoutParams(-1,ui().dp(240)));TextView text=ui().text("图片将上传至 cangku.moe（"+(bytes.length/1024)+"KB）"+(type.equals("avatar")?"，头像已居中裁成正方形":""),12,ui().muted,false);box.addView(text);
            dialog().setTitle("确认上传图片").setView(box).setNegativeButton("取消",null).setPositiveButton("上传",(d,w)->{setBusy(true);String path=type.equals("post")?"upload/image":"user/uploadImage";String field=type.equals("avatar")?"avatar":"image";Map<String,String> extra=type.equals("post")?Collections.emptyMap():ApiClient.params("type",type);host.task(()->host.client().upload(path,field,bytes,extra),response->{setBusy(false);String url=uploadUrl(response);if(!UrlPolicy.isImage(url)){host.toast("上传成功，但网站没有返回有效图片地址");return;}done.accept(url);host.toast("图片已上传；资料需点击保存才会更新");},message->{setBusy(false);host.toast(message);});}).show();
        },message->{setBusy(false);host.toast(message);});
    }
    private String uploadUrl(JSONObject response){JSONObject data=response.optJSONObject("data");String url=data==null?response.optString("link"):data.optString("url",data.optString("link"));if(url.startsWith("/"))url=UrlPolicy.ORIGIN+url;return url;}
    private byte[] prepareImage(Uri uri,String type)throws Exception {
        byte[] data;try(InputStream in=host.getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){
            if(in==null)throw new IOException("无法读取图片");byte[] block=new byte[8192];int size=0,n;while((n=in.read(block))!=-1){size+=n;if(size>25*1024*1024)throw new IOException("请选择小于25MB的图片");out.write(block,0,n);}data=out.toByteArray();
        }
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(data,0,data.length,bounds);if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IOException("无法解码这张图片");BitmapFactory.Options opts=new BitmapFactory.Options();opts.inPreferredConfig=Bitmap.Config.RGB_565;opts.inSampleSize=1;int max=type.equals("avatar")?600:1920;while(bounds.outWidth/opts.inSampleSize>max*2||bounds.outHeight/opts.inSampleSize>max*2)opts.inSampleSize*=2;Bitmap decoded=BitmapFactory.decodeByteArray(data,0,data.length,opts);if(decoded==null)throw new IOException("图片格式不支持");
        try{
            android.media.ExifInterface exif=new android.media.ExifInterface(new ByteArrayInputStream(data));int orientation=exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION,android.media.ExifInterface.ORIENTATION_NORMAL);Matrix matrix=new Matrix();
            switch(orientation){case 2:matrix.setScale(-1,1);break;case 3:matrix.setRotate(180);break;case 4:matrix.setRotate(180);matrix.postScale(-1,1);break;case 5:matrix.setRotate(90);matrix.postScale(-1,1);break;case 6:matrix.setRotate(90);break;case 7:matrix.setRotate(270);matrix.postScale(-1,1);break;case 8:matrix.setRotate(270);break;default:break;}
            if(!matrix.isIdentity()){Bitmap rotated=Bitmap.createBitmap(decoded,0,0,decoded.getWidth(),decoded.getHeight(),matrix,true);if(rotated!=decoded){decoded.recycle();decoded=rotated;}}
        }catch(IOException ignored){}
        Bitmap scaled=decoded;
        try{
            if(type.equals("avatar")){int side=Math.min(decoded.getWidth(),decoded.getHeight());Bitmap square=Bitmap.createBitmap(decoded,(decoded.getWidth()-side)/2,(decoded.getHeight()-side)/2,side,side);scaled=Bitmap.createScaledBitmap(square,200,200,true);if(square!=decoded&&square!=scaled)square.recycle();}
            else{float factor=Math.min(1f,max/(float)Math.max(decoded.getWidth(),decoded.getHeight()));if(factor<1)scaled=Bitmap.createScaledBitmap(decoded,Math.max(1,(int)(decoded.getWidth()*factor)),Math.max(1,(int)(decoded.getHeight()*factor)),true);}
            ByteArrayOutputStream out=new ByteArrayOutputStream();int quality=90;do{out.reset();scaled.compress(Bitmap.CompressFormat.JPEG,quality,out);quality-=10;}while(out.size()>1900*1024&&quality>=40);if(out.size()>2*1024*1024)throw new IOException("压缩后图片仍然过大，请换一张");return out.toByteArray();
        }finally{if(scaled!=decoded)scaled.recycle();decoded.recycle();}
    }
}
