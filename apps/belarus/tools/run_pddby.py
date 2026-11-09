#!/usr/bin/env python3
"""Run the local, resumable source collection, media download and evidence review.

Completion means the configured sampling run and checks finished, not that the
publisher's entire bank or the official GAI bank has been obtained.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

from collect_pddby import atomic_json


def run_pipeline(folder, rounds, *, run=subprocess.run):
    tools = Path(__file__).resolve().parent
    status = {
        'pid': os.getpid(),
        'startedAt': datetime.now(timezone.utc).isoformat(),
        'completeness': 'unverified-random-public-trainer-sample',
        'state': 'running',
    }

    def save():
        status['updatedAt'] = datetime.now(timezone.utc).isoformat()
        atomic_json(folder / 'pipeline-status.json', status)

    stages = [
        ('collect', 'collect_pddby.py', ['--output', str(folder), '--rounds', str(rounds)]),
        ('images', 'download_pddby_images.py', [str(folder)]),
        ('review', 'review_pddby.py', [str(folder), '--require-images']),
    ]
    try:
        for name, script, args in stages:
            status['stage'] = name
            save()
            with (folder / f'pipeline-{name}.log').open('a') as log:
                log.write(f'\nRun started {status["updatedAt"]}\n')
                log.flush()
                result = run([sys.executable, str(tools / script), *args],
                             stdout=log, stderr=subprocess.STDOUT, check=False)
            if result.returncode:
                status.update(state='failed', exitCode=result.returncode)
                save()
                return result.returncode
        report = json.loads((folder / 'review-report.json').read_text())
        if not report['answerEvidenceVerified'] or report['missingImages']:
            raise ValueError('Source evidence or image verification incomplete')
        status.update(state='sampling-and-review-finished', questions=report['questions'],
                      imageUrls=report['uniqueImageUrls'], exitCode=0)
        save()
        return 0
    except KeyboardInterrupt:
        status.update(state='interrupted', exitCode=130)
        save()
        raise
    except Exception as error:
        status.update(state='failed', error=str(error), exitCode=1)
        save()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--rounds', type=int, default=1000)
    args = parser.parse_args()
    folder = args.source.resolve()
    if args.rounds < 1 or not any(p in ('scratch', 'output') for p in folder.parts):
        parser.error('Use positive rounds and an ignored scratch/ or output/ folder')
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / '.pipeline.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error('A pipeline already owns this output directory')
        raise SystemExit(run_pipeline(folder, args.rounds))


if __name__ == '__main__':
    main()
