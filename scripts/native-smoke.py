"""Exercise the built GUI host over real pipes, without keys or HTTP calls."""
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import struct
import subprocess
import tempfile
import time
import uuid


def frame(value):
    data = json.dumps(value).encode()
    return struct.pack("=I", len(data)) + data


def receive(process):
    def read(count):
        data = b""
        end = time.monotonic() + 8
        while len(data) < count:
            if not select.select([process.stdout], [], [], max(0, end - time.monotonic()))[0]:
                raise AssertionError("Native state timeout")
            part = os.read(process.stdout.fileno(), count - len(data))
            if not part:
                raise AssertionError("Host exited before a state message")
            data += part
        return data
    length, = struct.unpack("=I", read(4))
    assert 0 < length < 1_000_000
    return json.loads(read(length))


def main():
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="ai-solver-native-") as directory:
        app = Path(directory) / "Smoke.app"
        shutil.copytree(root / "build/Canvas RAG Solver.app", app)
        info = app / "Contents/Info.plist"
        values = plistlib.loads(info.read_bytes())
        origin = "chrome-extension://" + "a" * 32 + "/"
        values.update(CFBundleIdentifier="com.hjkim24.solver-smoke." + uuid.uuid4().hex, AllowedExtensionOrigin=origin)
        info.write_bytes(plistlib.dumps(values))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        binary = str(app / "Contents/MacOS/CanvasRAGSolver")
        rejected = subprocess.run([binary, "chrome-extension://" + "b" * 32 + "/"], capture_output=True, timeout=10)
        assert rejected.returncode == 2 and not rejected.stdout
        process = subprocess.Popen([binary, origin], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        try:
            assert receive(process)["state"] == "disabled"
            request_id = str(uuid.uuid4())
            data = frame(dict(version=1, type="begin", request_id=request_id))
            process.stdin.write(data[:2]); process.stdin.write(data[2:])
            state = receive(process)
            assert state["state"] == "disabled" and state["request_id"] == request_id
            process.stdin.write(frame(dict(version=1, type="cancel", request_id=request_id, reason="검사 취소")))
            assert receive(process)["state"] == "disabled"
            process.stdin.close()
            process.wait(timeout=8)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
    print("Native process smoke checks passed: 4 (origin, partial frame, cancel, EOF)")


if __name__ == "__main__":
    main()
