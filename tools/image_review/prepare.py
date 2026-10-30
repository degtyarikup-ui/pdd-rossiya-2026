"""Cache the user-approved Drom mirror of exam illustrations by ticket position.
Run with requests and Pillow installed. Does not modify application assets.
"""
import concurrent.futures
import hashlib
import html
import io
import json
from pathlib import Path
import re
import time
import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'output/image-review'


def get(url, path):
    if path.exists():
        return path.read_bytes()
    for attempt in range(3):
        try:
            r = requests.get(url, timeout=25)
            r.raise_for_status()
            path.write_bytes(r.content)
            return r.content
        except requests.RequestException:
            if attempt == 2:
                raise
            time.sleep(1+attempt)


def ticket(number):
    url = f'https://www.drom.ru/pdd/bilet_{number}/'
    source = get(url, DATA/'pages'/f'{number}.html').decode('windows-1251')
    sections = re.split(r'<a name="(\d+)"></a>', source)
    result = {}
    for i in range(1, len(sections), 2):
        n = int(sections[i])
        block = sections[i+1]
        match = re.search(r'<img[^>]+src="(https://[^" ]+/pdd/tickets/[^" ]+)"', block)
        title = re.search(r'<div class="b-title b-title_type_h4 b-title_no-margin">(.*?)</div>', block, re.S)
        result[f'{number:02d}-{n:02d}'] = dict(url=match[1] if match else None,
            pageUrl=f'{url}vopros_{n}/', question=html.unescape(re.sub('<[^>]+>', '', title[1])).strip() if title else '')
    if len(result) != 20:
        raise ValueError(f'Ticket {number}: expected 20 questions, found {len(result)}')
    return result


def download(item):
    key, ref = item
    if not ref['url']:
        return key, None
    suffix = Path(ref['url']).suffix.lower()
    if suffix not in ('.jpg', '.png', '.webp', '.jpeg'):
        raise ValueError(ref['url'])
    name = key+suffix
    blob = get(ref['url'], DATA/'official'/name)
    with Image.open(io.BytesIO(blob)) as image:
        image.verify()
    return key, dict(ref, file=name, edition='Копия экзаменационной иллюстрации · Дром',
                     sha256=hashlib.sha256(blob).hexdigest(), provenance='drom-mirror')


def main():
    for folder in ('pages', 'official'):
        (DATA/folder).mkdir(parents=True, exist_ok=True)
    bank=json.loads((ROOT/'assets/countries/ru/questions/questions_ab.json').read_text())
    questions=[]
    for t in bank['tickets']:
        for number,q in enumerate(t['questions'],1):
            if q.get('image'):
                questions.append(dict(q,key=f'{t["number"]:02d}-{number:02d}',ticketNumber=t['number'],questionNumber=number))
    refs={}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(ticket,range(1,41)):
            refs.update(result)
            print(f'Parsed {len(refs)//20}/40 tickets',flush=True)
    images={}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for i,(key,ref) in enumerate(pool.map(download,[(q['key'],refs[q['key']]) for q in questions]),1):
            images[key]=ref
            if i%50==0:print(f'Downloaded {i}/{len(questions)} images',flush=True)
    def normalize(s):
        return re.sub(r'[^а-яёa-z0-9]', '', s.lower().replace('ё','е'))
    mismatches=[]
    for q in questions:
        q['official']=images[q['key']]
        q['referenceQuestion']=refs[q['key']]['question']
        q['textMatches']=normalize(q['question'])==normalize(q['referenceQuestion'])
        if not q['textMatches']: mismatches.append(q['key'])
        if not (ROOT/'assets/countries/ru/images/questions_ab'/(q['image']+'.webp')).exists():
            raise ValueError(f'Missing application image {q["key"]}')
    manifest=dict(questions=questions,source='https://www.drom.ru/pdd/',
        notice='Эталон: копия экзаменационных иллюстраций на Дроме (согласованный источник). Это не файлы, полученные напрямую от ГИБДД. Оригиналы сохранены без обработки; ссылка на источник — ниже.')
    out=DATA/'manifest.json'
    tmp=out.with_suffix('.tmp')
    tmp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2));tmp.replace(out)
    print('Missing images:',[q['key'] for q in questions if not q['official']],flush=True)
    print('Text mismatches:',mismatches,flush=True)

if __name__=='__main__':main()
