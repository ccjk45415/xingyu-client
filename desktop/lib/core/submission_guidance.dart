import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;

import 'api.dart';
import 'reader.dart';

class GuideIssue {
  final String code, message;
  const GuideIssue(this.code, this.message);
}

/// Local, deterministic advice. Website text never becomes an AI instruction.
class SubmissionGuidance {
  final Json rules;
  SubmissionGuidance(this.rules);
  static Future<SubmissionGuidance> load() async => SubmissionGuidance(
    object(
      jsonDecode(
        await rootBundle.loadString('assets/submission-guidance.json'),
      ),
    ),
  );
  List<Json> get profiles => rows(rules['profiles']);
  String get sourceUrl => text(rules['source_url']);
  String get verifiedOn => text(rules['verified_on']);
  Json profile(String id) =>
      profiles.firstWhere((p) => p['id'] == id, orElse: () => profiles.last);
  List<String> paths(String id) => (profile(id)['paths'] as List)
      .map((p) => (p as List).join(' / '))
      .toList();
  String transportType(String kind) => switch (kind) {
    'game' => 'game',
    'comic' || 'doujin' => 'comic',
    'asmr' => 'asmr',
    'animation' => 'animation',
    _ => 'other',
  };
  String guess(List<Json> sources) {
    final urls = sources.map((s) => text(s['url'])).join('\n').toLowerCase();
    final corpus = sources
        .map((s) => '${text(s['title'])}\n${text(s['text'])}')
        .join('\n')
        .toLowerCase();
    if (urls.contains('store.steampowered.com/app/')) return 'game';
    if (RegExp(r'\basmr\b|音声|音聲').hasMatch(corpus)) return 'asmr';
    return 'other';
  }

  String title(
    String kind,
    String name, {
    String author = '',
    String date = '',
    String attributes = '',
    bool aiImages = false,
  }) {
    String part(String v) => v.replaceAll(RegExp(r'[\[\]\r\n]'), '').trim();
    final prefix = text(profile(kind)['prefix']);
    final leading = [
      '[$prefix]',
      if (part(date).isNotEmpty) '[${part(date)}]',
      if (part(author).isNotEmpty) '[${part(author)}]',
    ].join();
    final tags = attributes
        .split(RegExp(r'[,，\n]'))
        .map(part)
        .where((v) => v.isNotEmpty)
        .toSet();
    if (aiImages) tags.add('AI 生成');
    return '$leading ${name.trim()}${tags.isEmpty ? '' : ' ${tags.map((v) => '[$v]').join()}'}'
        .trim();
  }

  /// IDs come solely from the current account's actual tree, including parents.
  Set<int> resolve(List<Json> tree, String path) {
    if (path.isEmpty) return {};
    var level = tree;
    final ids = <int>{};
    for (final name in path.split(' / ')) {
      String canonical(String value) =>
          value.replaceAll('其它', '其他').replaceAll(RegExp(r'\s+'), '');
      final matches = level
          .where((c) => canonical(text(c['name'])) == canonical(name))
          .toList();
      if (matches.length != 1 || number(matches.single['id']) <= 0) return {};
      ids.add(number(matches.single['id']));
      level = rows(matches.single['children']);
    }
    return ids;
  }

  List<Json> catalog(List<Json> tree) {
    final out = <Json>[];
    void visit(List<Json> level, int parent, int root) {
      for (final c in level) {
        final id = number(c['id']);
        out.add({...c, '_parent': parent, '_root': root == 0 ? id : root});
        visit(rows(c['children']), id, root == 0 ? id : root);
      }
    }

    visit(tree, 0, 0);
    return out;
  }

  List<GuideIssue> check({
    required String title,
    required String body,
    required Set<int> selected,
    required List<Json> tree,
    String kind = 'other',
    bool aiImages = false,
  }) {
    final issues = <GuideIssue>[];
    void add(String code, String message) =>
        issues.add(GuideIssue(code, message));
    final named = title.trim();
    final workName = named
        .replaceFirst(RegExp(r'^(?:\[[^\[\]]+\])+\s*'), '')
        .split(' [')
        .first
        .trim();
    if (workName.isEmpty || workName == '作品介绍') {
      add('title.missing', '请填写具体作品名称，不能直接使用“作品介绍”占位标题。');
    }
    if (!RegExp(r'^\[[^\[\]]+\](?:\[[^\[\]]+\])* \S').hasMatch(named)) {
      add('title.structure', '标题建议使用半角 []；前缀与作品名之间留一个空格。');
    }
    if (RegExp(r'[［］]').hasMatch(named) ||
        kind != 'asmr' && RegExp(r'[【】]').hasMatch(named)) {
      add('title.brackets', '请核对全角括号；音声原名自带的【】可保留，不应批量替换。');
    }
    if (named.runes.length > 500) {
      add('title.length', '标题超过编辑器500字容量，请精简；这不是官网另设的标题下限。');
    }
    if (aiImages && !named.contains('[AI 生成]')) {
      add('title.ai', 'AI生成图片投稿需要在标题标注 [AI 生成]。');
    }
    final all = catalog(tree),
        known = all.where((c) => selected.contains(number(c['id']))).toList();
    final normal = known.where((c) => !text(c['name']).contains('隐藏')).toList();
    if (selected.isEmpty) add('category.missing', '尚未选择分类。根据实际作品选择大类及合适的子类。');
    if (tree.isEmpty || known.length != selected.length) {
      add('category.unknown', '当前分类目录不完整，无法完整检查；请联网打开分类选择后复核。');
    }
    if (known.isNotEmpty && normal.isEmpty) {
      add('category.hidden', '不能只选择隐藏分类，需要同时选择作品所属分类。');
    }
    if (normal.any(
      (c) =>
          number(c['_parent']) > 0 && !selected.contains(number(c['_parent'])),
    )) {
      add('category.parent', '已选子类缺少上级分类，请同时选择大类。');
    }
    if (normal.any(
      (c) =>
          number(c['_parent']) == 0 &&
          rows(c['children']).isNotEmpty &&
          !normal.any((n) => number(n['_parent']) == number(c['id'])),
    )) {
      add('category.child', '目前只选了大类；存在合适子类时需要一并勾选。');
    }
    if (normal.map((c) => number(c['_root'])).toSet().length > 1) {
      add('category.cross', '选择跨越多个大类，请确认符合官网规则；少数特殊组合需人工核对。');
    }
    if (aiImages && !selected.containsAll(resolve(tree, '图片 / 图包')) ||
        aiImages && resolve(tree, '图片 / 图包').isEmpty) {
      add('category.ai', 'AI图片应归入 图片 / 图包，目录不可用时请手动核对。');
    }
    final fragment = html.parseFragment(body);
    for (final node in fragment.querySelectorAll('pre,code,script,style')) {
      node.remove();
    }
    final imageCount = fragment.querySelectorAll('img').where((e) {
      final u = Uri.tryParse(e.attributes['src'] ?? '');
      return u?.scheme == 'https' && u!.host.isNotEmpty && u.userInfo.isEmpty;
    }).length;
    if (imageCount == 0) add('body.image', '正文未发现有效HTTPS配图；封面和商店链接不能代替正文介绍图片。');
    final resourceDoc = ReaderDocument.parse(fragment.outerHtml);
    final downloads = resourceDoc.resources
        .expand((r) => r.links.values)
        .toList();
    final article =
        kind == 'article' ||
        normal.any((c) => (rules['article_only'] as List).contains(c['name']));
    if (article) {
      add('body.original', '该文章类型可能要求本人原创；网页翻译不能自动视为原创，请核对所选分类。');
      if (downloads.isNotEmpty) {
        add('body.article_download', '纯文章分类通常不允许资源下载，请核对下载卡片和分类。');
      }
    } else if (downloads.isEmpty) {
      add('download.missing', '未发现下载卡片；请补充实际资源下载地址。作品商店和资料来源链接不等于下载地址。');
    } else {
      bool white(String raw) {
        final u = Uri.tryParse(raw);
        return u != null &&
            ['http', 'https'].contains(u.scheme) &&
            u.userInfo.isEmpty &&
            (rules['white_hosts'] as List).any(
              (h) =>
                  u.host.toLowerCase() == h ||
                  u.host.toLowerCase().endsWith('.$h'),
            );
      }

      if (!downloads.any(white)) {
        add(
          'download.whitelist',
          '下载卡片中未识别到白名单网盘。IPFS、官方软件来源等特殊情况及未识别域名请对照官网人工核对。',
        );
      }
      if (downloads.any((u) => Uri.tryParse(u)?.host == 'adf.ly')) {
        add('download.redirect', '请使用直接下载地址，避免需等待跳转的推广短链。');
      }
    }
    final software = kind == 'software' || normal.any((c) => c['name'] == '工具');
    if (software) {
      final vt = fragment.querySelectorAll('a[href]').any((e) {
        final u = Uri.tryParse(e.attributes['href']!);
        return u?.scheme == 'https' &&
            u!.userInfo.isEmpty &&
            (u.host == 'virustotal.com' || u.host == 'www.virustotal.com') &&
            u.path.contains('/file/');
      });
      if (!vt) {
        add('software.scan', '软件投稿缺少 VirusTotal 文件检测结果链接；请自行检测后填写，不生成虚构检测结果。');
      }
      add('software.screenshot', '还需检查正文包含对应的真实查毒结果截图。程序不能通过图片链接判断截图内容。');
    }
    if (named.contains('合集')) {
      if (!RegExp(r'\d').hasMatch(named)) {
        add('collection.count', '合集标题需写明实际数量，请按资源核实填写。');
      }
      if (!(fragment.text ?? '').contains('目录')) {
        add('collection.index', '合集正文需提供具体目录，建议用可搜索的文字列表。');
      }
    }
    return issues;
  }

  String report(List<GuideIssue> issues) =>
      '官网规范辅助检查 · 核对于 $verifiedOn\n${issues.isEmpty ? '自动项目未发现缺项；仍需人工核对图片、权限、资源可用性和最新规则。' : issues.map((i) => '• ${i.message}').join('\n')}\n\n${(rules['manual_checks'] as List).map((s) => '• $s').join('\n')}\n${text(rules['notice'])}';
}
