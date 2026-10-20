"""Exercise update identity with isolated certificates, keychains and app copies."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sign_app", ROOT / "scripts/sign-app.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SigningCheck(unittest.TestCase):
    def test_changed_build_keeps_identity_but_other_signer_does_not_match(self):
        with tempfile.TemporaryDirectory(prefix="solver-signing-check-") as directory:
            root = Path(directory)
            state = root / "identity"
            other = root / "other-identity"
            try:
                apps = [root / f"Version{i}.app" for i in range(3)]
                for i, app in enumerate(apps):
                    shutil.copytree(ROOT / "build/Clipboard AI Solver.app", app)
                    (app / "Contents/Resources/update-test.txt").write_text(str(i))
                module.sign_app(apps[0], state)
                original = module.requirement(apps[0])
                credentials = (state / "identity.json").read_bytes()
                module.sign_app(apps[1], state)
                self.assertEqual(original, module.requirement(apps[1]))
                self.assertEqual(credentials, (state / "identity.json").read_bytes())
                self.assertNotIn("cdhash", original)
                for app in apps[:2]:
                    subprocess.run(["codesign", "--verify", "--deep", "--strict", "-R=" + original, str(app)], check=True, capture_output=True)
                module.sign_app(apps[2], other)
                mismatch = subprocess.run(["codesign", "--verify", "-R=" + original, str(apps[2])], capture_output=True)
                self.assertNotEqual(mismatch.returncode, 0)
                self.assertEqual((state / "password").stat().st_mode & 0o777, 0o600)
                self.assertEqual(state.stat().st_mode & 0o777, 0o700)
                for invalid in ["[]", "null"]:
                    with self.subTest(invalid=invalid):
                        (state / "identity.json").write_text(invalid)
                        try:
                            with self.assertRaises(RuntimeError): module.sign_app(apps[1], state)
                        finally:
                            (state / "identity.json").write_bytes(credentials)
            finally:
                for folder in [state, other]:
                    keychain = folder / "identity.keychain-db"
                    if keychain.exists():
                        subprocess.run(["security", "delete-keychain", str(keychain)], check=True, capture_output=True)

    def test_incomplete_identity_fails_without_recreating_key(self):
        with tempfile.TemporaryDirectory(prefix="solver-signing-incomplete-") as directory:
            state = Path(directory)
            marker = state / "keep.txt"; marker.write_text("preserve")
            with self.assertRaises(RuntimeError):
                module.sign_app(ROOT / "build/Clipboard AI Solver.app", state)
            self.assertEqual(list(state.iterdir()), [marker])
            self.assertEqual(marker.read_text(), "preserve")


if __name__ == "__main__": unittest.main()
