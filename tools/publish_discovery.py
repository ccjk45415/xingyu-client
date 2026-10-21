"""Validate or publish discovery DATA without building or updating either client."""
import argparse
import json
import re
import urllib.error
from pathlib import Path
from publish_announcement import KEY, request


def load(path):
    value = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not isinstance(value, dict) or set(value) != {'title', 'content'}:
        raise ValueError('发现文件只应包含 title/content 字段')
    for field, limit in [('title', 80), ('content', 1500)]:
        if (not isinstance(value[field], str) or not value[field].strip()
                or len(value[field]) > limit
                or re.search('[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', value[field])):
            raise ValueError('发现标题或正文无效')
    return {key: value[key].strip() for key in ['title', 'content']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'publish'])
    parser.add_argument('file')
    args = parser.parse_args()
    value = load(args.file)
    if args.command == 'validate':
        print('PASS 发现格式；未连接或修改线上服务。')
        return
    if not KEY.is_file():
        raise ValueError('请先使用 publish_announcement.py configure 配置共用发布密钥。')
    secret = KEY.read_text(encoding='ascii').strip()
    if not re.fullmatch('[a-f0-9]{64}', secret):
        raise ValueError('本机发布密钥格式无效')
    revision = request('/discovery')['revision']
    result = request('/discovery/publish', {**value, 'base_revision': revision}, secret)
    if not result.get('ok'):
        raise RuntimeError('发现发布未被确认')
    latest = request('/discovery')
    if (latest.get('revision') != result['revision']
            or any(latest.get(key) != text for key, text in value.items())):
        raise RuntimeError('发现已提交，但随后内容已变化，请读取最新内容确认')
    print('发现数据已发布并校验，版本', result['revision'], '；未修改公告、未发布客户端。')


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        raise SystemExit('发现服务返回HTTP ' + str(error.code) + '；未自动重试覆盖。')
    except Exception as error:
        raise SystemExit(str(error))
