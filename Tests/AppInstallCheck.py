import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_app", ROOT / "scripts/install-app.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
SOURCE = ROOT / "build/Clipboard AI Solver.app"


class AppInstallCheck(unittest.TestCase):
    def test_fresh_install_and_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / SOURCE.name
            module.install(SOURCE, target)
            self.assertEqual((target / "Contents/Info.plist").read_bytes(), (SOURCE / "Contents/Info.plist").read_bytes())
            (target / "obsolete-resource.txt").write_text("old version only")
            module.install(SOURCE, target)
            self.assertFalse((target / "obsolete-resource.txt").exists())
            self.assertEqual(list(Path(temporary).iterdir()), [target])

    def test_does_not_replace_unrelated_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / SOURCE.name
            (target / "Contents").mkdir(parents=True)
            value = plistlib.dumps({"CFBundleIdentifier": "test.someone-else"})
            (target / "Contents/Info.plist").write_bytes(value)
            with self.assertRaises(ValueError): module.install(SOURCE, target)
            self.assertEqual((target / "Contents/Info.plist").read_bytes(), value)

    def test_failed_promotion_restores_previous_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / SOURCE.name
            shutil.copytree(SOURCE, target)
            marker = target / "previous-build-marker.txt"; marker.write_text("keep")
            rename = Path.rename
            def fail_once(path, destination):
                if path.name == "new.app": raise OSError("simulated promotion failure")
                return rename(path, destination)
            with patch.object(Path, "rename", fail_once), self.assertRaises(OSError):
                module.install(SOURCE, target)
            self.assertEqual(marker.read_text(), "keep")
            self.assertEqual(list(Path(temporary).iterdir()), [target])

    def test_failed_rollback_keeps_backup_for_recovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / SOURCE.name
            shutil.copytree(SOURCE, target)
            (target / "previous-build-marker.txt").write_text("keep")
            rename = Path.rename
            def fail_restore(path, destination):
                if Path(destination) == target: raise OSError("simulated rename denial")
                return rename(path, destination)
            with patch.object(Path, "rename", fail_restore), self.assertRaises(RuntimeError):
                module.install(SOURCE, target)
            kept = list(Path(temporary).rglob("previous-build-marker.txt"))
            self.assertEqual(len(kept), 1)
            self.assertEqual(kept[0].read_text(), "keep")


if __name__ == "__main__": unittest.main()
