package moe.cangku.reader;

/** Static editing examples; selected snippets are only inserted into the local draft. */
public final class EditorHints {
    private EditorHints(){}
    public static final String[] LANGUAGES={"cpp","c","python","java","javascript","typescript","dart","kotlin","rust","go","csharp","html","css","json","sql","bash","plaintext"};
    public static final String[] LANGUAGE_NAMES={"C++","C","Python","Java","JavaScript","TypeScript","Dart","Kotlin","Rust","Go","C#","HTML","CSS","JSON","SQL","Shell","纯文本"};
    public static final String[][] ITEMS={
        {"段落与换行","p分段，br换行","<p>第一段文字</p>\n<p>第二段<br>换行文字</p>"},
        {"二级标题","正文大标题","<h2>章节标题</h2>"},
        {"三级标题","正文小标题","<h3>小节标题</h3>"},
        {"加粗与斜体","强调文字","<p><strong>加粗</strong> · <em>斜体</em></p>"},
        {"下划线与删除线","文字标记","<p><u>下划线</u> · <del>删除线</del></p>"},
        {"无序列表","多个平行条目","<ul>\n  <li>第一项</li>\n  <li>第二项</li>\n</ul>"},
        {"有序列表","带编号的步骤","<ol>\n  <li>第一步</li>\n  <li>第二步</li>\n</ol>"},
        {"引用","引用一段说明","<blockquote><p>引用的文字</p></blockquote>"},
        {"超链接","修改href和显示文字","<a href=\"https://example.com\">链接文字</a>"},
        {"图片","src填图片地址，alt填说明","<p><img src=\"https://example.com/image.png\" alt=\"图片说明\"></p>"},
        {"表格","th是表头，td是内容单元格","<table>\n  <thead><tr><th>名称</th><th>说明</th></tr></thead>\n  <tbody><tr><td>内容</td><td>说明文字</td></tr></tbody>\n</table>"},
        {"行内代码","短命令或函数名","<p>使用 <code>function()</code> 完成操作。</p>"},
        {"水平分隔线","分隔正文段落","\n<hr>\n"},
        {"HTML特殊字符","&lt;显示<，&gt;显示>，&amp;显示&","<p>&lt;标签&gt; &amp; 文本</p>"},
        {"下载卡片","仓库专用短代码，修改标题、说明、网盘与链接","[dlbox title=\"资源标题\" info=\"提取码与说明\" link1=\"网盘|https://example.com\"][/dlbox]"}
    };
    public static String codeBlock(String language,String code){
        if(!java.util.Arrays.asList(LANGUAGES).contains(language))throw new IllegalArgumentException("不支持的语言");
        return "\n<pre><code class=\"language-"+language+"\">"+ReaderContent.escape(code)+"</code></pre>\n";
    }
}
