#!/usr/bin/env python3
"""Validate local scraped evidence and build an escaped offline review page.

This does not approve content, claim completeness, or publish publisher material.
"""
import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
from collect_pddby import atomic_json, parse_ticket, correct_index


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--require-images', action='store_true')
    args = parser.parse_args()
    folder = args.source.resolve()
    if not any(p in ('scratch', 'output') for p in folder.parts):
        parser.error('Use ignored scratch/ or output/')
    bank = json.loads((folder / 'collected.json').read_text())
    media_path = folder / 'media.json'
    media = json.loads(media_path.read_text()) if media_path.exists() else {}
    missing = set()
    cards = []
    verified_raw = {}
    e = html.escape
    for q in bank['questions'].values():
        raw = {}
        for kind, path in q['evidence'].items():
            target = (folder / path).resolve()
            if not target.is_relative_to(folder / 'raw'):
                raise ValueError('Evidence escapes raw directory')
            data = target.read_bytes()
            verified_raw[path] = hashlib.sha256(data).hexdigest()
            raw[kind] = json.loads(data)
        observed = parse_ticket(raw['question'])
        for key in ('id', 'text', 'answers', 'imageUrls'):
            if observed[key] != q[key]:
                raise ValueError('Normalized question differs from raw response')
        submitted = int(raw['answer']['an'])
        if correct_index(raw['answer'], submitted, len(q['answers']), expected_current=int(raw['question']['current'])) != q['correctIndex']:
            raise ValueError('Normalized answer differs from raw response')
        images = []
        for url in q['imageUrls']:
            entry = media.get(url)
            if not entry:
                missing.add(url)
                images.append('<p>Изображение ещё не загружено</p>')
                continue
            path = (folder / entry['path']).resolve()
            if not path.is_relative_to(folder / 'images'):
                raise ValueError('Image escapes local image directory')
            if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('Image checksum mismatch')
            images.append(f'<img src="{e(entry["path"], quote=True)}" alt="Иллюстрация к вопросу">')
        options = ''.join(f'<li class="{"correct" if i == q["correctIndex"] else ""}">{e(a)}</li>' for i, a in enumerate(q['answers']))
        hint = PlainText(); hint.feed(q['hintHtml'])
        cards.append(f'<article><small>{e(q["id"])} · Разделы {e(str(q["topics"]))}</small><h2>{e(q["text"])}</h2>{"".join(images)}<ol>{options}</ol><p>{e("".join(hint.parts))}</p></article>')
    report = {'questions': len(cards), 'uniqueImageUrls': len({u for q in bank['questions'].values() for u in q['imageUrls']}), 'missingImages': sorted(missing), 'answerEvidenceVerified': True, 'completeness': bank['completeness'], 'checkedAt': bank['checkedAt'], 'ticketsByTopic': bank['ticketsByTopic'], 'rawSha256': verified_raw}
    atomic_json(folder / 'review-report.json', report)
    page = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'"><title>ПДД.by — локальная проверка</title><style>body{font:17px system-ui;max-width:850px;margin:32px auto;padding:0 20px;background:#f8f8fa;color:#172136}article{background:white;padding:24px;margin:20px 0;border-radius:16px}img{display:block;max-width:100%;max-height:400px}li{padding:8px}.correct{background:#e2f5e8;font-weight:600}small{overflow-wrap:anywhere;color:#536176}h2{font-size:21px}</style><h1>ПДД.by — локальная проверка</h1>'''
    page += f'<p>Получено вопросов: {len(cards)}. Правильные ответы сверены с ответами сервера и выделены зелёным. Полнота базы и соответствие всему банку ГАИ не подтверждены.</p>' + ''.join(cards)
    (folder / 'review.html').write_text(page + '</html>')
    print(json.dumps({k:v for k,v in report.items() if k != 'rawSha256'}, ensure_ascii=False))
    if args.require_images and missing:
        raise SystemExit('Missing images; review incomplete')


if __name__ == '__main__':
    main()
