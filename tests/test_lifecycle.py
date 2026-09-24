"""Run with python3 -m unittest discover -s tests -v; no VM is modified."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
    'system status') exit "${SERVICE_DOWN:-0}" ;;
    'system start') ;;
    'system dns ls -q') printf '%s\n' "$DEVVM_DNS_DOMAIN" ;;
    'machine ls -q')
        [ "${LIST_FAIL:-0}" = 0 ] || exit 1
        [ "${EXISTS:-0}" = 0 ] || printf '%s\n' "$DEVVM_NAME"
        ;;
    machine\ inspect\ *) printf '{"homeMount":"%s"}\n' "${MOUNT:-none}" ;;
    build\ *)
        cp "$REPO/.authorized_keys" "$CAPTURE"
        exit "${BUILD_FAIL:-0}"
        ;;
    machine\ create\ *) test ! -e "$REPO/.authorized_keys" ;;
    *'/usr/sbin/sshd -T')
        [ "${SSHD_FAIL:-0}" = 0 ] || exit 1
        printf '%s\n' \
            'pubkeyauthentication yes' 'authenticationmethods publickey' \
            "passwordauthentication ${PASSWORD:-no}" \
            'kbdinteractiveauthentication no' 'permitemptypasswords no' \
            'permitrootlogin no' 'usedns no' 'gssapiauthentication no'
        ;;
    *'systemctl is-active --quiet ssh') exit "${SSH_DOWN:-0}" ;;
    machine\ run\ *|machine\ stop\ *|machine\ rm\ *) ;;
    *) exit 99 ;;
esac
'''


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        shutil.copytree(ROOT / 'scripts', self.repo / 'scripts')
        (self.repo / 'pubkeys').mkdir()
        (self.repo / 'pubkeys/.gitkeep').touch()
        self.home = self.base / 'home'
        (self.home / '.ssh').mkdir(parents=True)
        (self.home / '.ssh/config').write_text('# unchanged\n')
        (self.home / '.ssh/id_ed25519').write_text('PRIVATE HOST KEY')
        (self.repo / 'pubkeys/private').write_text('PRIVATE REPO KEY')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        mock = self.bin / 'container'
        mock.write_text(MOCK)
        mock.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        HOME=str(self.home), REPO=str(self.repo),
                        CALLS=str(self.base / 'calls'), CAPTURE=str(self.base / 'keys'),
                        DEVVM_NAME='testvm', DEVVM_DNS_DOMAIN='localvm',
                        DEVVM_SSH_USER='tester')

    def run_script(self, name, ok=True, answer='', **env):
        result = subprocess.run([str(self.repo / 'scripts' / name)],
                                env=dict(self.env, **env), input=answer,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        self.assertEqual((self.home / '.ssh/config').read_text(), '# unchanged\n')
        self.assertFalse((self.repo / '.authorized_keys').exists())
        return result

    def calls(self):
        return (self.base / 'calls').read_text()

    def connection(self, result):
        self.assertIn('ssh tester@testvm.localvm', result.stdout)
        self.assertIn('Host testvm.localvm\n    HostName testvm.localvm\n    User tester', result.stdout)
        self.assertNotIn('IdentityFile', result.stdout)

    def key(self, source, content='ssh-ed25519 AAAA test\n'):
        path = self.home / '.ssh/id_test.pub' if source == 'host' else self.repo / 'pubkeys/test.pub'
        path.write_text(content)

    def test_key_sources(self):
        for sources in [('host',), ('repo',), ('host', 'repo')]:
            with self.subTest(sources=sources):
                for path in [self.home / '.ssh/id_test.pub', self.repo / 'pubkeys/test.pub']:
                    if path.exists():
                        path.unlink()
                for source in sources:
                    self.key(source, '\nssh-ed25519 AAAA test\nssh-ed25519 AAAA test')
                self.connection(self.run_script('init'))
                self.assertEqual((self.base / 'keys').read_text(), 'ssh-ed25519 AAAA test\n')
                self.assertIn('machine create --name testvm', self.calls())
                self.assertIn('--home-mount none', self.calls())

    def test_no_keys(self):
        self.run_script('init', ok=False)
        self.assertNotIn('build ', self.calls())

    def test_empty_keys(self):
        self.key('repo', '\n  \n')
        self.run_script('init', ok=False)
        self.assertNotIn('build ', self.calls())

    def test_existing_init(self):
        result = self.run_script('init', ok=False, EXISTS='1')
        self.assertIn('./scripts/up', result.stderr)
        self.assertNotIn('build ', self.calls())
        self.assertNotIn('machine create', self.calls())
        self.assertNotIn('machine run', self.calls())

    def test_missing_up(self):
        result = self.run_script('up', ok=False)
        self.assertIn('./scripts/init', result.stderr)
        self.assertNotIn('build ', self.calls())
        self.assertNotIn('machine create', self.calls())

    def test_existing_up(self):
        self.connection(self.run_script('up', EXISTS='1', SERVICE_DOWN='1'))
        self.assertIn('system start', self.calls())
        self.assertNotIn('build ', self.calls())
        self.assertNotIn('machine create', self.calls())

    def test_unsafe_mount(self):
        self.run_script('up', ok=False, EXISTS='1', MOUNT='shared')
        self.assertNotIn('machine run', self.calls())

    def test_build_failure(self):
        self.key('host')
        self.run_script('init', ok=False, BUILD_FAIL='1')
        self.assertNotIn('machine create', self.calls())

    def test_ssh_failures(self):
        for env in [{'PASSWORD': 'yes'}, {'SSH_DOWN': '1'}, {'SSHD_FAIL': '1'}]:
            with self.subTest(env=env):
                result = self.run_script('up', ok=False, EXISTS='1', **env)
                self.assertNotIn('Ready.', result.stdout)

    def test_list_failure(self):
        self.run_script('init', ok=False, LIST_FAIL='1')
        self.assertNotIn('build ', self.calls())
        self.assertNotIn('machine create', self.calls())

    def test_destroy_confirmation(self):
        self.run_script('destroy', EXISTS='1', answer='n\n')
        self.assertNotIn('machine rm', self.calls())
        self.run_script('destroy', EXISTS='1', answer='yes\n')
        self.assertIn('machine rm testvm', self.calls())


if __name__ == '__main__':
    unittest.main()
