package moe.cangku.reader;
import org.json.*;import java.util.*;
public final class CategoryRules {
 public static ArrayList<JSONObject> nodes(JSONArray tree){ArrayList<JSONObject> out=new ArrayList<>();if(tree!=null)for(int i=0;i<tree.length();i++){JSONObject n=tree.optJSONObject(i);if(n!=null){out.add(n);out.addAll(nodes(n.optJSONArray("children")));}}return out;}
 public static LinkedHashSet<Long> branch(JSONObject node){LinkedHashSet<Long> out=new LinkedHashSet<>();if(node.optLong("id")>0)out.add(node.optLong("id"));for(JSONObject n:nodes(node.optJSONArray("children")))if(n.optLong("id")>0)out.add(n.optLong("id"));return out;}
 public static LinkedHashSet<Long> effective(Set<Long> selected,JSONArray tree){LinkedHashSet<Long> out=new LinkedHashSet<>();for(JSONObject node:nodes(tree))if(selected.contains(node.optLong("id")))out.add(node.optLong("id"));return out;}
 public static void toggle(Set<Long> selected,JSONObject node,boolean on,JSONArray tree){Set<Long> ids=branch(node);if(on)selected.addAll(ids);else{selected.removeAll(ids);for(JSONObject p:nodes(tree))if(branch(p).contains(node.optLong("id")))selected.remove(p.optLong("id"));}}
 public static JSONArray filter(JSONArray posts,Set<Long> selected){JSONArray out=new JSONArray();if(posts!=null)for(int i=0;i<posts.length();i++){JSONObject post=posts.optJSONObject(i);if(post==null)continue;for(JSONObject n:nodes(post.optJSONArray("categories")))if(selected.contains(n.optLong("id"))){out.put(post);break;}}return out;}
}
