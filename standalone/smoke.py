#!/usr/bin/env python3
"""Launch a disposable copy, verify defaults and request an ordinary AppKit quit."""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid
import json

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build/Clipboard AI Solver.app"


def main():
    assert SOURCE.is_dir(), "Run bash standalone/build.sh first"
    bundle = "com.hjkim24.clipboard-solver-smoke." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="clipboard-solver-smoke-") as directory:
        temporary = pathlib.Path(directory)
        app = temporary / "Clipboard Solver Smoke.app"
        shutil.copytree(SOURCE, app)
        info = app / "Contents/Info.plist"
        value = plistlib.loads(info.read_bytes()); value["CFBundleIdentifier"] = bundle
        info.write_bytes(plistlib.dumps(value))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        quitter = temporary / "quit-app"
        subprocess.run(["swiftc", "-module-cache-path", str(ROOT / "build/ClipboardModuleCache"), str(ROOT / "scripts/quit-app.swift"), "-o", str(quitter), "-framework", "AppKit"], check=True, capture_output=True)
        subprocess.run([str(quitter), bundle], check=True, capture_output=True, timeout=5)
        process = subprocess.Popen([str(app / "Contents/MacOS/ClipboardAISolver")], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            configuration = None
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                assert process.poll() is None, "App exited without a browser connection"
                exported = subprocess.run(["defaults", "export", bundle, "-"], capture_output=True)
                if exported.returncode == 0:
                    data = plistlib.loads(exported.stdout).get("solver.configuration")
                    if data:
                        configuration = json.loads(data); break
                time.sleep(0.2)
            assert configuration, "Startup did not save its own configuration"
            assert configuration["mode"] == "general" and not configuration["capsLockBlink"]
            assert configuration["files"] == [] and configuration["claudeFiles"] == []
            subprocess.run([str(quitter), bundle], check=True, capture_output=True, timeout=15)
            stdout, stderr = process.communicate(timeout=10)
            assert process.returncode == 0, "App did not quit cleanly"
            assert stdout == b"", "Standalone app unexpectedly emitted native messaging frames"
            print("App smoke passed: direct launch without stdin, isolated defaults, general mode/LED off, ordinary quit")
        finally:
            if process.poll() is None:
                process.kill(); process.communicate(timeout=5)
            subprocess.run(["defaults", "delete", bundle], capture_output=True)


if __name__ == "__main__":
    main()
