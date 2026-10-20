"""Register one locally built Native Messaging host for one extension."""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def register(extension_id, host_directory):
    if not re.fullmatch(r"[a-p]{32}", extension_id):
        raise ValueError("확장 ID는 a~p로 된 32자리여야 합니다.")
    directory = Path(host_directory).expanduser()
    if not directory.is_absolute() or directory.name != "NativeMessagingHosts":
        raise ValueError("브라우저의 NativeMessagingHosts 절대 경로를 지정하세요.")
    root = Path(__file__).resolve().parent.parent
    app = root / "build/Canvas RAG Solver.app"
    binary = app / "Contents/MacOS/CanvasRAGSolver"
    if not binary.is_file():
        raise ValueError("먼저 bash scripts/legacy-build.sh를 실행하세요.")
    origin = f"chrome-extension://{extension_id}/"
    manifest = {"name": "com.hjkim24.canvas_rag_solver", "description": "Canvas RAG Solver",
                "path": str(binary), "type": "stdio", "allowed_origins": [origin]}
    destination = directory / (manifest["name"] + ".json")
    if destination.exists():
        existing = json.loads(destination.read_text())
        if existing.get("path") != str(binary):
            raise ValueError("같은 이름의 다른 host가 있습니다. 기존 등록을 확인하세요.")
    plist = app / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info["AllowedExtensionOrigin"] = origin
    plist.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    directory.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(destination)
    print(destination)


if __name__ == "__main__":
    try:
        register(*sys.argv[1:])
    except (ValueError, OSError, subprocess.CalledProcessError, TypeError) as error:
        print(f"등록 실패: {error}", file=sys.stderr)
        sys.exit(1)
