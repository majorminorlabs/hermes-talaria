"""Regression checks for service secrets and safe update boundaries (no live ops)."""
import importlib.util
import os
import copy
import sqlite3
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('studio', Path(__file__).with_name('bridge-service.py'))
studio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(studio)


class StudioServiceTests(unittest.TestCase):
    def test_serve_ownership_refuses_funnel_or_unrelated_routes(self):
        expected = 'http://127.0.0.1:8787'
        config = {'TCP':{'443':{'HTTPS':True}}, 'Web':{'studio:443':{'Handlers':{'/':{'Proxy':expected}}}}}
        self.assertTrue(studio.owns_serve(config, expected))
        variants = []
        funnel = copy.deepcopy(config); funnel['AllowFunnel'] = {'studio:443':True}; variants.append(funnel)
        other = copy.deepcopy(config); other['Web']['studio:443']['Handlers']['/extra'] = {'Proxy':expected}; variants.append(other)
        port = copy.deepcopy(config); port['TCP']['22'] = {'TCPForward':'127.0.0.1:22'}; variants.append(port)
        different = copy.deepcopy(config); different['Web']['studio:443']['Handlers']['/']['Proxy'] = 'http://127.0.0.1:9999'; variants.append(different)
        for config in variants: self.assertFalse(studio.owns_serve(config, expected))

    def test_private_config_rejects_symlink_and_world_readable_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root/'secret'
            studio.private_write(secret, '{"credential":"private"}')
            self.assertEqual(secret.stat().st_mode & 0o777, 0o600)
            link = root/'link'; link.symlink_to(secret)
            with self.assertRaises(ValueError): studio.read_json(link)
            with self.assertRaises(ValueError): studio.private_write(link, '{}')
            secret.chmod(0o644)
            with self.assertRaises(ValueError): studio.read_json(secret)

    def test_failed_write_keeps_existing_secret_and_refuses_stale_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'config'
            studio.private_write(path, 'original')
            path.with_name('config.new').write_text('stale')
            with self.assertRaises(FileExistsError): studio.private_write(path, 'replacement')
            self.assertEqual(path.read_text(), 'original')

    def test_private_directory_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); link = root/'link'; link.symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError): studio.private_dir(link)

    def test_update_refuses_every_active_and_unknown_state(self):
        for state in ('starting','running','waiting_for_input','stop_requested','unknown'):
            with self.subTest(state=state), patch.object(studio,'request',side_effect=lambda root,path: {'runs':[{'state':state}]} if 'state='+state+'&' in path else {'runs':[]}):
                with self.assertRaises(ValueError): studio.ensure_idle(Path('/unused'))

    def test_update_queries_state_instead_of_only_recent_run_page(self):
        paths = []
        def read(root, path):
            paths.append(path)
            return {'runs':[]}
        with patch.object(studio,'request',side_effect=read): studio.ensure_idle(Path('/unused'))
        self.assertEqual(len(paths),5)
        self.assertTrue(all('state=' in p and 'limit=1' in p for p in paths))

    def test_pending_bot_or_upload_mutation_prevents_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); state = root/'state'; state.mkdir()
            studio.private_write(root/'config.json', json.dumps({'state_dir':str(state)}))
            with sqlite3.connect(state/'bridge.sqlite3') as db:
                db.execute('CREATE TABLE commands(status TEXT)'); db.execute("INSERT INTO commands VALUES ('pending')")
            with patch.object(studio,'request',return_value={'runs':[]}):
                with self.assertRaises(ValueError): studio.ensure_idle(root)
            with sqlite3.connect(state/'bridge.sqlite3') as db: db.execute("UPDATE commands SET status='done'")
            with patch.object(studio,'request',return_value={'runs':[]}): studio.ensure_idle(root)

    def test_new_run_during_staging_prevents_shutdown(self):
        with patch.object(studio,'load_manifest',return_value={'python':'python3'}), patch.object(studio,'ensure_idle',side_effect=[None,ValueError('new run')]), patch.object(studio,'stage_release'), patch.object(studio,'stop') as stop:
            with self.assertRaises(ValueError): studio.update(Path('/unused'))
            stop.assert_not_called()

    def test_failed_start_restores_previous_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); previous=root/'old'; previous.mkdir(); (root/'current').symlink_to(previous)
            release=root/'new'; release.mkdir()
            with patch.object(studio,'load_manifest',return_value={'python':'python3'}), patch.object(studio,'ensure_idle'), patch.object(studio,'stage_release',return_value=release), patch.object(studio,'stop'), patch.object(studio,'start',side_effect=[ValueError('start failed'),None]) as start:
                with self.assertRaises(ValueError): studio.update(root)
                self.assertEqual((root/'current').resolve(),previous)
                self.assertEqual(start.call_count,2)


if __name__ == '__main__': unittest.main()
