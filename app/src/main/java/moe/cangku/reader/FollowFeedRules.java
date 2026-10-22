package moe.cangku.reader;
import org.json.*;import java.util.*;
public final class FollowFeedRules {
 public static JSONArray select(JSONArray input,Set<Long> followed,long selected){
  ArrayList<JSONObject> list=new ArrayList<>();Set<Long> seen=new HashSet<>();if(input!=null)for(int i=0;i<input.length();i++){
   JSONObject post=input.optJSONObject(i);if(post==null)continue;JSONObject author=post.optJSONObject("user");long uid=post.optLong("user_id",author==null?0:author.optLong("id")),id=post.optLong("id");
   if(id>0&&followed.contains(uid)&&(selected==0||selected==uid)&&seen.add(id))list.add(post);
  }
  list.sort((a,b)->b.optString("created_at").compareTo(a.optString("created_at")));return new JSONArray(list);
 }
}
