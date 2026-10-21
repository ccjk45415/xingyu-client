package moe.cangku.reader;

import java.util.*;
import java.util.regex.*;
import org.jsoup.parser.Parser;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;

/** Lossless native projection: markup is retained in source; only visible text units are edited. */
public final class RichEditorDocument {
    public static final int MAX_SOURCE_CHARS=1000000;
    public static boolean withinCapacity(String source){return source.length()<=MAX_SOURCE_CHARS;}
    public static final class Unit { public final int start,end;public final String text,kind,detail;Unit(int s,int e,String t,String k,String d){start=s;end=e;text=t;kind=k;detail=d;} }
    public static final class Mark { public final int a,b;public final String tag,style;Mark(int a,int b,String tag,String style){this.a=a;this.b=b;this.tag=tag;this.style=style;} }
    public final String source,text;public final List<Unit> units=new ArrayList<>();public final List<Mark> marks=new ArrayList<>();
    private static final Pattern TOKEN=Pattern.compile("<!--(?s:.*?)-->|<(?:[^>\\\"']|\\\"[^\\\"]*\\\"|'[^']*')*>|\\[(dlbox|iframe|collapse|spoiler|vote|poll|lottery)\\b[^\\]]*\\](?s:.*?)\\[/\\1\\]|&(?:#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]+);",Pattern.CASE_INSENSITIVE);
    public RichEditorDocument(String html){
        source=html;StringBuilder out=new StringBuilder();Matcher match=TOKEN.matcher(html);int at=0;Map<String,ArrayDeque<int[]>> opens=new HashMap<>();Map<Integer,String> styles=new HashMap<>();
        while(match.find()){
            appendText(at,match.start(),out);String raw=match.group();int pos=out.length();
            if(raw.startsWith("<!--")){}
            else if(raw.startsWith("[")&&((opens.containsKey("pre")&&!opens.get("pre").isEmpty())||(opens.containsKey("code")&&!opens.get("code").isEmpty()))){appendText(match.start(),match.end(),out);}
            else if(raw.startsWith("[")){String kind=match.group(1).toLowerCase(Locale.ROOT);String label=kind.equals("dlbox")?"下载链接卡片":kind.equals("iframe")?"外部链接组件":"折叠/互动组件";add(match.start(),match.end(),"\uFFFC",kind,label,out);}
            else if(raw.startsWith("&")){add(match.start(),match.end(),Parser.unescapeEntities(raw,false),"text","",out);}
            else {
                Matcher name=Pattern.compile("^<(/?)\\s*([a-zA-Z0-9]+)").matcher(raw);if(name.find()){
                    boolean close=!name.group(1).isEmpty();String tag=name.group(2).toLowerCase(Locale.ROOT);
                    if(tag.equals("img")&&!close){Element img=Jsoup.parseBodyFragment(raw).selectFirst("img");add(match.start(),match.end(),"\uFFFC","image",img==null?"":img.attr("src"),out);}
                    else if(tag.equals("br")||tag.equals("hr")){add(match.start(),match.end(),"\n",tag,"",out);}
                    else if(close){ArrayDeque<int[]> stack=opens.get(tag);if(stack!=null&&!stack.isEmpty()){int[] start=stack.removeLast();marks.add(new Mark(start[0],pos,tag,styles.getOrDefault(start[1],"")));}if(block(tag)&&out.length()>0&&out.charAt(out.length()-1)!='\n'){Matcher next=Pattern.compile("^\\s*<"+tag+"(?:\\s[^>]*)?>",Pattern.CASE_INSENSITIVE).matcher(html.substring(match.end()));if((tag.equals("p")||tag.equals("div"))&&next.find())add(match.start(),match.end()+next.end(),"\n","join","",out);else add(match.end(),match.end(),"\n","break","",out);}}
                    else {opens.computeIfAbsent(tag,k->new ArrayDeque<>()).add(new int[]{pos,match.start()});styles.put(match.start(),raw);}
                }
            }
            at=match.end();
        }
        appendText(at,html.length(),out);if(!units.isEmpty()){Unit last=units.get(units.size()-1);if(last.kind.equals("break")&&out.length()>0&&out.charAt(out.length()-1)=='\n'){units.remove(units.size()-1);out.setLength(out.length()-1);}}text=out.toString();
    }
    private static boolean block(String tag){return Arrays.asList("p","div","h1","h2","h3","h4","h5","h6","li","blockquote","pre","tr","table","details").contains(tag);}
    private void appendText(int a,int b,StringBuilder out){if(!units.isEmpty()){Unit last=units.get(units.size()-1);if(last.kind.equals("join"))a=Math.max(a,last.end);}for(int i=a;i<b;){int n=Character.charCount(source.codePointAt(i));add(i,i+n,source.substring(i,i+n),"text","",out);i+=n;}}
    private void add(int a,int b,String value,String kind,String detail,StringBuilder out){if(value.isEmpty())return;units.add(new Unit(a,b,value,kind,detail));out.append(value);}
    public int sourceOffset(int visible,boolean end){if(end&&visible>0){int n=0;for(Unit unit:units){n+=unit.text.length();if(n>=visible)return unit.end;}}return sourceOffset(visible);}
    public int sourceOffset(int visible){int n=0,previous=0;for(Unit unit:units){if(n>=visible)return unit.kind.equals("break")?previous:unit.start;previous=unit.end;n+=unit.text.length();if(n>visible)return unit.end;}if(!units.isEmpty())return units.get(units.size()-1).end;Matcher open=Pattern.compile("^(?:<[^/!][^>]*>)+").matcher(source);return open.find()?open.end():0;}
    public int visibleOffset(int raw){int n=0;for(Unit unit:units){if(raw<=unit.start)return n;if(raw<unit.end)return n+unit.text.length();n+=unit.text.length();}return n;}
    public int[] enclosing(String tag,int raw){ArrayDeque<Integer> starts=new ArrayDeque<>();Matcher tokens=Pattern.compile("<(/?)"+Pattern.quote(tag)+"(?:\\s[^>]*)?>",Pattern.CASE_INSENSITIVE).matcher(source);while(tokens.find()){if(tokens.group(1).isEmpty())starts.addLast(tokens.start());else if(!starts.isEmpty()){int start=starts.removeLast();if(raw>=start&&raw<=tokens.end())return new int[]{start,tokens.end()};}}return null;}
    public String selectedHtml(int a,int b){StringBuilder result=new StringBuilder();int n=0;for(Unit unit:units){int end=n+unit.text.length();if(end>a&&n<b){if(unit.kind.equals("image")||(!unit.kind.equals("text")&&!unit.text.equals("\n")))result.append(source,unit.start,unit.end);else if(unit.text.equals("\n"))result.append("<br>");else result.append(ReaderContent.escape(unit.text.substring(Math.max(0,a-n),Math.min(unit.text.length(),b-n))));}n=end;}return result.toString();}
    /** Inline formatting is split at markup boundaries, so ranges across paragraphs stay valid. */
    public String wrapVisible(int a,int b,String before,String after){ArrayList<int[]> runs=new ArrayList<>();int n=0;for(Unit unit:units){int end=n+unit.text.length();if(end>a&&n<b&&unit.kind.equals("text")){if(!runs.isEmpty()&&runs.get(runs.size()-1)[1]==unit.start)runs.get(runs.size()-1)[1]=unit.end;else runs.add(new int[]{unit.start,unit.end});}n=end;}StringBuilder result=new StringBuilder(source);for(int i=runs.size()-1;i>=0;i--){int[] run=runs.get(i);result.insert(run[1],after);result.insert(run[0],before);}return result.toString();}
    /** Block insertions split an enclosing paragraph and inline styles rather than nesting paragraphs. */
    public String insertMarkup(int a,int b,String markup){
        int raw=sourceOffset(Math.max(0,Math.min(text.length(),a)));if(markup.matches("(?s)^\\s*<(?:p|div|h[1-6]|ul|ol|blockquote|pre|table|hr)(?:[ >].*)?")){
            ArrayList<String[]> stack=new ArrayList<>();Matcher tags=Pattern.compile("<(/?)([a-zA-Z0-9]+)(?:[^>\"']|\"[^\"]*\"|'[^']*')*>").matcher(source.substring(0,raw));while(tags.find()){String tag=tags.group(2).toLowerCase(Locale.ROOT);if(!tags.group(1).isEmpty()){for(int i=stack.size()-1;i>=0;i--)if(stack.get(i)[0].equals(tag)){while(stack.size()>i)stack.remove(stack.size()-1);break;}}else if(!Arrays.asList("img","br","hr","input","meta","link","source","wbr").contains(tag)&&!tags.group().endsWith("/>"))stack.add(new String[]{tag,tags.group()});}
            int p=-1;for(int i=stack.size()-1;i>=0;i--)if(stack.get(i)[0].equals("p")){p=i;break;}if(p>=0){StringBuilder split=new StringBuilder();for(int i=stack.size()-1;i>=p;i--)split.append("</").append(stack.get(i)[0]).append('>');split.append(markup);for(int i=p;i<stack.size();i++)split.append(stack.get(i)[1]);markup=split.toString();}
        }
        return replaceMarkup(a,b,markup);
    }
    /** Edits remove selected text/images, never unrelated tags or shortcodes. */
    public String replace(int a,int b,String typed){return replaceMarkup(a,b,ReaderContent.escape(typed).replace("\r\n","\n").replace("\r","\n").replace("\n","<br>"));}
    public String replaceMarkup(int a,int b,String markup){a=Math.max(0,Math.min(text.length(),a));b=Math.max(a,Math.min(text.length(),b));int insertion=sourceOffset(a),n=0;ArrayList<int[]> removed=new ArrayList<>();for(Unit unit:units){int end=n+unit.text.length();if(end>a&&n<b&&unit.end>unit.start)removed.add(new int[]{unit.start,unit.end});n=end;}StringBuilder updated=new StringBuilder(source);for(int i=removed.size()-1;i>=0;i--){int[] r=removed.get(i);updated.delete(r[0],r[1]);if(r[1]<=insertion)insertion-=r[1]-r[0];else if(r[0]<insertion)insertion=r[0];}updated.insert(Math.max(0,Math.min(updated.length(),insertion)),markup);return updated.toString();}
}
