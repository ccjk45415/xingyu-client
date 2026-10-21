package moe.cangku.reader;

import java.util.*;

/** Local source editing, bounded undo history, and selection-preserving markup. */
public final class EditorBuffer {
    private EditorBuffer(){}
    public static final class State {
        public final String text;public final int a,b;public final boolean html;
        public State(String text,int start,int end,boolean html){this.text=text;this.a=Math.max(0,Math.min(text.length(),Math.min(start,end)));this.b=Math.max(a,Math.min(text.length(),Math.max(start,end)));this.html=html;}
        public State asHtml(){if(html)return this;return new State(AuthoringRules.editablePlainHtml(text),AuthoringRules.plainOffset(text,a),AuthoringRules.plainOffset(text,b),true);}
    }
    public static final class History {
        public State current;private final ArrayDeque<State> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();private long typingAt;
        public History(State s){current=s;}
        public boolean canUndo(){return !undo.isEmpty();}public boolean canRedo(){return !redo.isEmpty();}
        public void select(State s){current=s;}
        public void record(State next,boolean typing,long now){
            if(next.text.equals(current.text)&&next.html==current.html){current=next;return;}
            boolean merge=typing&&typingAt>0&&now-typingAt<750&&Math.abs(next.text.length()-current.text.length())<=2;
            if(!merge)undo.addLast(current);current=next;redo.clear();typingAt=typing?now:0;
            int chars=0;for(State s:undo)chars+=s.text.length();while(undo.size()>50||(!undo.isEmpty()&&chars>2000000))chars-=undo.removeFirst().text.length();
        }
        public State undo(){if(undo.isEmpty())return null;redo.addLast(current);current=undo.removeLast();typingAt=0;return current;}
        public State redo(){if(redo.isEmpty())return null;undo.addLast(current);current=redo.removeLast();typingAt=0;return current;}
    }
    public static State insert(State raw,String markup){State v=raw.asHtml();return new State(v.text.substring(0,v.a)+markup+v.text.substring(v.b),v.a+markup.length(),v.a+markup.length(),true);}
    public static State wrap(State raw,String before,String after,String placeholder){
        State v=raw.asHtml();String selected=v.text.substring(v.a,v.b);
        if(v.a>=before.length()&&v.text.substring(v.a-before.length(),v.a).equals(before)&&v.text.substring(v.b).startsWith(after)){
            return new State(v.text.substring(0,v.a-before.length())+selected+v.text.substring(v.b+after.length()),v.a-before.length(),v.b-before.length(),true);
        }
        String body=selected.isEmpty()?placeholder:selected;
        return new State(v.text.substring(0,v.a)+before+body+after+v.text.substring(v.b),v.a+before.length(),v.a+before.length()+body.length(),true);
    }
    public static State list(State raw,boolean ordered){State v=raw.asHtml();String body=v.text.substring(v.a,v.b),tag=ordered?"ol":"ul";StringBuilder out=new StringBuilder("<"+tag+">\n");for(String line:(body.isEmpty()?"第一项\n第二项":body).replace("\r\n","\n").split("\n",-1))out.append("  <li>").append(line).append("</li>\n");out.append("</").append(tag).append(">");return insert(v,out.toString());}
    public static State indent(State v,boolean outdent){
        int from=v.a==0?0:v.text.lastIndexOf('\n',v.a-1)+1,to=v.b>v.a&&v.text.charAt(v.b-1)=='\n'?v.b-1:v.b,tail=v.text.indexOf('\n',to),until=tail<0?v.text.length():tail;
        String[] lines=v.text.substring(from,until).split("\n",-1);int delta=0,first=0;
        for(int i=0;i<lines.length;i++){String old=lines[i];lines[i]=outdent?old.replaceFirst("^(?:\\t| {1,2})",""):"  "+old;int n=lines[i].length()-old.length();delta+=n;if(i==0)first=n;}
        String result=v.text.substring(0,from)+String.join("\n",lines)+v.text.substring(until);return new State(result,Math.max(from,v.a+first),Math.max(from,v.b+delta),v.html);
    }
    public static String replaceAll(String source,String needle,String replacement){
        if(needle.isEmpty())return source;int count=0,offset=0;while(true){int at=source.indexOf(needle,offset);if(at<0)break;count++;offset=at+needle.length();}
        if(source.length()+(long)count*(replacement.length()-needle.length())>1000000)throw new IllegalArgumentException("替换结果超过100万字符，请缩小范围");return source.replace(needle,replacement);
    }
}
