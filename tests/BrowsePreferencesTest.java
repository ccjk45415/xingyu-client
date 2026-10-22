package moe.cangku.reader;
import org.json.*;import java.util.*;
public class BrowsePreferencesTest {
 static int n;static void ok(boolean value){n++;if(!value)throw new AssertionError("case "+n);}
 public static void main(String[] args)throws Exception{
  JSONArray tree=new JSONArray("[{id:10,name:'书籍',children:[{id:11,name:'漫画'},{id:12,name:'小说'}]},{id:20,name:'游戏',children:[{id:21,name:'电脑游戏'},{id:22,name:'手机游戏'}]}]");
  JSONObject root=tree.getJSONObject(0);Set<Long> ids=new LinkedHashSet<>();
  ok(CategoryRules.nodes(tree).size()==6);ok(CategoryRules.branch(root).equals(new LinkedHashSet<>(Arrays.asList(10L,11L,12L))));
  CategoryRules.toggle(ids,root,true,tree);ok(ids.equals(new LinkedHashSet<>(Arrays.asList(10L,11L,12L))));
  CategoryRules.toggle(ids,root.getJSONArray("children").getJSONObject(0),false,tree);ok(ids.equals(new LinkedHashSet<>(Arrays.asList(12L))));
  ids.add(999L);ok(CategoryRules.effective(ids,tree).equals(new LinkedHashSet<>(Arrays.asList(12L))));
  JSONArray posts=new JSONArray("[{id:1,categories:[{id:11}]},{id:2,categories:[{id:12}]},{id:3,categories:[{id:21}]},{id:4,categories:[]}]");
  JSONArray filtered=CategoryRules.filter(posts,ids);ok(filtered.length()==1);ok(filtered.getJSONObject(0).getLong("id")==2);ok(posts.length()==4);
  ok(CategoryRules.filter(posts,new HashSet<>()).length()==0);ok(CategoryRules.filter(null,ids).length()==0);
  CategoryRules.toggle(ids,tree.getJSONObject(1),true,tree);ok(CategoryRules.filter(posts,ids).length()==2);
  CategoryRules.toggle(ids,tree.getJSONObject(1),false,tree);ok(!ids.contains(20L)&&!ids.contains(21L)&&!ids.contains(22L));
  JSONArray feed=new JSONArray("[{id:1,user_id:77,created_at:'2026-10-20T00:00:00Z'},{id:2,user_id:88,created_at:'2026-10-22T00:00:00Z'},{id:3,user:{id:79},created_at:'2026-10-21T00:00:00Z'},{id:1,user_id:77,created_at:'2026-10-20T00:00:00Z'}]");
  Set<Long> follows=new HashSet<>(Arrays.asList(77L,79L));JSONArray dynamic=FollowFeedRules.select(feed,follows,0);ok(dynamic.length()==2);ok(dynamic.getJSONObject(0).getLong("id")==3);ok(FollowFeedRules.select(feed,follows,77).length()==1);ok(FollowFeedRules.select(feed,follows,88).length()==0);ok(FollowFeedRules.select(feed,new HashSet<>(),0).length()==0);ok(feed.length()==4);
  System.out.println("PASS "+n+" native category filter / follow-feed assertions; no website writes");
 }
}
