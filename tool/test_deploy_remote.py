"""Exercise immutable deployment with real Git and isolated command doubles."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class RemoteDeployTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "server's checkout with spaces"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Deployment test")
        shutil.copytree(SOURCE / "deploy", self.repo / "deploy")
        (self.repo / ".gitignore").write_text(".env\nbackups/\n.farash-releases/\n")
        self.git("add", ".")
        self.git("commit", "-m", "validated release")
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.origin = self.root / "origin.git"
        subprocess.run(["git", "clone", "--bare", str(self.repo), str(self.origin)],
                       check=True, capture_output=True)
        self.git("remote", "add", "origin", str(self.origin))
        self.config = self.repo / "deploy" / ".env"
        self.config.write_text("FARASH_DOMAIN=test.invalid\nCOMPOSE_PROJECT_NAME=existing-project\n")
        self.dirty = self.repo / "deploy" / "deploy.sh"
        self.dirty.write_text("server customization: must not run or disappear\n")
        (self.repo / "deploy" / "local-note").write_text("keep untracked data")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]
record={'command':pathlib.Path(sys.argv[0]).name,'args':args,
        'tag':os.environ.get('FARASH_IMAGE_TAG'),
        'caddy':os.environ.get('FARASH_CADDYFILE')}
with open(os.environ['DEPLOY_TEST_LOG'],'a') as f:f.write(json.dumps(record)+'\\n')
if 'pg_dump' in args:
    if os.environ.get('FAIL_BACKUP')=='1':sys.exit(7)
    sys.stdout.write('PGDMP isolated fixture')
'''
        for name in ["docker", "curl"]:
            path = self.bin / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                    "DEPLOY_TEST_LOG": str(self.log)}
        for key in ["FARASH_BACKUP_DIR", "FARASH_DEPLOY_CONFIG_DIR", "COMPOSE_FILE",
                    "COMPOSE_PROJECT_NAME", "FARASH_CADDYFILE"]:
            self.env.pop(key, None)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args],
                                       text=True, stderr=subprocess.DEVNULL)

    def deploy(self, sha=None, **env):
        return subprocess.run(["bash", str(SOURCE / "tool/deploy_remote.sh"),
                               str(self.repo), sha or self.sha], env={**self.env, **env},
                              text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_dirty_checkout_preserved_and_all_compose_calls_share_config(self):
        before = self.git("status", "--porcelain")
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("status", "--porcelain"), before)
        self.assertIn("server customization", self.dirty.read_text())
        self.assertEqual((self.repo / "deploy/local-note").read_text(), "keep untracked data")
        calls = self.commands()
        compose = [c for c in calls if c["args"][:1] == ["compose"]]
        self.assertEqual(len(compose), 5)
        prefix = ["compose", "--project-directory", str(self.repo / "deploy"),
                  "--env-file", str(self.config)]
        for call in compose:
            self.assertEqual(call["args"][:5], prefix)
            self.assertEqual(call["tag"], self.sha)
            self.assertIn("/.farash-releases/", call["args"][6])
            self.assertTrue(Path(call["caddy"]).is_file())
        backup = list((self.repo / "deploy/backups").glob("*.dump"))
        self.assertEqual(len(backup), 1)
        self.assertEqual(backup[0].stat().st_mode & 0o777, 0o600)
        self.assertTrue(backup[0].with_suffix(".dump.sha256").exists())
        self.assertEqual(calls[-1]["args"], ["-fsS", "https://test.invalid/api/v1/health"])

    def test_backup_failure_prevents_api_restart_and_health_probe(self):
        result = self.deploy(FAIL_BACKUP="1")
        self.assertNotEqual(result.returncode, 0)
        calls = self.commands()
        up = [c for c in calls if "up" in c["args"]]
        self.assertEqual(len(up), 1)
        self.assertEqual(up[0]["args"][-1], "postgres")
        self.assertFalse(any(c["command"] == "curl" for c in calls))
        self.assertFalse(list((self.repo / "deploy/backups").glob(".pending.*")))

    def test_selected_commit_is_exported_instead_of_current_head(self):
        old = (self.repo / "deploy/Caddyfile").read_text()
        (self.repo / "deploy/Caddyfile").write_text("newer unselected config\n")
        self.git("add", "deploy/Caddyfile")
        self.git("commit", "-m", "later source")
        self.git("push", "origin", "main")
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        release_file = Path(self.commands()[0]["caddy"])
        self.assertEqual(release_file.read_text(), old)
        self.assertNotEqual(self.git("rev-parse", "HEAD").strip(), self.sha)

    def test_missing_config_stops_before_commands(self):
        self.config.unlink()
        self.assertNotEqual(self.deploy().returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_invalid_or_unavailable_revision_stops_before_commands(self):
        for sha in ["main", "-bad", "f" * 40]:
            with self.subTest(sha=sha):
                self.assertNotEqual(self.deploy(sha).returncode, 0)
                self.assertEqual(self.commands(), [])


if __name__ == "__main__":
    unittest.main()
