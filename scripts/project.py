#!/usr/bin/env python3
"""로컬 macOS 빌드, 설치, 패키지 검사, GitHub 릴리스. 외부 Python 패키지 불필요."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Mouse Teleportation.app"
EXECUTABLE = "MouseTeleportation"
BUNDLE_ID = "net.jeonghyeon.MouseTeleportation"
REPO = "jeonghyeon-net/mouse-teleportation"
INSTALL = Path("/Applications") / APP_NAME


def run(*args, capture=False, cwd=ROOT):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def version():
    value = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise RuntimeError("VERSION에는 X.Y.Z 형식의 버전이 필요합니다.")
    return value


def commit():
    result = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT,
                            text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else "uncommitted"


def executable(app):
    return app / "Contents/MacOS" / EXECUTABLE


def inspect(app, expected_commit=None):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != BUNDLE_ID or
            info.get("CFBundleShortVersionString") != version() or
            info.get("LSUIElement") is not True or
            (expected_commit and info.get("MouseTeleportationGitCommit") != expected_commit)):
        raise RuntimeError(f"앱 메타데이터가 소스와 다릅니다: {app}")
    if run("lipo", "-archs", executable(app), capture=True) != "arm64":
        raise RuntimeError("이번 배포는 arm64 전용입니다.")
    run("codesign", "--verify", "--strict", "--verbose=2", app)
    if not (app / "Contents/Resources/AppIcon.icns").is_file():
        raise RuntimeError("앱 아이콘이 없습니다.")
    return info


def build():
    run("swift", "build", "-c", "release", "--arch", "arm64")
    binaries = Path(run("swift", "build", "-c", "release", "--arch", "arm64", "--show-bin-path", capture=True))
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    app = output / APP_NAME
    processes = run("ps", "-axo", "comm=", capture=True).splitlines()
    if str(executable(app)) in [line.strip() for line in processes]:
        raise RuntimeError("build 폴더의 앱을 먼저 종료하세요. 설치된 앱은 계속 실행해도 됩니다.")
    with tempfile.TemporaryDirectory(prefix=".bundle-", dir=output) as temporary:
        staged = Path(temporary) / APP_NAME
        (staged / "Contents/MacOS").mkdir(parents=True)
        resources = staged / "Contents/Resources"
        resources.mkdir()
        iconset = Path(temporary) / "AppIcon.iconset"
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for multiplier in [1, 2]:
                pixels = size * multiplier
                suffix = "@2x" if multiplier == 2 else ""
                run("sips", "-z", pixels, pixels, ROOT / "Assets/AppIcon.png", "--out",
                    iconset / f"icon_{size}x{size}{suffix}.png", capture=True)
        run("iconutil", "-c", "icns", iconset, "-o", resources / "AppIcon.icns")
        shutil.copy2(binaries / EXECUTABLE, executable(staged))
        info = plistlib.loads((ROOT / "Config/Info.plist").read_bytes())
        info["CFBundleShortVersionString"] = version()
        info["CFBundleVersion"] = run("git", "rev-list", "--count", "HEAD", capture=True) if commit() != "uncommitted" else "1"
        info["MouseTeleportationGitCommit"] = commit()
        (staged / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        (staged / "Contents/PkgInfo").write_text("APPL????")
        shutil.copy2(ROOT / "LICENSE", resources / "LICENSE")
        identity = os.environ.get("SIGNING_IDENTITY")
        if identity:
            run("codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity, staged)
            signature = subprocess.run(["codesign", "-d", "--verbose=4", str(staged)], check=True,
                                       capture_output=True, text=True).stderr
            if "Authority=Developer ID Application:" not in signature:
                raise RuntimeError("SIGNING_IDENTITY는 Developer ID Application 인증서여야 합니다.")
        else:
            run("codesign", "--force", "--timestamp=none", "--sign", "-", staged)
        inspect(staged, commit())
        if app.exists():
            shutil.rmtree(app)
        staged.rename(app)
    print(f"앱 생성: {app}", flush=True)
    return app


def test():
    developer = Path(run("xcode-select", "-p", capture=True))
    plugin = developer / "usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    args = ["-Xswiftc", "-load-plugin-library", "-Xswiftc", plugin] if plugin.exists() else []
    run("swift", "test", *args)


def check():
    test()
    run("python3", "-m", "unittest", "discover", "-s", "scripts/tests")
    app = build()
    run(executable(app), "--self-test")
    return app


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_checksums(directory):
    manifest = json.loads((directory / "release-manifest.json").read_text())
    assets = manifest["assets"]
    if set(assets) != {f"MouseTeleportation-{version()}-arm64.{suffix}" for suffix in ["zip", "dmg"]}:
        raise RuntimeError("배포 파일명 또는 버전이 다릅니다.")
    for name, metadata in assets.items():
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"일반 배포 파일이 아닙니다: {name}")
        if path.stat().st_size != metadata["size"] or digest(path) != metadata["sha256"]:
            raise RuntimeError(f"체크섬 불일치: {name}")
    expected = "".join(f"{assets[name]['sha256']}  {name}\n" for name in sorted(assets))
    if (directory / "SHA256SUMS").read_text() != expected:
        raise RuntimeError("SHA256SUMS와 manifest가 다릅니다.")
    return manifest


def verify_package(directory):
    manifest = verify_checksums(directory)
    with tempfile.TemporaryDirectory(prefix="mouse-teleport-verify-") as temporary:
        temporary = Path(temporary)
        zip_path = next(directory.glob("*.zip"))
        run("ditto", "-x", "-k", zip_path, temporary / "zip")
        zip_app = temporary / "zip" / APP_NAME
        inspect(zip_app, manifest["commit"])
        run(executable(zip_app), "--self-test")
        mount = temporary / "mount"
        mount.mkdir()
        run("hdiutil", "attach", next(directory.glob("*.dmg")), "-readonly", "-nobrowse", "-mountpoint", mount)
        try:
            dmg_app = mount / APP_NAME
            inspect(dmg_app, manifest["commit"])
            if os.readlink(mount / "Applications") != "/Applications":
                raise RuntimeError("Applications 바로가기가 올바르지 않습니다.")
            zip_files = {p.relative_to(zip_app): digest(p) for p in zip_app.rglob("*") if p.is_file()}
            dmg_files = {p.relative_to(dmg_app): digest(p) for p in dmg_app.rglob("*") if p.is_file()}
            if zip_files != dmg_files:
                raise RuntimeError("ZIP과 DMG 앱 내용이 다릅니다.")
        finally:
            run("hdiutil", "detach", mount)
    print("ZIP·DMG 서명, 메타데이터, 파일 내용, 체크섬 검증 통과", flush=True)


def package(app=None, release=False):
    app = app or build()
    destination = ROOT / "dist" / ("releases" if release else "packages") / version()
    if destination.exists():
        if release:
            manifest = verify_checksums(destination)
            if manifest["commit"] != commit():
                raise RuntimeError("같은 버전의 다른 커밋 산출물이 있습니다. VERSION을 올리세요.")
            verify_package(destination)
            return destination
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".package-", dir=destination.parent) as temporary:
        temporary = Path(temporary)
        image = temporary / "image"
        image.mkdir()
        snapshot = image / APP_NAME
        run("ditto", app, snapshot)
        inspect(snapshot, commit())
        profile = os.environ.get("NOTARY_PROFILE")
        if profile:
            if not os.environ.get("SIGNING_IDENTITY"):
                raise RuntimeError("공증에는 SIGNING_IDENTITY가 필요합니다.")
            upload = temporary / "notarization.zip"
            run("ditto", "-c", "-k", "--keepParent", snapshot, upload)
            run("xcrun", "notarytool", "submit", upload, "--keychain-profile", profile, "--wait")
            run("xcrun", "stapler", "staple", snapshot)
            run("xcrun", "stapler", "validate", snapshot)
        output = temporary / "output"
        output.mkdir()
        name = f"MouseTeleportation-{version()}-arm64"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", snapshot, output / f"{name}.zip")
        (image / "Applications").symlink_to("/Applications")
        dmg = output / f"{name}.dmg"
        run("hdiutil", "create", "-volname", "Mouse Teleportation", "-srcfolder", image, "-format", "UDZO", dmg)
        if os.environ.get("SIGNING_IDENTITY"):
            run("codesign", "--timestamp", "--sign", os.environ["SIGNING_IDENTITY"], dmg)
        if profile:
            run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", profile, "--wait")
            run("xcrun", "stapler", "staple", dmg)
            run("xcrun", "stapler", "validate", dmg)
        assets = {p.name: {"size": p.stat().st_size, "sha256": digest(p)} for p in sorted(output.iterdir())}
        manifest = {"version": version(), "commit": commit(), "architecture": "arm64", "minimumMacOS": "14.0",
                    "signing": "Developer ID" if os.environ.get("SIGNING_IDENTITY") else "ad-hoc", "notarized": bool(profile), "assets": assets}
        (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (output / "SHA256SUMS").write_text("".join(f"{item['sha256']}  {name}\n" for name, item in assets.items()))
        verify_package(output)
        output.rename(destination)
    print(f"배포 파일: {destination}", flush=True)
    return destination


def stop_installed():
    # 앱 본체와 확대 helper 모두 SIGTERM으로 복원 절차를 거친다.
    processes = run("ps", "-axo", "pid=,comm=", capture=True)
    stopped = []
    for line in processes.splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) == 2 and parts[1] == str(executable(INSTALL)):
            try:
                os.kill(int(parts[0]), 15)
                stopped.append(int(parts[0]))
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 3
    while stopped and time.monotonic() < deadline:
        remaining = []
        for pid in stopped:
            try:
                os.kill(pid, 0)
                remaining.append(pid)
            except ProcessLookupError:
                pass
        stopped = remaining
        if stopped:
            time.sleep(0.05)
    if stopped:
        raise RuntimeError("앱 종료를 기다리는 중입니다. 활성 상태 보기에서 종료한 뒤 다시 실행하세요.")


def install():
    app = build()
    stop_installed()
    # 실행 파일 자체를 덮어쓰지 않고 새 번들을 원자적으로 교체한다.
    with tempfile.TemporaryDirectory(prefix=".mouse-teleport-", dir="/Applications") as temporary:
        staged = Path(temporary) / APP_NAME
        run("ditto", app, staged)
        previous = Path(temporary) / "previous.app"
        if INSTALL.exists():
            INSTALL.rename(previous)
        try:
            staged.rename(INSTALL)
        except BaseException:
            if previous.exists():
                previous.rename(INSTALL)
            raise
    run("open", "-g", INSTALL)
    run(executable(INSTALL), "--enable-login")
    print(f"설치 및 로그인 자동 실행 등록: {INSTALL}", flush=True)


def release_preflight():
    if run("git", "status", "--porcelain", capture=True):
        raise RuntimeError("릴리스 전에 변경 사항을 커밋하세요.")
    if run("git", "branch", "--show-current", capture=True) != "main":
        raise RuntimeError("릴리스는 main에서 실행하세요.")
    for args in [("get-url", "origin"), ("get-url", "--push", "origin")]:
        remote = run("git", "remote", *args, capture=True)
        if remote not in [f"https://github.com/{REPO}.git", f"git@github.com:{REPO}.git", f"https://github.com/{REPO}"]:
            raise RuntimeError("origin이 배포 저장소와 다릅니다.")
    remote = run("git", "ls-remote", "origin", "refs/heads/main", capture=True)
    if not remote or remote.split()[0] != commit():
        raise RuntimeError("현재 커밋을 origin/main에 먼저 푸시하세요.")


def prepare():
    release_preflight()
    app = check()
    destination = package(app, release=True)
    manifest = verify_checksums(destination)
    notes = f"""Option + Tab으로 마우스를 다른 디스플레이 중앙으로 이동합니다.

- 메뉴바, Dock, Command + Tab에 표시되지 않는 백그라운드 앱
- 최초 실행 시 로그인 자동 시작 등록
- 실제 시스템 커서를 잠깐 확대하고 원래 크기로 복원
- 도착 화면을 macOS의 활성 디스플레이로 전환하여 메뉴 막대 활성 표시
- 도착 화면의 사각 가장자리에 약 0.24초의 부드럽고 넓은 푸른빛 효과 표시
- 모니터가 3대 이상이면 왼쪽부터, 같은 x에서는 위부터 순환

macOS 14 이상 / Apple Silicon. DMG를 열어 앱을 Applications로 옮긴 뒤 실행하세요.

커서 확대와 활성 디스플레이 전환은 비공개 SkyLight API를 사용하며 OS 업데이트에 영향을 받을 수 있습니다. 확대는 macOS의 흔들기 제스처 자체를 호출하는 방식이 아닙니다. 디스플레이 활성화에 따라 macOS가 해당 화면에서 사용하던 앱을 앞으로 가져올 수 있으며, 앱이 별도 클릭을 보내거나 개별 창을 선택하지는 않습니다.

서명: {manifest['signing']}. Apple 공증: {'완료' if manifest['notarized'] else '없음'}. 공증되지 않은 다운로드는 macOS에서 차단될 수 있으며, 신뢰하는 배포인지 확인한 뒤 시스템 설정 → 개인정보 보호 및 보안에서 직접 허용해야 합니다.

소스 커밋: `{manifest['commit']}`

SHA-256은 첨부한 `SHA256SUMS`에 있습니다. 모든 파일은 로컬 Mac에서 빌드·검증했습니다.
"""
    (destination / "release-notes.md").write_text(notes)
    return destination


def release():
    destination = prepare()
    tag = "v" + version()
    # 같은 이름의 릴리스나 태그는 덮어쓰지 않는다. 실패한 초안도 자동 변경하지 않는다.
    releases = json.loads(run("gh", "api", f"repos/{REPO}/releases", "--paginate", "--slurp", capture=True))
    if any(item["tag_name"] == tag for page in releases for item in page):
        raise RuntimeError(f"{tag} 릴리스가 이미 있습니다. 기존 파일은 덮어쓰지 않습니다.")
    if run("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}", capture=True):
        raise RuntimeError(f"원격 태그 {tag}가 이미 있습니다.")
    local_tag = subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}"], cwd=ROOT, capture_output=True)
    if local_tag.returncode == 0:
        raise RuntimeError(f"로컬 태그 {tag}가 이미 있습니다.")
    release_preflight()
    manifest = verify_checksums(destination)
    if manifest["commit"] != commit():
        raise RuntimeError("빌드 후 소스 커밋이 변경되었습니다.")
    run("git", "tag", "-a", tag, "-m", tag, commit())
    run("git", "push", "origin", tag)
    names = [*manifest["assets"], "SHA256SUMS", "release-manifest.json"]
    run("gh", "release", "create", tag, *[destination / name for name in names], "--repo", REPO,
        "--verify-tag", "--draft", "--title", tag, "--notes-file", destination / "release-notes.md")
    with tempfile.TemporaryDirectory(prefix="mouse-teleport-download-") as temporary:
        run("gh", "release", "download", tag, "--repo", REPO, "--dir", temporary)
        downloaded = Path(temporary)
        if {p.name for p in downloaded.iterdir()} != set(names):
            raise RuntimeError("업로드된 파일 목록이 다릅니다. 초안을 보존했습니다.")
        for name in names:
            if digest(downloaded / name) != digest(destination / name):
                raise RuntimeError("업로드 검증 실패. 초안을 보존했습니다.")
    run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest")
    print(f"https://github.com/{REPO}/releases/tag/{tag}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "test", "check", "package", "install", "uninstall", "prepare", "release", "verify"])
    parser.add_argument("directory", nargs="?", type=Path)
    args = parser.parse_args()
    if args.command == "uninstall":
        if INSTALL.exists():
            run(executable(INSTALL), "--disable-login")
            stop_installed()
            shutil.rmtree(INSTALL)
        print("앱과 로그인 항목을 제거했습니다.")
    elif args.command == "verify":
        if not args.directory:
            parser.error("verify에는 배포 폴더가 필요합니다.")
        verify_package(args.directory.resolve())
    else:
        globals()[args.command]()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
