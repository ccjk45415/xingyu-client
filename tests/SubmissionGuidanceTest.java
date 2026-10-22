package moe.cangku.reader;
import java.nio.file.*;import java.util.*;import org.json.*;

public final class SubmissionGuidanceTest {
    static int count;
    static void ok(boolean value,String name){count++;if(!value)throw new AssertionError(name);}
    public static void main(String[] args)throws Exception{
        SubmissionGuidance g=new SubmissionGuidance(Files.readString(Path.of(args[0])));
        JSONObject fixture=new JSONObject(Files.readString(Path.of(args[1])));JSONArray tree=fixture.getJSONArray("tree"),cases=fixture.getJSONArray("cases");
        JSONArray results=new JSONArray();
        for(int i=0;i<cases.length();i++){
            JSONObject c=cases.getJSONObject(i);Set<Long> ids=new LinkedHashSet<>();JSONArray selected=c.getJSONArray("selected");for(int n=0;n<selected.length();n++)ids.add(selected.getLong(n));
            Set<String> codes=new TreeSet<>();for(SubmissionGuidance.Issue issue:g.check(c.getString("title"),c.getString("body"),ids,tree,c.getString("kind"),c.getBoolean("ai_images")))codes.add(issue.code);
            for(int j=0;j<c.getJSONArray("expected").length();j++)ok(codes.contains(c.getJSONArray("expected").getString(j)),c.getString("name")+": missing issue");
            for(int j=0;j<c.getJSONArray("absent").length();j++)ok(!codes.contains(c.getJSONArray("absent").getString(j)),c.getString("name")+": unexpected issue");
            results.put(new JSONObject().put("name",c.getString("name")).put("codes",new JSONArray(codes)));
        }
        ok(g.resolve(tree,"音乐 / 侍寝声音").equals(new LinkedHashSet<>(Arrays.asList(200L,210L))),"real parent IDs");
        ok(g.resolve(tree,"游戏 / 未存在的分类").isEmpty(),"no invented ID");
        ok(g.resolve(tree,"书籍 / 其它书籍").equals(new LinkedHashSet<>(Arrays.asList(700L,710L))),"equivalent spelling");
        ok(g.title("game","测试","","","",false).equals("[游戏分享] 测试"),"no invented author/date");
        ok(g.title("asmr","【雨声】","社团","","WAV,日语",false).equals("[音声分享][社团] 【雨声】 [WAV][日语]"),"retain original brackets");
        ok(g.transportType("software").equals("other"),"compatible transport");
        ok(g.guess(new JSONArray("[{\"url\":\"https://store.steampowered.com/app/123\",\"text\":\"sample\"}]")).equals("game"),"steam type only");
        Files.writeString(Path.of(args[2]),results.toString(2));
        System.out.println("PASS "+count+" native guidance assertions; "+cases.length()+" shared cases; no AI calls or website writes");
    }
}
