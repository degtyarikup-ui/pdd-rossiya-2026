#!/usr/bin/env python3
"""Collect the publisher's public practice questions, with local provenance.

Requires permission from the publisher (reported by the project owner).
Only uses the public trainer's observed start/select/set/exit operations.
Does not claim random sampling proves the complete official examination bank.
Output must stay outside source control; no cookies or source content are committed.
"""
import argparse
import hashlib
import fcntl
import html
from html.parser import HTMLParser
import http.cookiejar
import json
from pathlib import Path
import re
import time
from datetime import datetime, timezone
from urllib.parse import urlencode, urljoin, urlparse
from urllib.error import URLError
from urllib.request import build_opener, HTTPCookieProcessor, Request

BASE = 'https://pdd.by'


def normalize(value):
    return ' '.join(value.split())


class TicketParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.question = []
        self.answers = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        parent = self.stack[-1][1] if self.stack else None
        mode = parent
        if 'b-question' in a.get('class', '').split():
            mode = 'question'
        if a.get('id') == 'variants':
            mode = 'variants'
        if tag == 'span' and parent == 'variants':
            self.answers.append([])
            mode = 'answer'
        if tag == 'br':
            self.handle_data(' ')
        if a.get('id') == 'q-img':
            mode = 'image'
        if mode in ('question', 'image', 'answer'):
            candidates = ([a['src']] if tag == 'img' and a.get('src') else [])
            candidates += re.findall(r'url\([\'\"]?([^\'\")]+)', a.get('style', ''))
            if mode == 'answer' and candidates:
                raise ValueError('Answer-specific images require a reviewed layout mapping')
            for source in candidates:
                url = urljoin(BASE, html.unescape(source))
                if urlparse(url).hostname != 'pdd.by':
                    raise ValueError('Unexpected image host')
                if url not in self.images:
                    self.images.append(url)
        if tag not in {'img', 'br', 'hr', 'input', 'meta', 'link', 'wbr', 'source'}:
            self.stack.append((tag, mode))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        mode = self.stack[-1][1] if self.stack else None
        if mode == 'question':
            self.question.append(data)
        if mode == 'answer':
            self.answers[-1].append(data)


def parse_ticket(payload):
    p = TicketParser()
    p.feed(payload['ticket'])
    question = normalize(''.join(p.question))
    answers = [normalize(''.join(parts)) for parts in p.answers]
    if not question or not 2 <= len(answers) <= 5 or any(not a for a in answers):
        raise ValueError('Unexpected question/answer markup; raw response retained')
    if len(set(answers)) != len(answers):
        raise ValueError('Duplicate answer text')
    key_data = [question, answers, p.images]
    key = hashlib.sha256(json.dumps(key_data, ensure_ascii=False).encode()).hexdigest()
    return {'id': 'by:pddby:' + key[:24], 'text': question,
            'answers': answers, 'imageUrls': p.images}


def correct_index(reply, submitted, answer_count):
    if 'error' in reply or int(reply.get('an', 0)) != submitted:
        raise ValueError('Answer was not acknowledged')
    answer = int(reply['answ'])
    if not 1 <= answer <= answer_count or reply['result'] != (answer == submitted):
        raise ValueError('Inconsistent answer from publisher')
    return answer - 1


def atomic_json(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    tmp.replace(path)


class Collector:
    def __init__(self, output, delay):
        self.output = output
        self.raw = output / 'raw'
        self.raw.mkdir(parents=True, exist_ok=True)
        self.opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.delay = delay
        self.last_request = 0
        self.last_ticket_end = 0
        self.sequence = len(list(self.raw.glob('*.json')))
        bank_path = output / 'collected.json'
        self.bank = json.loads(bank_path.read_text()) if bank_path.exists() else {
            'source': BASE + '/tasks/online/',
            'permission': 'Owner reports publisher permission to scrape the website; 2026-11-09',
            'completeness': 'unverified-random-public-trainer-sample',
            'questions': {}, 'ticketsByTopic': {}, 'history': []}

    def fetch(self, path, params=None):
        url = BASE + path + ('?' + urlencode(params) if params else '')
        time.sleep(max(0, self.delay - (time.monotonic() - self.last_request)))
        self.last_request = time.monotonic()
        # Retry only TLS handshakes: no HTTP operation reached the server yet.
        # Ambiguous read timeouts/session errors fail with the checkpoint intact.
        for attempt in range(3):
            try:
                with self.opener.open(Request(url, headers={'User-Agent': 'PDD-Belarus-content-review/1.0'}), timeout=25) as r:
                    data = r.read(4 * 1024 * 1024)
                break
            except URLError as error:
                if 'handshake operation timed out' not in str(error) or attempt == 2:
                    raise
                print(json.dumps({'networkRetry': attempt + 1, 'reason': 'TLS handshake timeout'}), flush=True)
                time.sleep(10 * (attempt + 1))
        if params is None:
            (self.output / 'source-page.html').write_bytes(data)
            return None
        self.sequence += 1
        raw_path = self.raw / f'{self.sequence:07d}.json'
        raw_path.write_bytes(data)
        reply = json.loads(data)
        if reply.get('error'):
            raise ValueError(f'Publisher returned an error; see {raw_path.name}')
        return reply, str(raw_path.relative_to(self.output))

    def api(self, method, **params):
        return self.fetch('/tasks/o/', {'meth': method, **params})

    def save(self):
        self.bank['checkedAt'] = datetime.now(timezone.utc).isoformat()
        atomic_json(self.output / 'collected.json', self.bank)

    def ticket(self, topic):
        # The publisher requires ten seconds between attempts.
        time.sleep(max(0, 11 - (time.monotonic() - self.last_ticket_end)))
        self.fetch('/tasks/online/')
        payload, raw_question = self.api('start', extype=topic)
        mistakes = 0
        answered = 0
        before = len(self.bank['questions'])
        for number in range(1, 11):
            if number != 1:
                payload, raw_question = self.api('select', n=number)
            if int(payload['current']) != number - 1:
                raise ValueError('Unexpected question position')
            question = parse_ticket(payload)
            known = self.bank['questions'].get(question['id'])
            submitted = known['correctIndex'] + 1 if known else 1
            reply, raw_answer = self.api('set', n=submitted)
            question['correctIndex'] = correct_index(reply, submitted, len(question['answers']))
            mistakes += not reply['result']
            answered += 1
            question['hintHtml'] = reply.get('hint') or payload.get('hint') or ''
            question['subject'] = 'other' if topic == 7 else 'pdd'
            question['topics'] = [topic]
            question['evidence'] = {'question': raw_question, 'answer': raw_answer}
            previous = self.bank['questions'].get(question['id'])
            if previous:
                for key in ['text', 'answers', 'imageUrls', 'correctIndex', 'subject']:
                    if previous[key] != question[key]:
                        raise ValueError(f'Conflicting source question: {question["id"]} ({key})')
                previous['topics'] = sorted(set(previous['topics'] + [topic]))
                previous['observations'] += 1
            else:
                question['observations'] = 1
                self.bank['questions'][question['id']] = question
            self.save()
            # The public trainer terminates an attempt after the second error.
            # Follow that behaviour; do not request questions from an ended ticket.
            if mistakes >= 2:
                break
        self.api('exit')
        self.last_ticket_end = time.monotonic()
        key = str(topic)
        self.bank['ticketsByTopic'][key] = self.bank['ticketsByTopic'].get(key, 0) + 1
        added = len(self.bank['questions']) - before
        self.bank['history'].append({'topic': topic, 'new': added, 'answered': answered})
        self.save()
        print(json.dumps({'topic': topic, 'new': added, 'unique': len(self.bank['questions']),
                          'tickets': self.bank['ticketsByTopic']}, ensure_ascii=False), flush=True)
        return added


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=1)
    parser.add_argument('--stale-tickets', type=int, default=12, help='Pause a topic after this many consecutive tickets with no new question; not proof of completeness')
    parser.add_argument('--delay', type=float, default=0.35)
    args = parser.parse_args()
    if args.rounds < 1 or args.delay < 0.2 or args.stale_tickets < 1:
        parser.error('Use at least one round and a delay of at least 0.2 seconds')
    if not any(part in ('scratch', 'output') for part in args.output.resolve().parts):
        parser.error('Store source material in ignored scratch/ or output/, outside app assets')
    args.output.mkdir(parents=True, exist_ok=True)
    lock = (args.output / '.collector.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error('A collector already owns this output directory')
    collector = Collector(args.output, args.delay)
    collector.fetch('/tasks/online/')
    for _ in range(args.rounds):
        active = 0
        for topic in sorted(range(1, 8), key=lambda t: collector.bank['ticketsByTopic'].get(str(t), 0)):
            history = [h for h in collector.bank['history'] if h['topic'] == topic]
            if len(history) >= args.stale_tickets and all(h['new'] == 0 for h in history[-args.stale_tickets:]):
                continue
            collector.ticket(topic)
            active += 1
        if not active:
            print('Sampling plateau reached in all topics; completeness remains unverified.', flush=True)
            break


if __name__ == '__main__':
    main()
