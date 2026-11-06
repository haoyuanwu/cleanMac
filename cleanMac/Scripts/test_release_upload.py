#!/usr/bin/env python3
"""离线验证上传流程，不调用 GitHub 或修改 Release。"""
import copy
import hashlib
import pathlib
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True
from unittest.mock import patch
import upload_local_release as uploader


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = pathlib.Path(self.temp.name) / 'cleanMac-arm64.dmg'
        self.package.write_bytes(b'fixture')
        self.notes = pathlib.Path(self.temp.name) / 'notes.md'
        self.notes.write_text('1. 测试更新。\n')
        self.info = dict(tag_name='v9.9.9', body=self.notes.read_text(), draft=True, html_url='https://example.test/release', assets=[dict(name=self.package.name, state='uploaded', size=7, digest='sha256:' + hashlib.sha256(b'fixture').hexdigest(), browser_download_url='https://example.test/package')])

    def testCreatesDraftUploadsVerifiesThenPublishes(self):
        public = copy.deepcopy(self.info)
        public['draft'] = False
        with patch.object(uploader, 'release', side_effect=[None, self.info, self.info, public]), patch.object(uploader, 'gh') as gh:
            uploader.upload('owner/repo', 'v9.9.9', self.notes, self.package)
        self.assertEqual([call.args[:2] for call in gh.call_args_list], [('release', 'create'), ('release', 'upload'), ('release', 'edit')])
        self.assertIn('--draft', gh.call_args_list[0].args)

    def testPublishedMatchingReleaseIsNeverOverwritten(self):
        self.info['draft'] = False
        with patch.object(uploader, 'release', return_value=self.info), patch.object(uploader, 'gh') as gh:
            uploader.upload('owner/repo', 'v9.9.9', self.notes, self.package)
        gh.assert_not_called()

    def testWrongDigestPreventsPublication(self):
        self.info['assets'][0]['digest'] = 'sha256:wrong'
        with patch.object(uploader, 'release', return_value=self.info), patch.object(uploader, 'gh') as gh:
            with self.assertRaises(RuntimeError):
                uploader.upload('owner/repo', 'v9.9.9', self.notes, self.package)
        self.assertEqual([call.args[:2] for call in gh.call_args_list], [('release', 'upload')])

    def testDifferentNotesPreventUpload(self):
        self.info['body'] = 'different notes'
        with patch.object(uploader, 'release', return_value=self.info), patch.object(uploader, 'gh') as gh:
            with self.assertRaises(RuntimeError):
                uploader.upload('owner/repo', 'v9.9.9', self.notes, self.package)
        gh.assert_not_called()

    def testOnly404MayCreateDraft(self):
        import subprocess
        for status in ['HTTP 401', 'HTTP 403', 'connection failed']:
            with patch.object(uploader.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', status)):
                with self.assertRaises(RuntimeError):
                    uploader.release('owner/repo', 'v9.9.9')
        with patch.object(uploader.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'HTTP 404')):
            self.assertIsNone(uploader.release('owner/repo', 'v9.9.9'))


if __name__ == '__main__':
    unittest.main()
