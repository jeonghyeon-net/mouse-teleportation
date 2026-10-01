import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("project", Path(__file__).parents[1] / "project.py")
project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project)


class PackageIntegrityTests(unittest.TestCase):
    def fixture(self, directory):
        assets = {}
        for suffix in ["dmg", "zip"]:
            path = directory / f"MouseTeleportation-{project.version()}-arm64.{suffix}"
            path.write_bytes(b"fixture")
            assets[path.name] = {"size": 7, "sha256": hashlib.sha256(b"fixture").hexdigest()}
        (directory / "release-manifest.json").write_text(json.dumps({"assets": assets}))
        (directory / "SHA256SUMS").write_text("".join(f"{assets[name]['sha256']}  {name}\n" for name in sorted(assets)))
        return next(directory.glob("*.dmg"))

    def test_accepts_matching_checksums(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.fixture(directory)
            project.verify_checksums(directory)

    def test_rejects_tampered_asset(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.fixture(directory).write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "체크섬"):
                project.verify_checksums(directory)

    def test_rejects_mismatched_checksum_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.fixture(directory)
            (directory / "SHA256SUMS").write_text("wrong")
            with self.assertRaisesRegex(RuntimeError, "SHA256SUMS"):
                project.verify_checksums(directory)
