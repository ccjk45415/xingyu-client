package moe.cangku.reader;

import org.json.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.*;
import java.util.*;
import java.net.URI;
import java.util.regex.Pattern;

/** Deterministic local advice. Source material is never promoted to AI instructions. */
public final class SubmissionGuidance {
    public final JSONObject rules;
    public SubmissionGuidance(String json)throws JSONException{rules=new JSONObject(json);}
    public JSONArray profiles(){return rules.optJSONArray("profiles");}
    public JSONObject profile(String id){JSONArray list=profiles();for(int i=0;i<list.length();i++)if(list.optJSONObject(i).optString("id").equals(id))return list.optJSONObject(i);return list.optJSONObject(list.length()-1);}
    public ArrayList<String> paths(String id){ArrayList<String> out=new ArrayList<>();JSONArray paths=profile(id).optJSONArray("paths");for(int i=0;i<paths.length();i++){JSONArray p=paths.optJSONArray(i);ArrayList<String> names=new ArrayList<>();for(int j=0;j<p.length();j++)names.add(p.optString(j));out.add(String.join(" / ",names));}return out;}
    public String transportType(String id){switch(id){case "game":return "game";case "doujin":case "comic":return "comic";case "asmr":return "asmr";case "animation":return "animation";default:return "other";}}
    public String guess(JSONArray sources){StringBuilder words=new StringBuilder();for(int i=0;i<sources.length();i++){JSONObject s=sources.optJSONObject(i);if(s.optString("url").toLowerCase(Locale.ROOT).contains("store.steampowered.com/app/"))return "game";words.append(s.optString("title")).append('\n').append(s.optString("text")).append('\n');}return Pattern.compile("(?i)\\basmr\\b|音声|音聲").matcher(words).find()?"asmr":"other";}
    private static String part(String value){return value.replaceAll("[\\[\\]\\r\\n]","").trim();}
    public String title(String kind,String name,String author,String date,String attrs,boolean aiImages){StringBuilder out=new StringBuilder("["+profile(kind).optString("prefix")+"]");if(!part(date).isEmpty())out.append('[').append(part(date)).append(']');if(!part(author).isEmpty())out.append('[').append(part(author)).append(']');out.append(' ').append(name.trim());LinkedHashSet<String> tags=new LinkedHashSet<>();for(String tag:attrs.split("[,，\\n]"))if(!part(tag).isEmpty())tags.add(part(tag));if(aiImages)tags.add("AI 生成");if(!tags.isEmpty()){out.append(' ');for(String tag:tags)out.append('[').append(tag).append(']');}return out.toString().trim();}
    private static String canonical(String name){return name.replace("其它","其他").replaceAll("\\s+","");}
    public LinkedHashSet<Long> resolve(JSONArray tree,String path){LinkedHashSet<Long> out=new LinkedHashSet<>();if(path.isEmpty())return out;JSONArray level=tree;for(String name:path.split(" / ")){JSONObject found=null;for(int i=0;level!=null&&i<level.length();i++){JSONObject c=level.optJSONObject(i);if(c!=null&&canonical(c.optString("name")).equals(canonical(name))){if(found!=null)return new LinkedHashSet<>();found=c;}}if(found==null||found.optLong("id")<=0)return new LinkedHashSet<>();out.add(found.optLong("id"));level=found.optJSONArray("children");}return out;}
    public ArrayList<JSONObject> catalog(JSONArray tree){ArrayList<JSONObject> out=new ArrayList<>();visit(tree,0,0,out);return out;}
    private void visit(JSONArray level,long parent,long root,ArrayList<JSONObject> out){if(level==null)return;for(int i=0;i<level.length();i++){JSONObject c=level.optJSONObject(i);if(c==null)continue;try{JSONObject copy=new JSONObject(c.toString());long id=c.optLong("id");copy.put("_parent",parent).put("_root",root==0?id:root);out.add(copy);visit(c.optJSONArray("children"),id,root==0?id:root,out);}catch(JSONException ignored){}}}
    public static final class Issue{public final String code,message;Issue(String c,String m){code=c;message=m;}}
    private void add(ArrayList<Issue> out,String code,String text){out.add(new Issue(code,text));}
    public ArrayList<Issue> check(String title,String body,Set<Long> selected,JSONArray tree,String kind,boolean aiImages){
        ArrayList<Issue> out=new ArrayList<>();String named=title.trim();
        String workName=named.replaceFirst("^(?:\\[[^\\[\\]]+\\])+\\s*","").split(" \\[",2)[0].trim();
        if(workName.isEmpty()||workName.equals("作品介绍"))add(out,"title.missing","请填写具体作品名称，不能直接使用“作品介绍”占位标题。");
        if(!Pattern.compile("^\\[[^\\[\\]]+\\](?:\\[[^\\[\\]]+\\])* \\S").matcher(named).find())add(out,"title.structure","标题建议使用半角 []；前缀与作品名之间留一个空格。");
        if(Pattern.compile("[［］]").matcher(named).find()||!kind.equals("asmr")&&Pattern.compile("[【】]").matcher(named).find())add(out,"title.brackets","请核对全角括号；音声原名自带的【】可保留，不应批量替换。");
        if(named.codePointCount(0,named.length())>500)add(out,"title.length","标题超过编辑器500字容量，请精简；这不是官网另设的标题下限。");
        if(aiImages&&!named.contains("[AI 生成]"))add(out,"title.ai","AI生成图片投稿需要在标题标注 [AI 生成]。");
        ArrayList<JSONObject> known=new ArrayList<>(),normal=new ArrayList<>();for(JSONObject c:catalog(tree))if(selected.contains(c.optLong("id"))){known.add(c);if(!c.optString("name").contains("隐藏"))normal.add(c);}
        if(selected.isEmpty())add(out,"category.missing","尚未选择分类。根据实际作品选择大类及合适的子类。");
        if(tree==null||tree.length()==0||known.size()!=selected.size())add(out,"category.unknown","当前分类目录不完整，无法完整检查；请联网打开分类选择后复核。");
        if(!known.isEmpty()&&normal.isEmpty())add(out,"category.hidden","不能只选择隐藏分类，需要同时选择作品所属分类。");
        boolean parentMissing=false,childMissing=false;Set<Long> roots=new HashSet<>();for(JSONObject c:normal){long id=c.optLong("id"),parent=c.optLong("_parent");roots.add(c.optLong("_root"));if(parent>0&&!selected.contains(parent))parentMissing=true;if(parent==0&&c.optJSONArray("children")!=null&&c.optJSONArray("children").length()>0){boolean found=false;for(JSONObject n:normal)if(n.optLong("_parent")==id)found=true;if(!found)childMissing=true;}}
        if(parentMissing)add(out,"category.parent","已选子类缺少上级分类，请同时选择大类。");if(childMissing)add(out,"category.child","目前只选了大类；存在合适子类时需要一并勾选。");if(roots.size()>1)add(out,"category.cross","选择跨越多个大类，请确认符合官网规则；少数特殊组合需人工核对。");
        Set<Long> aiPath=resolve(tree,"图片 / 图包");if(aiImages&&(aiPath.isEmpty()||!selected.containsAll(aiPath)))add(out,"category.ai","AI图片应归入 图片 / 图包，目录不可用时请手动核对。");
        Document doc=Jsoup.parseBodyFragment(body);doc.select("pre,code,script,style").remove();int imageCount=0;for(Element img:doc.select("img"))try{URI u=new URI(img.attr("src"));if("https".equals(u.getScheme())&&u.getHost()!=null&&u.getUserInfo()==null)imageCount++;}catch(Exception ignored){}
        if(imageCount==0)add(out,"body.image","正文未发现有效HTTPS配图；封面和商店链接不能代替正文介绍图片。");
        ArrayList<String> downloads=new ArrayList<>();for(ReaderContent.Resource r:ReaderContent.parse(doc.body().html()).resources)downloads.addAll(r.links.values());
        boolean article=kind.equals("article"),software=kind.equals("software");JSONArray articleOnly=rules.optJSONArray("article_only");for(JSONObject c:normal){if(c.optString("name").equals("工具"))software=true;for(int i=0;i<articleOnly.length();i++)if(articleOnly.optString(i).equals(c.optString("name")))article=true;}
        if(article){add(out,"body.original","该文章类型可能要求本人原创；网页翻译不能自动视为原创，请核对所选分类。");if(!downloads.isEmpty())add(out,"body.article_download","纯文章分类通常不允许资源下载，请核对下载卡片和分类。");}
        else if(downloads.isEmpty())add(out,"download.missing","未发现下载卡片；请补充实际资源下载地址。作品商店和资料来源链接不等于下载地址。");
        else {boolean white=false,redirect=false;for(String link:downloads){if(white(link))white=true;try{if("adf.ly".equals(new URI(link).getHost()))redirect=true;}catch(Exception ignored){}}if(!white)add(out,"download.whitelist","下载卡片中未识别到白名单网盘。IPFS、官方软件来源等特殊情况及未识别域名请对照官网人工核对。");if(redirect)add(out,"download.redirect","请使用直接下载地址，避免需等待跳转的推广短链。");}
        if(software){boolean vt=false;for(Element a:doc.select("a[href]"))try{URI u=new URI(a.attr("href"));if("https".equals(u.getScheme())&&u.getUserInfo()==null&&Arrays.asList("virustotal.com","www.virustotal.com").contains(u.getHost())&&u.getPath().contains("/file/"))vt=true;}catch(Exception ignored){}if(!vt)add(out,"software.scan","软件投稿缺少 VirusTotal 文件检测结果链接；请自行检测后填写，不生成虚构检测结果。");add(out,"software.screenshot","还需检查正文包含对应的真实查毒结果截图。程序不能通过图片链接判断截图内容。");}
        if(named.contains("合集")){if(!Pattern.compile("\\d").matcher(named).find())add(out,"collection.count","合集标题需写明实际数量，请按资源核实填写。");if(!doc.text().contains("目录"))add(out,"collection.index","合集正文需提供具体目录，建议用可搜索的文字列表。");}
        return out;
    }
    private boolean white(String raw){try{URI u=new URI(raw);if(!Arrays.asList("http","https").contains(u.getScheme())||u.getUserInfo()!=null||u.getHost()==null)return false;String host=u.getHost().toLowerCase(Locale.ROOT);JSONArray list=rules.optJSONArray("white_hosts");for(int i=0;i<list.length();i++)if(host.equals(list.optString(i))||host.endsWith("."+list.optString(i)))return true;}catch(Exception ignored){}return false;}
    public String report(ArrayList<Issue> issues){StringBuilder out=new StringBuilder("官网规范辅助检查 · 核对于 "+rules.optString("verified_on")+"\n");if(issues.isEmpty())out.append("自动项目未发现缺项；仍需人工核对图片、权限、资源可用性和最新规则。\n");for(Issue i:issues)out.append("• ").append(i.message).append('\n');out.append('\n');JSONArray manual=rules.optJSONArray("manual_checks");for(int i=0;i<manual.length();i++)out.append("• ").append(manual.optString(i)).append('\n');return out.append(rules.optString("notice")).toString();}
}
