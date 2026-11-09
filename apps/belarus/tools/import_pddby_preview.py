#!/usr/bin/env python3
"""Import a frozen, evidence-verified local snapshot for BY_CONTENT_PREVIEW.

Publisher content stays ignored by Git. This never approves an examination bank.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from collect_pddby import atomic_json
from review_pddby import PlainText


def build_catalog(bank, media):
    questions = []
    seen = set()
    for q in bank['questions'].values():
        images = []
        for url in q['imageUrls']:
            entry = media[url]
            suffix = Path(entry['path']).suffix.lower()
            if suffix not in ('.jpg', '.jpeg', '.png', '.webp', '.gif'):
                raise ValueError('Unsupported image extension')
            images.append(f"assets/countries/by/preview_{entry['sha256']}{suffix}")
        key = (q['text'], tuple(sorted(q['answers'])), tuple(images))
        if key in seen:
            raise ValueError('Duplicate question content; review before importing')
        seen.add(key)
        hint = PlainText()
        hint.feed(q['hintHtml'])
        questions.append({
            'id': q['id'], 'text': q['text'], 'answers': q['answers'],
            'correctIndex': q['correctIndex'], 'subject': q['subject'],
            'sourceId': 'pddby', 'imageAssets': images,
            'explanation': ''.join(hint.parts).strip() or 'ПДД.by',
        })
    return {
        'schemaVersion': 1, 'country': 'by', 'revision': 'preview-' + bank['checkedAt'],
        'previewOnly': True, 'reviewStatus': 'pending', 'examRulesReviewed': False,
        'sources': [{'id': 'pddby', 'url': bank['source'],
                     'license': 'Owner-reported publisher permission for website parsing; local testing only',
                     'revision': bank['checkedAt'], 'checkedAt': bank['checkedAt'],
                     'reviewStatus': 'pending'}],
        'questions': questions,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    args = parser.parse_args()
    source = args.snapshot.resolve()
    tools = Path(__file__).resolve().parent
    subprocess.run([sys.executable, str(tools / 'review_pddby.py'), str(source), '--require-images'], check=True)
    bank = json.loads((source / 'collected.json').read_text())
    media = json.loads((source / 'media.json').read_text())
    catalog = build_catalog(bank, media)
    target = tools.parent / 'assets/countries/by'
    for q in bank['questions'].values():
        for url in q['imageUrls']:
            entry = media[url]
            image = (source / entry['path']).resolve()
            if not image.is_relative_to(source / 'images'):
                raise ValueError('Image escapes snapshot')
            if hashlib.sha256(image.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('Image checksum mismatch')
            destination = target / f"preview_{entry['sha256']}{image.suffix.lower()}"
            if not destination.exists():
                shutil.copyfile(image, destination)
            if hashlib.sha256(destination.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('Imported image checksum mismatch')
    atomic_json(target / 'preview_catalog.json', catalog)
    print(json.dumps({'imported': len(catalog['questions']), 'previewOnly': True}))


if __name__ == '__main__':
    main()
