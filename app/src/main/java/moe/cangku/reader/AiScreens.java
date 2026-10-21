package moe.cangku.reader;

import android.app.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.function.Consumer;

/** Native, cancellable source -> preview -> explicit local import. No website post writes. */
final class AiScreens {
    static final class Import {
        JSONObject draft;boolean title,body,tags,cover,append;
    }
    private final MainActivity host;private final Ui ui;private final long owner;private final Consumer<Import> imported;
    private final ChatVault settings,identity;
    private AlertDialog window;private LinearLayout box,customBox,sourceBox,previewBox;
    private EditText links,material,address,key,model;private Spinner mode,type;private TextView status,generate,recover;
    private final ArrayList<View> controls=new ArrayList<>();private final ArrayList<EditText> sourceInputs=new ArrayList<>();
    private CheckBox titleCheck,bodyCheck,tagsCheck,coverCheck,appendCheck,keepOriginal;
    private AiClient client=new AiClient();private JSONArray sources=new JSONArray();private JSONObject result,previous;
    private boolean closed,busy;private long serial;
    AiScreens(MainActivity h,Consumer<Import> done){host=h;ui=h.design();owner=h.account()==null?0:h.account().optLong("id");imported=done;settings=new ChatVault(h,"aiPreferences","cangku.ai.settings.v1");identity=new ChatVault(h,"privateIdentity","cangku.private.v1");}
    void close(){closed=true;serial++;client.close();if(window!=null)window.dismiss();}
    private boolean live(){return !closed&&window!=null&&window.isShowing()&&host.account()!=null&&host.account().optLong("id")==owner;}
    private boolean custom(){return mode.getSelectedItemPosition()==1;}
    private AlertDialog.Builder dialog(){return new AlertDialog.Builder(new android.view.ContextThemeWrapper(host,ui.dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert));}
    private void text(LinearLayout parent,String value){TextView t=ui.text(value,12,ui.muted,false);parent.addView(t);ui.space(parent,10);}
    private EditText input(LinearLayout parent,String hint,int lines){EditText e=new EditText(host);e.setHint(hint);e.setTextSize(14);e.setTextColor(ui.text);e.setHintTextColor(ui.muted);e.setMinLines(lines);e.setMaxLines(Math.max(3,lines+2));e.setGravity(Gravity.TOP);e.setBackground(ui.round(ui.surface,12));ui.pad(e,12,10,12,10);e.setSaveEnabled(false);parent.addView(e,new LinearLayout.LayoutParams(-1,-2));ui.space(parent,10);controls.add(e);return e;}
    private TextView button(LinearLayout parent,String label,Runnable work){TextView b=ui.button(label,false,work);parent.addView(b,new LinearLayout.LayoutParams(-1,-2));ui.space(parent,8);controls.add(b);return b;}
    private Spinner spinner(LinearLayout parent,String[] items){Spinner s=new Spinner(host);s.setAdapter(new ArrayAdapter<String>(host,android.R.layout.simple_spinner_dropdown_item,items));parent.addView(s,new LinearLayout.LayoutParams(-1,ui.dp(48)));controls.add(s);return s;}
    void show(){
        box=ui.column();ui.pad(box,18,8,18,16);ScrollView scroll=new ScrollView(host);scroll.setFillViewport(true);scroll.addView(box);mode=spinner(box,new String[]{"内置 AI · 共享免费额度","自定义 AI · 自己的API"});
        text(box,"内置：仓库认证后每UID每日3次，全体共享16段翻译预算，UTC零点重置。只逐段翻译原文，不概括、不补写；图片和段落按原顺序保留。生成开始即占用次数，失败不自动重试。\n长介绍自动分段；超出免费预算会提示，不截断。\n自定义：直连你的服务，不占内置次数与字数额度，仍受服务商与设备容量限制。密钥只在本机加密保存。");
        customBox=ui.column();box.addView(customBox);address=input(customBox,"HTTPS API地址，例如 https://你的服务/v1",1);key=input(customBox,"API Key（按服务要求，可留空）",1);key.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);key.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);model=input(customBox,"模型名称",1);
        button(customBox,"保存加密配置",()->{try{save();status.setText("配置已加密保存");}catch(Exception e){status.setText(e.getMessage());}});
        button(customBox,"测试连接（可能消耗服务商额度）",()->{try{save();final String a=address.getText().toString(),k=key.getText().toString(),m=model.getText().toString();AiClient io=client;run(()->{io.json(AiClient.endpoint(a),new JSONObject().put("model",m).put("messages",new JSONArray().put(new JSONObject().put("role","user").put("content","Reply OK"))).put("max_tokens",8).put("stream",false),k,false);return "连接成功";},v->status.setText(v));}catch(Exception e){status.setText(e.getMessage());}});
        type=spinner(box,new String[]{"原文逐段翻译 · 不概括，不补写"});type.setEnabled(false);links=input(box,"作品链接，每行一个，最多3个（Steam / DLsite / 官网等）",2);
        button(box,"提取链接中的公开介绍",()->extract(false));button(box,"链接配合手动粘贴素材",()->extract(true));
        sourceBox=ui.column();box.addView(sourceBox);keepOriginal=new CheckBox(host);keepOriginal.setText("原文已是中文：跳过AI，原样带入（不耗次数）");keepOriginal.setTextColor(ui.text);box.addView(keepOriginal);controls.add(keepOriginal);material=input(box,"补充作品素材；提取失败时粘贴公开介绍。不要填写密码或私人资料。",3);

        status=ui.text("先提取来源，再生成草稿。网页资料只作为素材，不作为AI指令。",12,ui.accent,false);box.addView(status);ui.space(box,10);
        generate=button(box,"翻译并生成草稿",()->generate(false));recover=button(box,"恢复上次内置结果（不重复扣次）",()->generate(true));recover.setVisibility(View.GONE);
        // Cancel remains available while the form is frozen.
        TextView cancel=ui.button("取消当前任务",false,this::cancel);box.addView(cancel);ui.space(box,10);
        previewBox=ui.column();box.addView(previewBox);
        JSONObject cfg=settings.load(owner,ServiceEndpoint.origin());if(cfg!=null){address.setText(cfg.optString("address"));key.setText(cfg.optString("key"));model.setText(cfg.optString("model"));mode.setSelection(cfg.optBoolean("custom")?1:0);}
        mode.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int i,long id){customBox.setVisibility(i==1?View.VISIBLE:View.GONE);result=null;previous=null;previewBox.removeAllViews();recover.setVisibility(View.GONE);try{save(false);}catch(Exception e){status.setText("无法保存加密配置");}}public void onNothingSelected(AdapterView<?> p){}});
        customBox.setVisibility(custom()?View.VISIBLE:View.GONE);
        window=dialog().setTitle("AI 投稿助手").setView(scroll).setNegativeButton("关闭",null).create();window.setOnDismissListener(d->{closed=true;serial++;client.close();});window.show();window.getWindow().setLayout(-1,(int)(host.getResources().getDisplayMetrics().heightPixels*.9));
    }
    private void save()throws Exception{save(true);}
    private void save(boolean validate)throws Exception{if(host.account()==null||host.account().optLong("id")!=owner)throw new java.io.IOException("账号已切换");if(validate&&custom()){AiClient.endpoint(address.getText().toString());if(model.getText().toString().trim().isEmpty())throw new java.io.IOException("请填写模型名");}settings.save(owner,ServiceEndpoint.origin(),new JSONObject().put("custom",custom()).put("address",address.getText().toString().trim()).put("key",key.getText().toString().trim()).put("model",model.getText().toString().trim()));}
    private <T> void run(MainActivity.Work<T> work,Consumer<T> done){if(busy||!live())return;final long id=++serial;busy=true;for(View v:controls)v.setEnabled(false);status.setText("处理中…");host.task(work,value->{if(!live()||id!=serial)return;busy=false;for(View v:controls)v.setEnabled(true);done.accept(value);},message->{if(!live()||id!=serial)return;busy=false;for(View v:controls)v.setEnabled(true);status.setText(message);});}
    private void cancel(){serial++;client.close();client=new AiClient();busy=false;for(View v:controls)v.setEnabled(true);status.setText("已取消。内置生成若已开始仍计次，可恢复上次结果。不会自动重试。");}
    private void extract(boolean manual){
        final String[] urls=links.getText().toString().trim().split("\\s+");if(urls.length<1||urls.length>3){status.setText("请输入1至3个作品链接");return;}
        AiClient io=client;run(()->{JSONArray found=new JSONArray();for(String raw:urls){String u=AiClient.sourceUrl(raw).toString();found.put(manual?new JSONObject().put("url",u).put("text","").put("cover",""):io.source(u));}return found;},found->{sources=found;previous=null;result=null;previewBox.removeAllViews();recover.setVisibility(View.GONE);sourceBox.removeAllViews();controls.removeAll(sourceInputs);sourceInputs.clear();for(int i=0;i<sources.length();i++){JSONObject s=sources.optJSONObject(i);JSONArray bs=s.optJSONArray("blocks");int pictures=0;if(bs!=null)for(int n=0;n<bs.length();n++)if("image".equals(bs.optJSONObject(n).optString("kind")))pictures++;text(sourceBox,"来源 "+(i+1)+" · 完整介绍 / "+pictures+"张图片\n"+s.optString("url"));EditText e=input(sourceBox,"完整原文",3);e.setText(s.optString("text"));if(bs!=null&&bs.length()>0){e.setFocusable(false);e.setTextIsSelectable(true);}sourceInputs.add(e);}status.setText(manual?"粘贴作品介绍后生成":"已提取详细介绍和图片；不会用网页摘要替代，也不会精简原文");});
    }
    private String token(){JSONObject saved=identity.load(owner,ServiceEndpoint.origin());try{if(saved!=null&&saved.getJSONObject("user").getLong("id")==owner&&java.time.Instant.parse(saved.getString("expires_at")).toEpochMilli()>System.currentTimeMillis())return saved.getString("token");}catch(Exception ignored){}return "";}
    private void generate(boolean restore){
        try{
            if(!keepOriginal.isChecked())save();if(!custom()&&!keepOriginal.isChecked()&&token().isEmpty()){dialog().setTitle("认证仓库账号").setMessage("内置AI按仓库UID分配额度。把当前官网会话交给星屿服务验证，不保存官网密码或会话。所选介绍交给Cloudflare AI处理，草稿缓存1小时。").setNegativeButton("取消",null).setPositiveButton("认证并继续",(d,w)->run(()->host.client().enablePrivateMessaging(owner),session->{try{if(session.getJSONObject("user").getLong("id")!=owner)throw new Exception("认证账号不符");identity.save(owner,ServiceEndpoint.origin(),session);generate(restore);}catch(Exception e){status.setText(e.getMessage());}})).show();return;}
            if(!restore){if(sources.length()==0)throw new Exception("请先提取链接，或使用链接配合手动素材");for(int i=0;i<sources.length();i++)sources.getJSONObject(i).put("text",sourceInputs.get(i).getText().toString());previous=SourceTranslation.request(sources,material.getText().toString().trim(),AiClient.TYPES[type.getSelectedItemPosition()],UUID.randomUUID().toString());if(!custom()&&!keepOriginal.isChecked()){JSONArray planned=new JSONArray(previous.getJSONArray("sources").toString());if(!previous.optString("material").isEmpty())planned.getJSONObject(0).getJSONArray("blocks").put(new JSONObject().put("kind","p").put("text",previous.getString("material")));if(new SourceTranslation.Plan(planned).chunks.size()>8||previous.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length>200000){previous=null;throw new Exception("详细介绍较长，内置免费预算无法完整翻译。请选择自定义AI，原文不会被截断");}}}
            if(previous==null)throw new Exception("没有可恢复的任务");if(keepOriginal.isChecked()){JSONArray original=new JSONArray(previous.getJSONArray("sources").toString());if(!previous.optString("material").trim().isEmpty())original.getJSONObject(0).getJSONArray("blocks").put(new JSONObject().put("kind","p").put("text",previous.getString("material")));SourceTranslation.Plan plan=new SourceTranslation.Plan(original);Map<String,String> values=new HashMap<>();for(JSONArray chunk:plan.chunks)for(int i=0;i<chunk.length();i++){JSONObject v=chunk.getJSONObject(i);values.put(v.getString("id"),v.getString("text"));}result=plan.assemble(original,"auto",values);preview();status.setText("已按原文带入，未调用AI、未消耗内置次数");recover.setVisibility(View.GONE);return;}final JSONObject data=new JSONObject(previous.toString());final boolean own=custom();final String a=address.getText().toString(),k=key.getText().toString(),m=model.getText().toString(),secret=token();final AiClient io=client;recover.setVisibility(own?View.GONE:View.VISIBLE);
            run(()->{if(own)return new JSONObject().put("draft",io.custom(a,k,m,data));JSONObject response;try{response=io.json(new java.net.URL(ServiceEndpoint.origin()+"/ai/v2/draft"),data,secret,true);}catch(AiClient.Failure e){if(e.status==401)identity.clear(owner);throw e;}AiClient.validate(response.getJSONObject("draft"),sources,true);return response;},response->{result=response.optJSONObject("draft");preview();status.setText(own?"草稿已生成，请核对来源后导入":"今日个人剩余 "+response.optInt("remaining")+" 次 · 共享翻译预算剩余 "+response.optInt("shared_remaining")+" 段");});
        }catch(Exception e){status.setText(e.getMessage());}
    }
    private CheckBox check(String label,boolean value){CheckBox c=new CheckBox(host);c.setText(label);c.setTextColor(ui.text);c.setChecked(value);previewBox.addView(c);return c;}
    private void preview(){try{
        previewBox.removeAllViews();previewBox.addView(ui.text(result.getString("title"),19,ui.text,true));text(previewBox,"AI只翻译文字，图片原样保留。请核对译文；仅导入本机草稿，不自动发表。");JSONArray translated=result.optJSONArray("blocks");if(translated!=null){for(int i=0;i<translated.length();i++){JSONObject b=translated.getJSONObject(i);if(b.optString("kind").equals("image")){ImageView photo=new ImageView(host);photo.setAdjustViewBounds(true);photo.setScaleType(ImageView.ScaleType.FIT_CENTER);previewBox.addView(photo,new LinearLayout.LayoutParams(-1,ui.dp(220)));host.pictures().into(b.getString("url"),photo);text(previewBox,"原文图片 · 不翻译");}else{TextView content=ui.text(b.optString("text"),14,ui.text,b.optString("kind").startsWith("h"));content.setTextIsSelectable(true);previewBox.addView(content);ui.space(previewBox,8);}}}else{TextView content=ui.text(android.text.Html.fromHtml(AiClient.body(result),android.text.Html.FROM_HTML_MODE_COMPACT).toString(),14,ui.text,false);content.setTextIsSelectable(true);previewBox.addView(content);}
        titleCheck=check("导入标题（替换）",true);bodyCheck=check("导入正文（可撤销）",true);tagsCheck=check("保留现有标签（本功能不生成标签）",false);tagsCheck.setEnabled(false);coverCheck=check("导入来源封面URL（替换，不上传）",false);appendCheck=check("正文追加至现有内容",true);
        button(previewBox,"导入选中字段",()->{if(busy||!live())return;dialog().setTitle("导入AI草稿？").setMessage("选中的标题、标签、封面将替换原字段；正文按所选方式追加或替换。尚未提交网站。").setNegativeButton("取消",null).setPositiveButton("导入",(d,w)->{if(!live())return;Import out=new Import();out.draft=result;out.title=titleCheck.isChecked();out.body=bodyCheck.isChecked();out.tags=tagsCheck.isChecked();out.cover=coverCheck.isChecked();out.append=appendCheck.isChecked();imported.accept(out);window.dismiss();}).show();});
    }catch(Exception e){status.setText("草稿格式错误，请重试");}}
}
