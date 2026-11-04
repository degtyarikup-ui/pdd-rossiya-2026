"""Play must retain an uploaded bundle while its processing is pending."""
import unittest
from unittest.mock import Mock, patch

from tools.store_release.publish import HttpError, Play


class PlayCommitTests(unittest.TestCase):
    def client(self, responses):
        client = object.__new__(Play)
        client.call = Mock(side_effect=responses)
        return client

    @patch('tools.store_release.publish.time.sleep')
    def test_pending_processing_retries_the_same_edit(self, sleep):
        error = HttpError(400, 'Some of the Android App Bundle uploads are not completed yet.')
        client = self.client([error, {'id': 'accepted'}])
        self.assertEqual(client.commit_edit('uploaded-edit'), {'id': 'accepted'})
        self.assertEqual(client.call.call_args_list, [
            unittest.mock.call('POST', '/edits/uploaded-edit:commit'),
            unittest.mock.call('POST', '/edits/uploaded-edit:commit'),
        ])
        sleep.assert_called_once_with(20)

    @patch('tools.store_release.publish.time.sleep')
    def test_other_validation_errors_are_not_retried(self, sleep):
        error = HttpError(400, 'Invalid release notes')
        client = self.client([error])
        with self.assertRaises(HttpError):
            client.commit_edit('invalid-edit')
        client.call.assert_called_once()
        sleep.assert_not_called()

    @patch('tools.store_release.publish.time.sleep')
    def test_pending_processing_has_a_bounded_wait(self, sleep):
        error = HttpError(400, 'Some of the Android App Bundle uploads are not completed yet.')
        client = self.client([error, error])
        with self.assertRaises(HttpError):
            client.commit_edit('pending-edit', attempts=2)
        self.assertEqual(client.call.call_count, 2)
        sleep.assert_called_once_with(20)


if __name__ == '__main__':
    unittest.main()
