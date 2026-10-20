import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("register_host", Path(__file__).resolve().parents[1] / "scripts/register-host.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class InstallerCheck(unittest.TestCase):
    def test_registration_is_restricted_and_reinstallable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "build/Canvas RAG Solver.app/Contents"
            (app / "MacOS").mkdir(parents=True)
            (app / "MacOS/CanvasRAGSolver").touch()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleName": "Test"}))
            host = root / "NativeMessagingHosts"
            with patch.object(module, "__file__", str(root / "scripts/register-host.py")), patch.object(module.subprocess, "run"):
                module.register("a" * 32, str(host))
                module.register("a" * 32, str(host))
                manifest_path = host / "com.hjkim24.canvas_rag_solver.json"
                manifest = json.loads(manifest_path.read_text())
                self.assertEqual(manifest["allowed_origins"], ["chrome-extension://" + "a" * 32 + "/"])
                self.assertEqual(plistlib.loads((app / "Info.plist").read_bytes())["AllowedExtensionOrigin"], manifest["allowed_origins"][0])
                manifest["path"] = "/other/host"
                manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    module.register("a" * 32, str(host))

    def test_rejects_invalid_id_or_destination(self):
        for extension_id, destination in [("bad", "/tmp/NativeMessagingHosts"), ("a" * 32, "/tmp/wrong"), ("a" * 32, "NativeMessagingHosts")]:
            with self.assertRaises(ValueError):
                module.register(extension_id, destination)


if __name__ == "__main__":
    unittest.main()
