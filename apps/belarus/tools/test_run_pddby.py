import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from run_pddby import run_pipeline


class PipelineTest(unittest.TestCase):
    def test_failure_does_not_mark_stale_report_as_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / 'review-report.json').write_text('{}')
            calls = []

            def fail(command, **kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, 1)

            self.assertEqual(run_pipeline(folder, 1, run=fail), 1)
            status = json.loads((folder / 'pipeline-status.json').read_text())
            self.assertEqual(status['state'], 'failed')
            self.assertEqual(status['stage'], 'collect')
            self.assertEqual(len(calls), 1)

    def test_success_preserves_unverified_completeness(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)

            def succeed(command, **kwargs):
                if Path(command[1]).name == 'review_pddby.py':
                    (folder / 'review-report.json').write_text(json.dumps({
                        'answerEvidenceVerified': True, 'missingImages': [],
                        'questions': 2, 'uniqueImageUrls': 1,
                    }))
                return subprocess.CompletedProcess(command, 0)

            self.assertEqual(run_pipeline(folder, 1, run=succeed), 0)
            status = json.loads((folder / 'pipeline-status.json').read_text())
            self.assertEqual(status['questions'], 2)
            self.assertEqual(status['state'], 'sampling-and-review-finished')
            self.assertEqual(status['completeness'], 'unverified-random-public-trainer-sample')


if __name__ == '__main__':
    unittest.main()
