"""Build and publish one committed Flutter mobile release from a local checkout."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = "MycroftCooper/PrimitiveAccumulation"
ANDROID_SIGNER = "9f16970baefe7081e486c303b0a2b62038fd37fb3adcf080c93f5580fab45da4"


def run(*args, cwd=ROOT, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def output(*args):
    return run(*args, stdout=subprocess.PIPE, encoding="utf-8").stdout.strip()


def android_build(frontend, version, number):
    flutter = shutil.which(os.environ.get("PA_FLUTTER", "flutter"))
    if not flutter:
        raise ValueError("请配置 Flutter 或设置 PA_FLUTTER。")
    # sqlite3 rechecks its pinned SHA-256 before accepting a cached download.
    cache = Path(".dart_tool/hooks_runner/shared/sqlite3/build")
    for entry in (ROOT / "frontend" / cache).glob("download-*"):
        if entry.is_dir():
            shutil.copytree(entry, frontend / cache / entry.name)
    for args in [
        ["pub", "get", "--enforce-lockfile"],
        ["analyze", "--no-pub"],
        ["test", "--no-pub"],
        ["build", "apk", "--release", "--no-pub"],
    ]:
        run(flutter, *args, cwd=frontend)
    apk = frontend / "build/app/outputs/flutter-apk/app-release.apk"
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("请设置 ANDROID_HOME 以验证正式包。")
    builds = Path(sdk, "build-tools")
    versions = [p for p in builds.iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", p.name)]
    if not versions:
        raise ValueError("缺少 Android SDK build-tools。")
    tools = max(versions, key=lambda p: tuple(map(int, p.name.split("."))))
    win = sys.platform == "win32"
    signature = output(tools / ("apksigner.bat" if win else "apksigner"),
                       "verify", "--print-certs", apk)
    if f"certificate SHA-256 digest: {ANDROID_SIGNER}" not in signature:
        raise ValueError("APK 签名与已有正式版不一致。")
    package = output(tools / ("aapt.exe" if win else "aapt"), "dump", "badging", apk)
    if f"versionCode='{number}' versionName='{version}'" not in package.splitlines()[0]:
        raise ValueError("APK 版本与 pubspec.yaml 不一致。")
    return apk


def remote_ios(host, archive, ipa):
    if not re.fullmatch(r"[a-zA-Z0-9_][a-zA-Z0-9@._-]*", host):
        raise ValueError("PA_MAC_HOST 请使用 SSH 别名或 user@host。")
    options = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes"]
    ssh = ["ssh", *options, host]
    remote_dir = output(*ssh, "mktemp -d /tmp/pa-ios.XXXXXXXX")
    if not re.fullmatch(r"/tmp/pa-ios\.[A-Za-z0-9]{8}", remote_dir):
        raise ValueError("无法确认 Mac 的临时构建目录。")
    try:
        with archive.open("rb") as src:
            run(*ssh, f"cd {remote_dir} && tar -xf - && /bin/bash -l scripts/build-ios.sh",
                stdin=src)
        run("scp", *options, f"{host}:{remote_dir}/app.ipa", ipa)
    finally:
        run(*ssh, f"rm -rf {remote_dir}")


def verify_ipa(ipa, version, number):
    with zipfile.ZipFile(ipa) as bundle:
        plists = [p for p in bundle.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", p)]
        if len(plists) != 1:
            raise ValueError("IPA 缺少应用 Info.plist。")
        info = plistlib.loads(bundle.read(plists[0]))
        if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (version, number):
            raise ValueError("IPA 版本与 pubspec.yaml 不一致。")


def publish(tag, commit, assets):
    # Use the same repository for the tag and release even if gh has a default fork.
    run("gh", "repo", "view", REPO, "--json", "nameWithOwner")
    run("git", "push", f"https://github.com/{REPO}.git", f"{commit}:refs/tags/{tag}")
    gh = ["gh", "release"]
    repo = ["--repo", REPO]
    existing = subprocess.run([*gh, "view", tag, *repo, "--json", "isDraft,name"],
                              cwd=ROOT, stdout=subprocess.PIPE, text=True)
    if existing.returncode == 0:
        release = json.loads(existing.stdout)
        if not release["isDraft"] or release["name"] != tag:
            raise ValueError(f"{tag} 已有 Release，请检查版本号。")
        # A previous upload can leave this release in draft. Replace both files.
        run(*gh, "upload", tag, *assets, *repo, "--clobber")
    else:
        run(*gh, "create", tag, *assets, *repo, "--draft", "--verify-tag",
            "--title", tag, "--generate-notes")
    uploaded = json.loads(output(*gh, "view", tag, *repo, "--json", "assets,isDraft"))
    sizes = {a["name"]: a["size"] for a in uploaded["assets"] if a["state"] == "uploaded"}
    if not uploaded["isDraft"] or sizes != {p.name: p.stat().st_size for p in assets}:
        raise ValueError("草稿附件与本次构建不一致，请检查 GitHub Release。")
    run(*gh, "edit", tag, *repo, "--draft=false")


def main():
    if not os.environ.get("PA_FLUTTER"):
        flutter = output("git", "config", "--default", "flutter", "--get", "pa.flutter")
        os.environ["PA_FLUTTER"] = flutter
    commit = output("git", "rev-parse", "HEAD")
    if output("git", "status", "--porcelain", "--untracked-files=all", "--", "frontend", "scripts"):
        raise ValueError("请先提交要发布的客户端和脚本改动，安装包将从该提交构建。")
    with tempfile.TemporaryDirectory(prefix="pa-release-") as tmp:
        work = Path(tmp)
        archive = work / "source.tar"
        run("git", "archive", "--format=tar", "-o", archive, commit,
            "frontend", "scripts/build-ios.sh")
        run("tar", "-xf", archive, cwd=work)
        frontend = work / "frontend"
        match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
                          (frontend / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
        if not match:
            raise ValueError("pubspec.yaml 需设置三段版本号与整数构建号。")
        version, number = match.groups()
        tag = f"v{version}"
        dest = ROOT / "frontend/build/releases" / tag / commit[:12]
        dest.mkdir(parents=True, exist_ok=True)
        stem = f"PrimitiveAccumulation-{version}-{number}"
        print(f"构建 {tag} ({number}) @ {commit}", flush=True)
        android = android_build(frontend, version, number)
        apk = dest / f"{stem}.apk"
        shutil.copyfile(android, apk)
        print(f"已验证 Android 正式包 {apk}", flush=True)
        ipa = work / "app.ipa"
        if sys.platform == "darwin":
            run("/bin/bash", work / "scripts/build-ios.sh", cwd=work)
        elif os.environ.get("PA_MAC_HOST"):
            remote_ios(os.environ["PA_MAC_HOST"], archive, ipa)
        else:
            raise ValueError("iOS 打包需要 Mac。请在 Mac 上运行，或设置 PA_MAC_HOST。本次尚未发布。")
        verify_ipa(ipa, version, number)
        ios = dest / f"{stem}.ipa"
        shutil.copyfile(ipa, ios)
        # Upload from this invocation's isolated workspace.
        android = android.rename(work / apk.name)
        ipa = ipa.rename(work / ios.name)
        publish(tag, commit, [android, ipa])
        print(f"https://github.com/{REPO}/releases/tag/{tag}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        sys.exit(f"发布管线停止。{error}")
