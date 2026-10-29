"""Audit local documentation links without treating historical evidence as current.

Checks Markdown links and HTML hrefs, including Markdown heading fragments.
Does not execute the application, replay captures, or validate indexed raw payloads.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
import re
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r'!?\[[^\]\n]+\]\(([^)\n]+)\)|href=["\x27]([^"\x27]+)')


def scope(path):
    parts = path.relative_to(ROOT).parts
    if parts[1] in ('history', 'search', 'cleanup'):
        return 'historical'
    if parts[1] == 'competitor':
        return 'competitor'
    return 'current'


def heading_ids(path):
    ids = set()
    counts = Counter()
    for heading in re.findall(r'^#{1,6}\s+(.+?)\s*#*$', path.read_text(encoding='utf-8-sig'), re.M):
        slug = re.sub(r'[^\w\-\s]', '', heading.lower()).replace(' ', '-')
        n = counts[slug]
        counts[slug] += 1
        ids.add(f'{slug}-{n}' if n else slug)
    return ids


def audit(include_history=False):
    files = sorted((ROOT / 'docs').rglob('*.md')) + sorted((ROOT / 'docs').glob('*.html'))
    records = []
    documents = {}
    anchors = {}
    for path in files:
        # Source snapshots and machine evidence retain their original relative links.
        if 'evidence' in path.relative_to(ROOT / 'docs').parts:
            continue
        group = scope(path)
        if group == 'historical' and not include_history:
            continue
        raw = path.read_bytes()
        text = raw.decode('utf-8-sig')
        rel = path.relative_to(ROOT).as_posix()
        documents[rel] = {'scope': group, 'sha256': hashlib.sha256(raw).hexdigest()}
        for match in LINK.finditer(text):
            target = unquote((match[1] or match[2]).strip('<>'))
            if re.match(r'^(?:https?|mailto|javascript|data|res|uid):', target):
                continue
            filename, _, fragment = target.partition('#')
            resolved = (path.parent / filename.split('?')[0]).resolve() if filename else path
            exists = resolved.exists()
            status = 'present' if exists else 'missing'
            if exists and fragment and resolved.suffix == '.md':
                if resolved not in anchors:
                    anchors[resolved] = heading_ids(resolved)
                if fragment not in anchors[resolved]:
                    status = 'missing_anchor'
            records.append({'document': rel, 'scope': group,
                            'line': text.count('\n', 0, match.start()) + 1,
                            'target': target, 'status': status})
    summary = {}
    for group in ('current', 'competitor', 'historical'):
        rows = [row for row in records if row['scope'] == group]
        summary[group] = {'documents': sum(v['scope'] == group for v in documents.values()),
                          'links': len(rows), **dict(Counter(row['status'] for row in rows))}
    return {'schema': 1, 'scope': 'Local Markdown links and HTML hrefs only; no raw-payload or algorithm validation.',
            'summary': summary, 'documents': documents, 'links': records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--include-history', action='store_true')
    parser.add_argument('--check', action='store_true', help='Fail on unresolved current and competitor topic links; historical evidence is report-only.')
    args = parser.parse_args()
    result = audit(args.include_history)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result['summary'], ensure_ascii=False))
    if args.check and any(r['scope'] in ('current', 'competitor') and r['status'] != 'present' for r in result['links']):
        raise SystemExit('Maintained documentation contains unresolved links; inspect the output report.')


if __name__ == '__main__':
    main()
