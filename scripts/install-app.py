"""Install only this app, with a staged copy and rollback on replacement failure."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

IDENTIFIER = "com.hjkim24.clipboard-ai-solver"


def check_identity(app):
    if app.is_symlink() or not app.is_dir():
        raise ValueError(f"올바른 앱 폴더가 아닙니다: {app}")
    if plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier") != IDENTIFIER:
        raise ValueError(f"다른 앱은 교체하지 않습니다: {app}")


def verify(app):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)


def install(source, destination):
    check_identity(source)
    if destination.exists() or destination.is_symlink(): check_identity(destination)
    verify(source)
    temporary = Path(tempfile.mkdtemp(prefix=".clipboard-ai-install-", dir=destination.parent))
    new, previous = temporary / "new.app", temporary / "previous.app"
    installed = False
    try:
        subprocess.run(["ditto", str(source), str(new)], check=True)
        verify(new)
        if destination.exists(): destination.rename(previous)
        try:
            new.rename(destination)
            installed = True
        except BaseException:
            if previous.exists():
                try: previous.rename(destination)
                except OSError as error:
                    raise RuntimeError(f"이전 앱을 보존했습니다. 이 위치에서 복원하세요: {previous}") from error
            raise
    finally:
        if installed or not previous.exists(): shutil.rmtree(temporary)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    destination = Path("/Applications/Clipboard AI Solver.app")
    try:
        install(root / "build/Clipboard AI Solver.app", destination)
        print(destination)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"설치 실패: {error}")
