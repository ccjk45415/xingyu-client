import moe.cangku.reader.*;

public class EditorToolsTest {
    private static int checks;
    static void check(boolean v){checks++;if(!v)throw new AssertionError("editor check "+checks);}
    public static void main(String[] args){
        EditorBuffer.State plain=new EditorBuffer.State("A & 星屿\nB",4,6,false);
        EditorBuffer.State bold=EditorBuffer.wrap(plain,"<strong>","</strong>","文字");
        check(bold.text.equals("<p>A &amp; <strong>星屿</strong><br>B</p>"));check(bold.text.substring(bold.a,bold.b).equals("星屿"));
        EditorBuffer.State clean=EditorBuffer.wrap(bold,"<strong>","</strong>","文字");check(clean.text.equals("<p>A &amp; 星屿<br>B</p>"));
        EditorBuffer.State placeholder=EditorBuffer.wrap(new EditorBuffer.State("",0,0,true),"<h2>","</h2>","标题");check(placeholder.text.equals("<h2>标题</h2>"));check(placeholder.text.substring(placeholder.a,placeholder.b).equals("标题"));
        EditorBuffer.State numbered=EditorBuffer.list(new EditorBuffer.State("一\n二",0,3,true),true);check(numbered.text.equals("<ol>\n  <li>一</li>\n  <li>二</li>\n</ol>"));
        EditorBuffer.State original=new EditorBuffer.State("first\n  second\nthird",0,15,false),indented=EditorBuffer.indent(original,false);check(indented.text.equals("  first\n    second\nthird"));check(EditorBuffer.indent(indented,true).text.equals(original.text));
        EditorBuffer.State reversed=EditorBuffer.wrap(new EditorBuffer.State("abcd",3,1,true),"<u>","</u>","");check(reversed.text.equals("a<u>bc</u>d"));
        check(EditorBuffer.replaceAll("a$a$a","a$","b\\$").equals("b\\$b\\$a"));check(EditorBuffer.replaceAll("aaa","aa","x").equals("xa"));
        try{EditorBuffer.replaceAll("a".repeat(1000),"a","b".repeat(2000));throw new AssertionError("oversize replacement accepted");}catch(IllegalArgumentException expected){checks++;}
        EditorBuffer.History history=new EditorBuffer.History(new EditorBuffer.State("",0,0,false));history.record(new EditorBuffer.State("a",1,1,false),true,1000);history.record(new EditorBuffer.State("ab",2,2,false),true,1100);check(history.undo().text.isEmpty());check(history.redo().text.equals("ab"));
        history.record(EditorBuffer.wrap(history.current,"<em>","</em>","文字"),false,1200);EditorBuffer.State undo=history.undo();check(undo.text.equals("ab")&&!undo.html);check(history.redo().html);history.undo();history.record(new EditorBuffer.State("changed",7,7,true),false,1300);check(!history.canRedo());
        for(int i=0;i<80;i++)history.record(new EditorBuffer.State("change"+i,0,0,true),false,2000+i);int steps=0;while(history.canUndo()){history.undo();steps++;}check(steps<=50);
        String css="<span style=\"font-size:24px;color:#8a6adb\">大字<span>里面</span></span><span style='font-size:9px'>小字</span>";
        String marked=EditorStyles.markFontSizes(css);check(marked.contains("<xysize24>大字<span>里面</span></xysize24></span>"));check(!marked.contains("xysize9"));check(css.contains("font-size:24px")&&!css.contains("xysize"));
        String nested=EditorStyles.markFontSizes("<span style='font-size:20px'>a<span style='font-size:14px'>b</span>c</span>");check(nested.contains("<xysize20>a<span style='font-size:14px'><xysize14>b</xysize14></span>c</xysize20>"));
        System.out.println("PASS "+checks+" editor selection, formatting, history, font style and replacement checks");
    }
}
