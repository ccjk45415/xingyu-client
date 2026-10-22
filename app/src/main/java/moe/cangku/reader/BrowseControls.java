package moe.cangku.reader;
import android.app.*;import android.view.*;import android.widget.*;import org.json.*;import java.util.*;
final class BrowseControls {
 final MainActivity host;final Ui ui;final LocalLibrary library;
 BrowseControls(MainActivity h,LocalLibrary l){host=h;ui=h.design();library=l;}
 void filter(){
  final long owner=host.account()==null?0:host.account().optLong("id");
  JSONArray tree=host.categoryTree();if(tree.length()==0){host.toast("分类尚未载入，请稍后刷新再试");return;}
  LinkedHashSet<Long> all=new LinkedHashSet<>();for(JSONObject n:CategoryRules.nodes(tree))all.add(n.optLong("id"));
  Set<Long> saved=library.homeCategories();LinkedHashSet<Long> selected=saved==null?new LinkedHashSet<>(all):CategoryRules.effective(saved,tree);
  LinearLayout shell=ui.column();ui.pad(shell,14,8,14,10);shell.addView(ui.text("只看勾选的分类，多个分类取合集。设置按账号保存在本机，分类页与排行不受影响。",13,ui.muted,false));
  LinearLayout actions=ui.row();TextView allButton=ui.button("全部分类",false,()->{}),clear=ui.button("清空选择",false,()->{});actions.addView(allButton,new LinearLayout.LayoutParams(0,-2,1));actions.addView(clear,new LinearLayout.LayoutParams(0,-2,1));shell.addView(actions);ui.space(shell,10);
  ScrollView scroll=new ScrollView(host);LinearLayout groups=ui.column();scroll.addView(groups);shell.addView(scroll,new LinearLayout.LayoutParams(-1,(int)(host.getResources().getDisplayMetrics().heightPixels*.48)));TextView count=ui.text("",12,ui.accent,true);shell.addView(count);
  Runnable[] draw=new Runnable[1];draw[0]=()->{int y=scroll.getScrollY();groups.removeAllViews();for(int i=0;i<tree.length();i++){JSONObject root=tree.optJSONObject(i);if(root==null)continue;LinearLayout card=ui.column();ui.pad(card,10,10,10,12);card.setBackground(ui.round(ui.soft,16));Set<Long> branch=CategoryRules.branch(root);CheckBox box=check(root.optString("name")+(selected.containsAll(branch)?"":branch.stream().anyMatch(selected::contains)?" · 部分":""),selected.containsAll(branch));card.addView(box);box.setOnCheckedChangeListener((b,on)->{CategoryRules.toggle(selected,root,on,tree);draw[0].run();});
   for(JSONObject sub:CategoryRules.nodes(root.optJSONArray("children"))){CheckBox child=check(sub.optString("name"),selected.contains(sub.optLong("id")));ui.pad(child,12,0,0,0);card.addView(child);child.setOnCheckedChangeListener((b,on)->{CategoryRules.toggle(selected,sub,on,tree);draw[0].run();});}groups.addView(card);ui.space(groups,10);}
   count.setText(selected.isEmpty()?"未勾选分类，首页将不显示作品":"已选 "+selected.size()+" 个分类");scroll.post(()->scroll.scrollTo(0,y));};
  allButton.setOnClickListener(v->{selected.addAll(all);draw[0].run();});clear.setOnClickListener(v->{selected.clear();draw[0].run();});draw[0].run();
  new AlertDialog.Builder(new android.view.ContextThemeWrapper(host,ui.dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert)).setTitle("定制首页").setView(shell).setNegativeButton("取消",null).setPositiveButton("保存筛选",(d,w)->{if(host.account()==null||host.account().optLong("id")!=owner){host.toast("账号已变化，筛选未保存");return;}host.applyHomeFilter(selected.containsAll(all)?null:selected);}).show();
 }
 CheckBox check(String label,boolean value){CheckBox c=new CheckBox(host);c.setText(label);c.setTextSize(14);c.setTextColor(ui.text);c.setButtonTintList(android.content.res.ColorStateList.valueOf(ui.accent));c.setChecked(value);return c;}
}
