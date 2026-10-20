"""Reuse a private local signing identity so updates retain their code requirement."""
from pathlib import Path
import json
import os
import plistlib
import re
import secrets
import subprocess
import sys
import tempfile

IDENTIFIER = "com.hjkim24.clipboard-ai-solver"
STATE = Path.home() / "Library/Application Support/Clipboard AI Solver Signing"


def command(args):
    try:
        return subprocess.run(args, check=True, capture_output=True, text=True, timeout=45)
    except subprocess.CalledProcessError as error:
        # Arguments can contain temporary keychain passwords; never print them.
        raise RuntimeError(f"{Path(args[0]).name} 실행 실패 ({error.returncode}). 서명 키체인 상태를 확인하세요.") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{Path(args[0]).name} 서명 작업 시간이 초과되었습니다.") from None


def requirement(app):
    result = command(["/usr/bin/codesign", "-d", "-r-", str(app)])
    for line in (result.stdout + result.stderr).splitlines():
        if "designated =>" in line:
            return line.split("designated =>", 1)[1].strip()
    raise RuntimeError("앱의 코드 서명 식별 정보를 읽지 못했습니다.")


def identity(state):
    if not state.exists():
        state.mkdir(parents=True, mode=0o700)
        password = secrets.token_urlsafe(32)
        path = state / "password"
        with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as output:
            output.write(password)
        certificate = state / "certificate.pem"
        with tempfile.TemporaryDirectory(prefix="create-", dir=state) as temporary:
            private = Path(temporary) / "private.pem"
            package = Path(temporary) / "identity.p12"
            command(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(private), "-out", str(certificate), "-days", "10950",
                     "-subj", "/CN=Clipboard AI Solver Local Signing", "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=critical,codeSigning"])
            private.chmod(0o600)
            command(["/usr/bin/openssl", "pkcs12", "-export", "-out", str(package), "-inkey", str(private), "-in", str(certificate), "-passout", "pass:" + password])
            keychain = state / "identity.keychain-db"
            command(["/usr/bin/security", "create-keychain", "-p", password, str(keychain)])
            command(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
            command(["/usr/bin/security", "import", str(package), "-k", str(keychain), "-P", password, "-x", "-T", "/usr/bin/codesign"])
        fingerprint = command(["/usr/bin/openssl", "x509", "-in", str(certificate), "-noout", "-fingerprint", "-sha1"]).stdout.split("=", 1)[1].replace(":", "").strip()
        (state / "identity.json").write_text(json.dumps({"sha1": fingerprint}))
    files = [state / name for name in ["identity.json", "password", "identity.keychain-db", "certificate.pem"]]
    if state.is_symlink() or not state.is_dir() or any(not path.is_file() or path.is_symlink() for path in files):
        raise RuntimeError("기존 서명 정보가 불완전합니다. 서명 폴더를 복원하세요. 다른 인증서나 임시 서명으로 자동 교체하지 않습니다.")
    if state.stat().st_uid != os.getuid() or state.stat().st_mode & 0o077 or (state / "password").stat().st_mode & 0o077:
        raise RuntimeError("서명 폴더와 비밀번호 파일은 현재 사용자만 접근할 수 있어야 합니다.")
    try:
        fingerprint = json.loads((state / "identity.json").read_text())["sha1"]
        password = (state / "password").read_text()
    except (ValueError, KeyError, TypeError):
        raise RuntimeError("기존 서명 정보를 읽지 못했습니다. 보관한 서명 폴더를 복원하세요.") from None
    if not isinstance(fingerprint, str) or re.fullmatch(r"[A-Fa-f0-9]{40}", fingerprint) is None or not password:
        raise RuntimeError("기존 서명 정보가 올바르지 않습니다.")
    command(["/usr/bin/openssl", "x509", "-in", str(state / "certificate.pem"), "-noout", "-checkend", "0"])
    return fingerprint, password


def sign_app(app, state=STATE):
    app = Path(app); state = Path(state)
    if app.is_symlink() or plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier") != IDENTIFIER:
        raise RuntimeError("Clipboard AI Solver 앱만 서명할 수 있습니다.")
    fingerprint, password = identity(state)
    keychain = state / "identity.keychain-db"
    command(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
    # shortcut: local certificate; use Developer ID when official distribution trust is needed.
    command(["/usr/bin/codesign", "--force", "--timestamp=none", "--keychain", str(keychain), "--sign", fingerprint, str(app)])
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    result = requirement(app)
    if "cdhash" in result or fingerprint.lower() not in result.lower():
        raise RuntimeError("고정 인증서에 연결된 코드 서명인지 확인하지 못했습니다.")
    return result


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2: raise RuntimeError("Usage: python3 scripts/sign-app.py <app>")
        sign_app(Path(sys.argv[1]))
        print("고정 로컬 인증서로 서명했습니다.")
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(str(error))
