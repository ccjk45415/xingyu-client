import 'dart:convert';

const codeLanguages = <String, String>{
  'cpp': 'C++',
  'c': 'C',
  'python': 'Python',
  'java': 'Java',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'dart': 'Dart',
  'kotlin': 'Kotlin',
  'rust': 'Rust',
  'go': 'Go',
  'csharp': 'C#',
  'html': 'HTML',
  'css': 'CSS',
  'json': 'JSON',
  'sql': 'SQL',
  'bash': 'Shell',
  'plaintext': '纯文本',
};
String codeBlock(String language, String code) {
  if (!codeLanguages.containsKey(language)) throw ArgumentError('不支持的语言');
  return '\n<pre><code class="language-$language">${const HtmlEscape().convert(code)}</code></pre>\n';
}

const htmlHints = <({String title, String note, String code})>[
  (title: '段落与换行', note: 'p分段，br换行', code: '<p>第一段文字</p>\n<p>第二段<br>换行文字</p>'),
  (title: '二级标题', note: '正文大标题', code: '<h2>章节标题</h2>'),
  (title: '三级标题', note: '正文小标题', code: '<h3>小节标题</h3>'),
  (
    title: '加粗与斜体',
    note: '强调文字',
    code: '<p><strong>加粗</strong> · <em>斜体</em></p>',
  ),
  (title: '下划线与删除线', note: '文字标记', code: '<p><u>下划线</u> · <del>删除线</del></p>'),
  (
    title: '无序列表',
    note: '多个平行条目',
    code: '<ul>\n  <li>第一项</li>\n  <li>第二项</li>\n</ul>',
  ),
  (
    title: '有序列表',
    note: '带编号的步骤',
    code: '<ol>\n  <li>第一步</li>\n  <li>第二步</li>\n</ol>',
  ),
  (title: '引用', note: '引用一段说明', code: '<blockquote><p>引用的文字</p></blockquote>'),
  (
    title: '超链接',
    note: '修改href和显示文字',
    code: '<a href="https://example.com">链接文字</a>',
  ),
  (
    title: '图片',
    note: 'src填图片地址，alt填说明',
    code: '<p><img src="https://example.com/image.png" alt="图片说明"></p>',
  ),
  (
    title: '表格',
    note: 'th是表头，td是内容单元格',
    code: '<table>\n  <thead><tr><th>名称</th><th>说明</th></tr></thead>\n  <tbody><tr><td>内容</td><td>说明文字</td></tr></tbody>\n</table>',
  ),
  (
    title: '行内代码',
    note: '短命令或函数名',
    code: '<p>使用 <code>function()</code> 完成操作。</p>',
  ),
  (title: '水平分隔线', note: '分隔正文段落', code: '\n<hr>\n'),
  (
    title: 'HTML特殊字符',
    note: '&lt;显示<，&gt;显示>，&amp;显示&',
    code: '<p>&lt;标签&gt; &amp; 文本</p>',
  ),
  (
    title: '下载卡片',
    note: '仓库专用短代码，修改标题、说明、网盘与链接',
    code: '[dlbox title="资源标题" info="提取码与说明" link1="网盘|https://example.com"][/dlbox]',
  ),
];
