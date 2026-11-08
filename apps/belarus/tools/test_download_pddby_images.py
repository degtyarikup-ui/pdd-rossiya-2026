import unittest
from unittest.mock import patch
from download_pddby_images import download_image


class Response:
    def __init__(self, content_type='image/jpeg', content=b'complete image bytes'):
        self.headers = {'Content-Type': content_type}
        self.content = content
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def raise_for_status(self): pass
    def iter_content(self, chunk_size): yield self.content


class Session:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.calls = 0
    def get(self, *args, **kwargs):
        self.calls += 1
        result = next(self.responses)
        if isinstance(result, Exception): raise result
        return result


class ImageTransferTest(unittest.TestCase):
    @patch('download_pddby_images.time.sleep')
    def test_timeout_retries_without_saving_partial_bytes(self, sleep):
        session = Session([TimeoutError('connection timed out'), Response()])
        self.assertEqual(download_image('https://pdd.by/img/tickets/test.jpg', session), b'complete image bytes')
        self.assertEqual(session.calls, 2)
        sleep.assert_called_once_with(10)

    def test_html_response_is_rejected_without_retry(self):
        session = Session([Response('text/html', b'<html>unavailable</html>')])
        with self.assertRaises(ValueError):
            download_image('https://pdd.by/img/tickets/test.jpg', session)
        self.assertEqual(session.calls, 1)

    @patch('download_pddby_images.MAX_IMAGE_BYTES', 10)
    def test_size_limit_applies_to_streamed_data(self):
        session = Session([Response(content=b'x' * 11)])
        with self.assertRaises(ValueError):
            download_image('https://pdd.by/img/tickets/test.jpg', session)


if __name__ == '__main__':
    unittest.main()
