import base64
import importlib.util
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-public-data.py"
spec = importlib.util.spec_from_file_location("publication_checks", SCRIPT)
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class PublicationChecksTests(unittest.TestCase):
    def test_redacted_findings_and_public_fixtures(self):
        token = b"sk_" + b"x" * 32
        path = b"/Users/" + b"private-test/Documents/project"
        findings = checks.findings(token + b"\n" + path, "fixture")
        self.assertEqual({v["category"] for v in findings}, {"credential-format", "private-home"})
        self.assertNotIn(token.decode(), json.dumps(findings))
        self.assertFalse(checks.findings(b"00000000-0000-4000-8000-000000000001 " + checks.WEBSOCKET_GUID, "fixture"))

    def test_history_and_archive_boundaries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                subprocess.run(["git", "-C", directory, *args], check=True, capture_output=True)
            def scan(*args, secret=None):
                return subprocess.run(["python3", str(SCRIPT), "--repo", directory, "--json", *args], input=secret, capture_output=True)
            git("init", "-q")
            git("config", "user.name", "Public fixture")
            git("config", "user.email", "0+fixture@users.noreply.github.com")
            token = b"sk_" + b"z" * 32
            (root / "fixture.txt").write_bytes(token)
            git("add", "fixture.txt"); git("commit", "-qm", "fixture")
            (root / "fixture.txt").write_text("synthetic example")
            git("add", "fixture.txt"); git("commit", "-qm", "remove fixture")
            self.assertEqual(scan().returncode, 0)
            history = scan("--history")
            self.assertEqual(history.returncode, 1)
            self.assertNotIn(token, history.stdout)
            self.assertIn("credential-format", history.stdout.decode())
            archive = root / "fixture.zip"
            opaque = b"opaque-" + b"k" * 30
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("App/Contents/Resources/reviews.json", "{}")
                handle.writestr("App/Contents/MacOS/app", base64.b64encode(opaque))
            package = scan("--archive", str(archive), "--known-secret-stdin", secret=opaque)
            self.assertEqual(package.returncode, 1)
            self.assertNotIn(opaque, package.stdout)
            self.assertNotIn(base64.b64encode(opaque), package.stdout)
            self.assertEqual({v["category"] for v in json.loads(package.stdout)["findings"]}, {"private-file", "known-credential"})

    def test_c2pa_provenance_is_not_a_chat_identifier(self):
        image = SCRIPT.parent.parent / "Assets/codex-companion.png"
        data = image.read_bytes()
        self.assertTrue(checks.public_provenance_ranges(data))
        self.assertFalse(checks.findings(data, "production-image"))
        private_id = b"12345678" + b"-1234-4234-8234-123456789012"
        self.assertTrue(checks.findings(data + private_id, "outside-provenance"))


if __name__ == "__main__":
    unittest.main()
