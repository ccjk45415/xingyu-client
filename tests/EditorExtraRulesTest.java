package moe.cangku.reader;
import java.util.*;
import org.json.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
public final class EditorExtraRulesTest {
 static int checks;static void ok(boolean v){checks++;if(!v)throw new AssertionError("check "+checks);}
 interface Run{void run()throws Exception;}static void rejects(Run r)throws Exception{checks++;try{r.run();}catch(IllegalArgumentException e){return;}throw new AssertionError("expected rejection "+checks);}
 static JSONObject poll()throws Exception{return new JSONObject().put("title","选择 <作品>").put("options",new JSONArray().put(new JSONObject().put("id",11).put("text","甲").put("image","")).put(new JSONObject().put("id",12).put("text","乙").put("image",""))).put("multi_select",true).put("max_select",2).put("image_mode",false).put("start_at","2026-10-21 12:00:00").put("end_at","2026-10-22 12:00:00");}
 public static void main(String[] args)throws Exception{
  ok(EditorExtraRules.esc("<&\"'").equals("&lt;&amp;&quot;&#39;"));
  ok(EditorExtraRules.font(3,"<b>字</b>").contains("&quot;Microsoft YaHei&quot;"));
  rejects(()->EditorExtraRules.font(99,"字"));rejects(()->EditorExtraRules.inline("onclick=evil","字"));
  String collapse=EditorExtraRules.collapse("[引号\"]","<script>\n第二行",true);ok(collapse.contains("show=\"true\"")&&collapse.contains("【引号&quot;】")&&collapse.contains("&lt;script&gt;<br>"));
  ok(EditorExtraRules.reference("poll",123).equals("[poll id=\"123\"][/poll]"));rejects(()->EditorExtraRules.reference("poll",0));rejects(()->EditorExtraRules.reference("image",2));
  Set<String> randoms=new HashSet<>();for(int i=0;i<30;i++){String s=EditorExtraRules.randomFileName();ok(s.matches("\\[GalACG\\]EX[0-9]{9}"));randoms.add(s);}ok(randoms.size()==30);
  rejects(()->EditorExtraRules.web("javascript:alert(1)",false));rejects(()->EditorExtraRules.web("https://u:p@example.com/x",false));ok(EditorExtraRules.web("https://example.com/running.png",false).contains("running"));
  String original="<a href=\"https://old.example/a\"><img src=\"https://img.example/old.png\" data-src=\"https://img.example/old.png\" class=\"custom\" data-id=\"88\" style=\"color:red;width:12px;height:20px;\" alt=\"old\"></a>";
  String updated=EditorExtraRules.updateImage(original,"https://img.example/new.png","<说明>","320","50%",true,"https://example.com/?x=1&y=2");Element img=Jsoup.parseBodyFragment(updated).selectFirst("img");ok(img.attr("src").endsWith("new.png")&&!img.hasAttr("data-src"));ok(img.attr("data-id").equals("88")&&img.hasClass("custom")&&img.hasClass("blur-img"));ok(img.attr("width").equals("320")&&img.attr("style").contains("height:50%")&&img.attr("style").contains("color:red"));ok(img.attr("alt").equals("<说明>"));ok(img.parent().attr("href").equals("https://example.com/?x=1&y=2"));
  updated=EditorExtraRules.updateImage(original,"https://img.example/old.png","old","","",false,"");ok(Jsoup.parseBodyFragment(updated).selectFirst("a")==null);rejects(()->EditorExtraRules.updateImage(original,"https://img.example/a","","0","",false,""));
  String table="<table data-id=\"7\" style=\"color:blue;width:20px;height:30px\"><caption>标题</caption><tbody><tr><th><a href=\"https://example.com\">甲</a></th><td>乙</td></tr></tbody></table>";
  String changed=EditorExtraRules.table(table,2,2,Arrays.asList("甲","<img onerror=x>","丙","丁"),"100%","","dashed","center");Element t=Jsoup.parseBodyFragment(changed).selectFirst("table");ok(t.attr("data-id").equals("7")&&t.selectFirst("caption").text().equals("标题"));ok(t.selectFirst("a")!=null&&t.select("tr").size()==2&&t.selectFirst("img")==null);ok(t.attr("style").contains("width:100%")&&!t.attr("style").contains("height:"));ok(t.hasClass("fr-dashed-borders"));rejects(()->EditorExtraRules.table("<table><tr><td colspan=2>x</td></tr></table>",1,1,Arrays.asList("x"),"","","solid","left"));rejects(()->EditorExtraRules.table("",31,1,Collections.emptyList(),"","","solid","left"));
  JSONObject valid=EditorExtraRules.pollPayload(poll());ok(valid.getJSONArray("options").getJSONObject(0).getInt("id")==11&&valid.getInt("max_select")==2);ok(valid.getString("start_at").equals("2026-10-21 12:00:00"));rejects(()->EditorExtraRules.pollPayload(poll().put("max_select",1)));rejects(()->EditorExtraRules.pollPayload(poll().put("image_mode",true)));JSONObject duplicate=poll();duplicate.getJSONArray("options").getJSONObject(1).put("text","甲");rejects(()->EditorExtraRules.pollPayload(duplicate));rejects(()->EditorExtraRules.pollPayload(poll().put("end_at","2026-02-30 12:00:00")));
  ok(!EditorExtraRules.lotteryAllowed(new JSONObject().put("roles",new JSONArray().put(new JSONObject().put("name","contributor")))));ok(EditorExtraRules.lotteryAllowed(new JSONObject().put("roles",new JSONArray().put("editor"))));
  System.out.println("EDITOR_EXTRA_RULES_PASSED "+checks+" assertions; no website writes");
 }
}
