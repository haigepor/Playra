"""从接口文档提取去重端点；描述未提供时保留待核验，不推测字段。"""
import argparse
import json
from pathlib import Path
import re

TOKEN = re.compile(r'`([^`\n]+)`')
PATH = re.compile(r'(?:GET\s+|POST\s+)?(?:https?://[^\s`]+|/?[A-Za-z][A-Za-z0-9_-]*(?:/[A-Za-z0-9_.-]+)+|userInfo|updateProfile)')


def inventory(directory):
    docs = {p.stem: p.read_text(encoding='utf-8') for p in Path(directory).glob('*.md')}
    roots = set()
    for raw in TOKEN.findall(docs['index']):
        if re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*/[A-Za-z0-9_./-]+', raw):
            roots.add(raw.split('/')[0])
    rows = {}
    def add(raw, source, description=None):
        method = 'GET' if raw.startswith('GET ') else 'POST'
        path = re.sub(r'^(GET|POST)\s+', '', raw).split('?')[0]
        if path.startswith(('http://', 'https://')):
            path = path.split('://', 1)[1].split('/', 1)[-1]
        path = path.removeprefix('/api/v1/app/client/').removeprefix('api/v1/app/client/').lstrip('/')
        if path.startswith('api/v1/client/'):
            path = path.removeprefix('api/v1/client/')
        if path not in ('userInfo', 'updateProfile', 'check-update') and path.split('/')[0] not in roots:
            return
        if path in ('auth/bootstrap.jpg', 'check-update'):
            method = 'GET'
        key = (method, path)
        row = rows.setdefault(key, {'method': method, 'path': path, 'documents': [],
                                   'description': '文档仅列出名称；请求与响应字段待核验'})
        if source not in row['documents']: row['documents'].append(source)
        if description: row['description'] = description.strip()
    for source, text in docs.items():
        for raw in TOKEN.findall(text):
            for match in PATH.findall(raw): add(match, source)
        for line in text.splitlines():
            match = re.match(r'(?:GET|POST)\s+\S+', line)
            if match: add(match.group(), source)
            if line.startswith('|'):
                cells = [s.strip() for s in line.strip('|').split('|')]
                if len(cells) > 1:
                    for raw in TOKEN.findall(cells[0]):
                        for match in PATH.findall(raw): add(match, source, cells[-1])
            for raw, description in re.findall(r'`([^`]+)`\s*——\s*(.+)', line):
                for match in PATH.findall(raw): add(match, source, description)
    return sorted(rows.values(), key=lambda row: (row['path'], row['method']))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    args = parser.parse_args()
    print(json.dumps(inventory(args.directory), ensure_ascii=False, indent=2))
