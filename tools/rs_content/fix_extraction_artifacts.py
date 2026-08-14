#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One-off cleanup of PDF-extraction artifacts in RS question content.

Fixes, in order:
1. Manual reconstruction of ~27 questions garbled by a duplicate-glyph span
   split bug (extraction duplicated 1-6 char fragments across word/span
   boundaries in a specific PDF page cluster).
2. Superscript cm3 (engine displacement) misplacement -> proper "cm3".
3. Degree-symbol ("0") misextraction -> proper degree sign, one question.
4. Corpus-wide strip of stray footnote/page-reference numbers bleeding into
   the middle of question text (missing trailing-period edge case in the
   PDF's small-font side-number filter).
5. Removal of ~16 questions whose accompanying image bounding-box extraction
   collapsed to an unusable sliver (background scenery, no sign visible) -
   these can't be recovered without the source PDF.
"""
import json
import os
import re

ROOT = '/Users/sergei/Documents/pdd'
QDIR = os.path.join(ROOT, 'assets/countries/rs/questions')
IMGDIR = os.path.join(ROOT, 'assets/countries/rs/images/questions_ab')

REMOVE_IDS = {
    'rs_sig_0117','rs_sig_0118','rs_sig_0119','rs_sig_0120','rs_sig_0121',
    'rs_sig_0204','rs_sig_0205','rs_sig_0208','rs_sig_0209','rs_sig_0210',
    'rs_sig_0211','rs_sig_0212','rs_sig_0256','rs_sig_0422',
    'rs_vozila_0264','rs_vozila_0265',
}

MANUAL_FIX = {
    'rs_sig_0206': (
        'Saobraćajni znak prikazan na slici označava:',
        ['mesto gde se završava deo puta na kojem se deca češće i u većem broju kreću',
         'završetak zone škole',
         'mesto gde se završava zona usporenog saobraćaja']),
    'rs_sig_0207': (
        'Saobraćajni znak prikazan na slici označava:',
        ['da određena saobraćajna traka nije namenjena za kretanje pojedinih vrsta vozila čiji je simbol prikazan na znaku',
         'da je određena saobraćajna traka namenjena za kretanje vrste vozila čiji je simbol prikazan na znaku',
         'da je na toj deonici puta zabranjeno kretanje vrste vozila čiji je simbol prikazan na znaku']),
    'rs_sig_0419': (
        'Znak policijskog službenika – lagano mahanje horizontalno odručenom rukom gore-dole, sa dlanom otvorene šake okrenutim naniže, prikazan na slici, označava da:',
        ['vozač u čijem smeru se daje taj znak treba da ubrza kretanje vozila',
         'vozač u čijem smeru se daje taj znak treba da pomeri svoje vozilo bliže raskrsnici, odnosno ovlašćenom licu koje daje znak',
         'vozač u čijem smeru se daje taj znak treba da smanji brzinu kretanja vozila']),
    'rs_sig_0420': (
        'U situaciji prikazanoj na slici:',
        ['dužni ste da se zaustavite',
         'možete nastaviti kretanje',
         'dužni ste da kretanje nastavite smanjenom brzinom']),
    'rs_sig_0421': (
        'U situaciji prikazanoj na slici dužni ste da:',
        ['smanjite brzinu kretanja vozila',
         'ubrzate kretanje vozila',
         'pomerite svoje vozilo bliže ovlašćenom licu koje daje znak']),
    'rs_sig_0423': (
        'U situaciji prikazanoj na slici dužni ste da:',
        ['smanjite brzinu kretanja vozila',
         'uklonite vozilo sa kolovoza',
         'zaustavite vozilo']),
    'rs_sig_0424': (
        'U situaciji prikazanoj na slici dužni ste da:',
        ['smanjite brzinu kretanja vozila',
         'ubrzate kretanje vozila',
         'pomerite svoje vozilo bliže raskrsnici, odnosno ovlašćenom licu koje daje znak']),

    'rs_vozila_0116': (
        'Oznaka prikazana na slici služi za označavanje:',
        ['teških vozila', 'dugih vozila', 'sporih vozila']),
    'rs_vozila_0117': (
        'Oznaka prikazana na slici služi za označavanje:',
        ['teških vozila', 'dugih vozila', 'sporih vozila']),
    'rs_vozila_0118': (
        'Tabla za označavanje sporih vozila postavlja se, vrhom zasečenog trougla okrenutim na gore i osnovicom paralelnom sa površinom kolovoza, na:',
        ['polovini širine zadnje strane sporog vozila',
         'levom delu zadnje strane sporog vozila',
         'na prednjoj ili zadnjoj strani sporog vozila']),
    'rs_vozila_0119': (
        'Zaprečna tabla se postavlja na:',
        ['traktore koji vuku ili nose priključak za izvođenje radova čija širina prelazi 2,5 m',
         'duga vozila', 'teška vozila']),
    'rs_vozila_0120': (
        'Na motornom vozilu na četiri ili više točkova, motornom vozilu na tri točka koja su šira od 1,3 m i priključnom vozilu, na zadnjoj strani vozila:',
        ['mora biti ugrađeno najmanje jedno stop svetlo, tako da daje svetlost crvene ili žute boje',
         'moraju biti ugrađena najmanje dva stop svetla, tako da daju svetlost žute boje',
         'moraju biti ugrađena najmanje dva stop svetla, tako da daju svetlost crvene boje']),
    'rs_vozila_0121': (
        'Na mopedu, odnosno motociklu, na zadnjoj strani vozila:',
        ['mora biti ugrađeno najmanje jedno stop svetlo, tako da daje svetlost crvene boje',
         'mora biti ugrađeno najmanje jedno stop svetlo, tako da daje svetlost žute boje',
         'moraju biti ugrađena najmanje dva stop svetla, tako da daju svetlost crvene boje']),
    'rs_vozila_0122': (
        'Putnička vozila koja su prvi put registrovana u Republici Srbiji nakon 1. marta 2011. godine moraju imati:',
        ['najmanje četiri stop svetala',
         'treće stop svetlo ugrađeno simetrično u odnosu na srednju uzdužnu ravan vozila',
         'stop svetla u obliku kruga, čiji je poluprečnik najmanje 0,15 m']),
    'rs_vozila_0123': (
        'Stop svetla se uključuju pri aktiviranju:',
        ['radnog kočenja vozila', 'parkirnog kočenja', 'dugotrajnog usporavanja vozila']),
    'rs_vozila_0124': (
        'Stop svetlo ne moraju imati motorna vozila koja na ravnom putu ne mogu razviti brzinu kretanja veću od:',
        ['25 km/h', '30 km/h', '45 km/h']),
    'rs_vozila_0260': (
        'Teret na vozilu mora da bude tako smešten i obezbeđen da:',
        ['ne zaklanja svetla, registarske tablice i druge propisane oznake na vozilu',
         'ne zaklanja samo svetla', 'ne zaklanja samo registarsku tablicu']),
    'rs_vozila_0261': (
        'Da li teret na vozilu može da bude smešten i obezbeđen tako da zagađuje životnu sredinu?',
        ['Da', 'Ne']),
    'rs_vozila_0262': (
        'Teret na vozilu, u rasutom stanju, mora da bude prekriven:',
        ['uvek kada se vozilo kreće po putu',
         'samo kada se vozilo kreće po putu u naselju',
         'samo kada se vozilo kreće po putu van naselja']),
    'rs_vozila_0263': (
        'Teret u rasutom stanju, ne mora da bude prekriven kada se na putu prevozi:',
        ['priključnim vozilom za traktor',
         'teretnim vozilom, odnosno skupom vozila, koje se kreće brzinom manjom od 50 km/h',
         'bilo kojim priključnim vozilom']),
    'rs_vozila_0266': (
        'Teret na motornom vozilu može da pređe najistureniju tačku na prednjoj strani vozila najviše do:',
        ['1,5 m', '1 m', '1/6 svoje dužine']),
    'rs_vozila_0267': (
        'Teret na motornom vozilu može da pređe najistureniju tačku na prednjoj strani vozila:',
        ['najviše do 1 m', 'više od 1 m, ako to odobri upravljač puta', 'najviše do 1/6 svoje dužine']),
    'rs_vozila_0268': (
        'Teret na vozilu ne sme da pređe najistureniju tačku na zadnjoj strani vozila za više od:',
        ['1/6 svoje dužine, a najviše za 1,5 m, s tim da teret preostalim delom dužine ne mora biti oslonjen na tovarni prostor',
         '1/4 svoje dužine, a najviše za 1,5 m, s tim da teret preostalim delom dužine ne mora biti oslonjen na tovarni prostor',
         '1 m']),
    'rs_vozila_0269': (
        'Da li teret na vozilu sme da pređe najistureniju tačku na zadnjoj strani vozila za više od 1/6 svoje dužine, s tim da teret preostalim delom dužine mora biti oslonjen na tovarni prostor?',
        ['Da', 'Ne', 'Da, ako to odobri upravljač puta']),
    'rs_vozila_0270': (
        'Teret koji na teretnom ili priključnom vozilu prelazi najistureniju tačku na zadnjoj strani vozila mora biti označen:',
        ['propisanom tablom', 'crvenom tkaninom', 'sigurnosnim trouglom']),
    'rs_vozila_0271': (
        'Teret koji na putničkom vozilu prelazi najistureniju tačku na zadnjoj strani vozila mora biti označen:',
        ['propisanom tablom', 'crvenom tkaninom', 'sigurnosnim trouglom']),
    'rs_vozila_0272': (
        'U uslovima smanjene vidljivosti i teret koji na teretnom ili priključnom vozilu prelazi najistureniju tačku na zadnjoj strani vozila mora biti označen:',
        ['crvenim svetlom ili svetloodbojnom materijom crvene boje', 'crvenom tkaninom', 'propisanom tablom']),

    # Tire-code decoding questions: each stem repeats the same code
    # "180/60 R14 82T" (or "195/65 R16 89N") and asks about one part of it -
    # the generic stray-footnote stripper can't tell that footnote number
    # apart from the legitimate code digits it's colliding with, so these
    # are hand-cleaned instead.
    'rs_vozila_0166': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka 180 označava:',
        ['širinu pneumatika', 'visinu pneumatika', 'odnos visine i širine pneumatika izražen u procentima']),
    'rs_vozila_0167': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka 60 označava:',
        ['brzinsku oznaku', 'indeks nosivosti', 'odnos visine i širine pneumatika izražen u procentima']),
    'rs_vozila_0168': (
        'U oznaci pneumatika 195/65 R16 89N konstrukcija je iskazana kodom:',
        ['195/65', '89', '16', 'R', 'N']),
    'rs_vozila_0169': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka R označava:',
        ['da pneumatik može da se narezuje', 'brzinsku oznaku pneumatika', 'da je pneumatik radijalni']),
    'rs_vozila_0170': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka 14 označava:',
        ['širinu pneumatika', 'visinu pneumatika', 'prečnik naplatka']),
    'rs_vozila_0171': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka 82 označava:',
        ['oznaku nosivosti', 'brzinsku oznaku pneumatika', 'visinu pneumatika']),
    'rs_vozila_0172': (
        'U oznaci pneumatika 195/65 R16 89N indeks nosivosti je iskazana kodom:',
        ['195/65', '89', '16', 'R', 'N']),
    'rs_vozila_0173': (
        'U oznaci pneumatika 195/65 R16 89N indeks brzine je iskazan kodom:',
        ['195/65', '89', '16', 'R', 'N']),
    'rs_vozila_0174': (
        'Na oznaci pneumatika 180/60 R14 82T oznaka T označava:',
        ['da pneumatik može da se narezuje', 'brzinsku oznaku pneumatika', 'da je pneumatik radijalni']),

    # Extraction segmentation bug: the PDF's points-anchor detector only
    # recognizes bold digits 1-3 (see extract_questions.py POINTS_RE), so a
    # points=4 question's anchor was never recognized and its own stem+
    # options got appended as trailing junk onto the PRECEDING question's
    # last answer instead of becoming its own question. Truncated back to
    # just the original (correctly-scored) question; the swallowed
    # points=4 question(s) are not recoverable without the source PDF.
    'rs_vozaci_0106': (
        'Dnevno vreme upravljanja vozača autobusa i trolejbusa, u javnom gradskom prevozu putnika, može biti najviše:',
        ['7 sati', '8 sati', '9 sati']),
    'rs_vozaci_0111': (
        'Pauzu od najmanje 45 minuta, najkasnije nakon 4 sata i 30 minuta upravljanja vozilom, mora napraviti vozač:',
        ['autobusa', 'autobusa, samo kada njegova najveća dozvoljena masa prelazi 3.500 kg',
         'autobusa, samo kada ima više od 17 sedišta uključujući i sedište za vozača']),
    'rs_vozaci_0112': (
        'Vozač teretnog vozila ili skupa vozila čija najveća dozvoljena masa prelazi 3.500 kg ili autobusa, kojim se obavlja međunarodni drumski prevoz, umesto pauze od najmanje 45 minuta, može napraviti dve pauze raspoređene tokom vožnje tako da vreme upravljanja ne sme biti duže od 4 sata i 30 minuta i da:',
        ['prva pauza traje najmanje 20 minuta, a druga najmanje 25 minuta',
         'prva pauza traje najmanje 15 minuta, a druga najmanje 30 minuta',
         'ukupno trajanje pauza iznosi najmanje 45 minuta']),
    'rs_vozila_0209': (
        'Priključno vozilo mora biti opterećeno tako da ukupno osovinsko opterećenje tri osovine, koje imaju međusobno rastojanje do 1,3 m, ne prelazi:',
        ['18 t', '21 t', '24 t']),
}

# id -> (question override or None, [answer overrides or None])
CM3_FIX_IDS = {
    'rs_vozaci_0052', 'rs_vozila_0136', 'rs_vozila_0153', 'rs_vozila_0154',
    'rs_osnove_0046', 'rs_osnove_0047', 'rs_osnove_0049', 'rs_osnove_0050',
    'rs_osnove_0053', 'rs_osnove_0059', 'rs_osnove_0060',
}

def fix_cm3(text):
    if ' cm' not in text and 'cm' not in text.split():
        pass
    # Remove a stray standalone "3" token (the misplaced cm^3 exponent) and
    # append it as "cm3" right after the nearest "cm" measurement.
    if not re.search(r'\bcm\b', text):
        return text
    if not re.search(r'(?<!\w)3(?!\w)', text):
        return text
    new = re.sub(r'\s*(?<!\w)3(?!\w)\s+', ' ', text, count=1)
    new = re.sub(r'\bcm\b(?!\d|³)', 'cm³', new, count=1)
    new = re.sub(r'\s{2,}', ' ', new).strip()
    new = re.sub(r'\s+([,.:;?])', r'\1', new)
    return new

STRAY_NUM_UNIT_FOLLOW = {
    'km/h','km','kg','m','mm','cm','cm³','t','dana','dan','meseci','mesec','meseca',
    'godina','godine','godini', 'sati','sata','sat','minuta','minut','minuti',
    'dinara','din','poena','poen','sedišta','mesta','mesto','kw','kw/kg', 'kw,',
    'kaznenih','kaznena','kaznenog','%','sekundi','sekunda','metara','metar',
    'časa','časova','čas',
}
# Legit both immediately BEFORE and AFTER a real (non-stray) number. Kept
# deliberately narrow/domain-specific - generic connectors (i/a/u/na/...)
# are too common to safely whitelist; they would also mask real stray
# footnote numbers that happen to sit next to them.
STRAY_NUM_CONTEXT_OK = {
    'od','do','za','najviše','najmanje','veća','veći','veće','manja','manje','manji',
    'duže','duži','duža','kraće','kraći','preko','iznad','ispod','brojem','broj','br','br.',
    'kategorije','poglavlje','član','tačka','stav','uzastopnih','perioda',
    'putanjom','putanjama','vozilom','vozila','vozilo','trakom','trakama','strani',
    'kolonom','koloni','pravcem','smeru','stepen','stepena','sistem',
}

def _is_num(tok):
    core = tok.strip(',.:;()')
    return bool(re.fullmatch(r'\d{1,4}', core)) and core == tok

def _looks_numeric(tok):
    core = tok.strip(',.:;()')
    return bool(re.fullmatch(r'\d{1,4}', core))

def strip_stray_numbers(text):
    toks = text.split(' ')
    out = []
    changed = False
    n = len(toks)
    for i, tok in enumerate(toks):
        if _is_num(tok):
            prev = toks[i-1].strip(',.:;()').lower() if i > 0 else ''
            nxt = toks[i+1].strip(',.:;()').lower() if i+1 < n else ''
            # Genuine enumeration: "N i M" / "N, M i K" - a number connected
            # to another number via i/ili one hop away (either direction).
            enum_ok = False
            if nxt in ('i', 'ili') and i + 2 < n and _looks_numeric(toks[i+2]):
                enum_ok = True
            if prev in ('i', 'ili') and i - 2 >= 0 and _looks_numeric(toks[i-2]):
                enum_ok = True
            if (prev in STRAY_NUM_UNIT_FOLLOW or nxt in STRAY_NUM_UNIT_FOLLOW
                    or prev in STRAY_NUM_CONTEXT_OK or nxt in STRAY_NUM_CONTEXT_OK
                    or enum_ok):
                out.append(tok)
                continue
            if n == 1:
                out.append(tok)
                continue
            changed = True
            continue
        out.append(tok)
    result = ' '.join(out)
    result = re.sub(r'\s{2,}', ' ', result).strip()
    return result, changed


def process_question_list(questions, stats):
    kept = []
    for q in questions:
        if q['id'] in REMOVE_IDS:
            stats['removed'].append(q['id'])
            continue
        if q['id'] in MANUAL_FIX:
            new_q, new_answers = MANUAL_FIX[q['id']]
            q['question'] = new_q
            # Some ids (segmentation-bled questions) had extra bogus answers
            # appended - truncate back to the number of real answers.
            q['answers'] = q['answers'][:len(new_answers)]
            for a, new_text in zip(q['answers'], new_answers):
                a['text'] = new_text
            assert len(q['answers']) == len(new_answers), q['id']
            stats['manual_fixed'].append(q['id'])
            kept.append(q)
            continue
        if q['id'] in CM3_FIX_IDS:
            q['question'] = fix_cm3(q['question'])
            for a in q['answers']:
                a['text'] = fix_cm3(a['text'])
            stats['cm3_fixed'].append(q['id'])
        if q['id'] == 'rs_vozila_0144':
            q['question'] = ('Kada je postavljena na mesto određeno od strane proizvođača, '
                              'ugao koji zaklapa registarska tablica i ravan upravna na horizontalnu podlogu:')
            q['answers'][0]['text'] = 'ne može prelaziti 30° prema gore niti 15° prema dole'
            q['answers'][1]['text'] = 'ne može prelaziti 15° prema gore niti 30° prema dole'
            q['answers'][2]['text'] = 'ne može prelaziti 15° prema gore niti 20° prema dole'
            stats['degree_fixed'].append(q['id'])
            kept.append(q)
            continue

        new_qtext, ch1 = strip_stray_numbers(q['question'])
        if ch1:
            q['question'] = new_qtext
            stats['stray_num_fixed'].add(q['id'])
        for a in q['answers']:
            new_atext, ch2 = strip_stray_numbers(a['text'])
            if ch2:
                a['text'] = new_atext
                stats['stray_num_fixed'].add(q['id'])
        kept.append(q)
    return kept


def main():
    stats = {'removed': [], 'manual_fixed': [], 'cm3_fixed': [], 'degree_fixed': [], 'stray_num_fixed': set()}

    qab_path = os.path.join(QDIR, 'questions_ab.json')
    qab = json.load(open(qab_path, encoding='utf-8'))
    for t in qab['tickets']:
        t['questions'] = process_question_list(t['questions'], stats)
    json.dump(qab, open(qab_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    # topics_ab.json and official_questions.json must reflect the exact same
    # per-id text/removal so all three stay consistent.
    fixed_by_id = {}
    for t in qab['tickets']:
        for q in t['questions']:
            fixed_by_id[q['id']] = q

    topics_path = os.path.join(QDIR, 'topics_ab.json')
    topics = json.load(open(topics_path, encoding='utf-8'))
    for top in topics['topics']:
        new_qs = []
        for q in top['questions']:
            if q['id'] in REMOVE_IDS:
                continue
            new_qs.append(fixed_by_id[q['id']])
        top['questions'] = new_qs
    json.dump(topics, open(topics_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    official_path = os.path.join(QDIR, 'official_questions.json')
    official = json.load(open(official_path, encoding='utf-8'))
    new_official = []
    for q in official:
        if q['id'] in REMOVE_IDS:
            continue
        new_official.append(fixed_by_id[q['id']])
    json.dump(new_official, open(official_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

    for qid in REMOVE_IDS:
        img_path = os.path.join(IMGDIR, qid + '.jpg')
        if os.path.exists(img_path):
            os.remove(img_path)

    print('removed:', len(stats['removed']))
    print('manual_fixed:', len(stats['manual_fixed']))
    print('cm3_fixed:', len(stats['cm3_fixed']))
    print('degree_fixed:', len(stats['degree_fixed']))
    print('stray_num_fixed (unique ids):', len(stats['stray_num_fixed']))
    missing_manual = set(MANUAL_FIX) - set(stats['manual_fixed'])
    if missing_manual:
        print('WARNING: manual fix ids not found in data:', missing_manual)
    missing_removed = REMOVE_IDS - set(stats['removed'])
    if missing_removed:
        print('WARNING: remove ids not found in data:', missing_removed)


if __name__ == '__main__':
    main()
