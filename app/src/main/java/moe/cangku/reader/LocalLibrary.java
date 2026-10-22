package moe.cangku.reader;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.*;

final class LocalLibrary {
    private final SharedPreferences prefs;
    private long user;
    LocalLibrary(Context c){prefs=c.getSharedPreferences("library",Context.MODE_PRIVATE);}
    void setUser(long id){user=id;}
    JSONArray history(){try{return new JSONArray(prefs.getString("history."+user,"[]"));}catch(Exception e){return new JSONArray();}}
    void visit(JSONObject article){
        JSONArray old=history(),all=new JSONArray();
        try{
            JSONObject item=new JSONObject().put("id",article.getLong("id")).put("title",article.optString("title"))
                    .put("thumb",article.optString("thumb")).put("user",article.optJSONObject("user"))
                    .put("view_count",article.optLong("view_count")).put("created_at",article.optString("created_at")).put("visited_at",System.currentTimeMillis());
            all.put(item);
            for(int i=0;i<old.length()&&all.length()<100;i++)if(old.getJSONObject(i).optLong("id")!=article.optLong("id"))all.put(old.getJSONObject(i));
            prefs.edit().putString("history."+user,all.toString()).apply();
        }catch(JSONException ignored){}
    }
    void clearHistory(){prefs.edit().remove("history."+user).apply();}
    boolean dark(){return prefs.getBoolean("dark",false);}
    void dark(boolean value){prefs.edit().putBoolean("dark",value).apply();}
    int textSize(){return prefs.getInt("readerSize",17);}
    void textSize(int size){prefs.edit().putInt("readerSize",Math.max(14,Math.min(24,size))).apply();}
    boolean categoryTabs(){return prefs.getBoolean("categoryTabs."+user,false);}
    void categoryTabs(boolean value){prefs.edit().putBoolean("categoryTabs."+user,value).apply();}
    java.util.LinkedHashSet<Long> homeCategories(){
        String raw=prefs.getString("homeCategories."+user,null);if(raw==null)return null;
        java.util.LinkedHashSet<Long> ids=new java.util.LinkedHashSet<>();try{JSONArray values=new JSONArray(raw);for(int i=0;i<values.length();i++)if(values.optLong(i)>0)ids.add(values.optLong(i));}catch(Exception ignored){}return ids;
    }
    void homeCategories(java.util.Set<Long> value){if(value==null)prefs.edit().remove("homeCategories."+user).apply();else prefs.edit().putString("homeCategories."+user,new JSONArray(value).toString()).apply();}
}
