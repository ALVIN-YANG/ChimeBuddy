#!/usr/bin/env python3
"""Notarize an already Developer ID-signed app, staple, verify and package.

Uses an existing notarytool Keychain profile. Raw Apple receipts stay under
.build; stdout never includes identity names, credentials or submission IDs.
A timed-out submission is resumed, never uploaded again blindly.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import time
import zipfile
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--profile", default=os.environ.get("CHIMEBUDDY_NOTARY_PROFILE"))
    args = parser.parse_args()
    if not args.profile:
        raise RuntimeError("需要已保存的 notarytool 钥匙串配置名称。")
    root = Path(__file__).resolve().parent.parent
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("无效版本号。")
    receipts = root / ".build/notary-receipts" / ("v" + version)
    receipts.mkdir(parents=True, exist_ok=True); receipts.chmod(0o700)
    destination = root / ".build/releases" / ("v" + version)
    destination.mkdir(parents=True, exist_ok=True)
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]

    def run(command, name, check=True, timeout=None):
        result = subprocess.run(command, capture_output=True, timeout=timeout)
        for suffix, data in [("stdout", result.stdout), ("stderr", result.stderr)]:
            path = receipts / (name + "." + suffix)
            path.write_bytes(data); path.chmod(0o600)
        if check and result.returncode:
            raise RuntimeError(name + " 失败；脱敏前的诊断保留在本机私有回执目录。")
        return result

    detail = run(["codesign", "-d", "--verbose=4", str(app)], "signature").stderr.decode()
    if "Authority=Developer ID Application:" not in detail or "runtime" not in detail or "Timestamp=" not in detail:
        raise RuntimeError("候选包缺少 Developer ID、Hardened Runtime 或安全时间戳。")
    entitlements = run(["codesign", "-d", "--entitlements", ":-", str(app)], "entitlements").stdout
    if entitlements.strip():
        values = plistlib.loads(entitlements)
        if values.get("com.apple.security.get-task-allow"):
            raise RuntimeError("发布包不能启用 get-task-allow。")
    run(["codesign", "--verify", "--deep", "--strict", str(app)], "signature-check")
    state_file = receipts / "candidate.json"
    state = {"bundleID": info["CFBundleIdentifier"], "version": version, "build": info["CFBundleVersion"], "executableSHA256": sha(binary)}
    if state_file.exists():
        if json.loads(state_file.read_text()) != state:
            raise RuntimeError("本版本已有不同候选包；不可复用旧公证结果。请检查原提交或递增版本。")
    else:
        state_file.write_text(json.dumps(state, indent=2)); state_file.chmod(0o600)
    submission_file = receipts / "submission.stdout"
    if submission_file.exists():
        try:
            submission = json.loads(submission_file.read_text())
        except ValueError:
            raise RuntimeError("已有上传回执未能解析，先核对 Apple history，不重复上传。")
    else:
        upload = receipts / ("ChimeBuddy-v" + version + "-upload.zip")
        run(["ditto", "-c", "-k", "--keepParent", str(app), str(upload)], "upload-zip")
        print("Uploading the signed candidate to Apple", flush=True)
        submitted = run(["xcrun", "notarytool", "submit", str(upload), "--keychain-profile", args.profile, "--output-format", "json", "--no-progress"], "submission", check=False)
        if submitted.returncode:
            raise RuntimeError("上传未确认；回执已保留，请先查询原提交，不重复上传。")
        submission = json.loads(submitted.stdout)
    identifier = submission.get("id", "")
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", identifier):
        raise RuntimeError("缺少可核对的 Apple 提交 ID，不继续打包。")
    result = None
    last = None
    for _ in range(60):
        response = run(["xcrun", "notarytool", "info", identifier, "--keychain-profile", args.profile, "--output-format", "json"], "status", timeout=60)
        result = json.loads(response.stdout)
        status = result.get("status")
        if status != last:
            print("Apple notarization:", status, flush=True); last = status
        if status == "Accepted":
            break
        if status in {"Invalid", "Rejected"}:
            run(["xcrun", "notarytool", "log", identifier, "--keychain-profile", args.profile, str(receipts / "apple-log.json")], "rejection-log", check=False)
            raise RuntimeError("Apple 未接受候选包，检查本机日志后再修复；安装包不会发布。")
        time.sleep(30)
    else:
        raise RuntimeError("Apple 仍在处理，保留原提交；重新运行此脚本将查询同一提交。")
    (receipts / "accepted.json").write_text(json.dumps(result, indent=2))
    run(["xcrun", "notarytool", "log", identifier, "--keychain-profile", args.profile, str(receipts / "apple-log.json")], "accepted-log", check=False)
    run(["xcrun", "stapler", "staple", str(app)], "staple")
    run(["xcrun", "stapler", "validate", str(app)], "staple-check")
    run(["codesign", "--verify", "--deep", "--strict", str(app)], "final-signature")
    assessment = run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], "gatekeeper")
    if b"Notarized Developer ID" not in assessment.stderr:
        raise RuntimeError("Gatekeeper 未确认 Notarized Developer ID。")
    archive = destination / ("ChimeBuddy-v" + version + "-macos-arm64.zip")
    run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], "final-zip")
    with zipfile.ZipFile(archive) as handle:
        if handle.testzip() is not None:
            raise RuntimeError("ZIP 完整性检查失败。")
    run(["python3", str(root / "scripts/check-public-data.py"), "--archive", str(archive)], "publication-check")
    (destination / "SHA256SUMS.txt").write_text(sha(archive) + "  " + archive.name + "\n")
    public = {**state, "notarization": "Accepted", "stapled": True, "gatekeeper": "Notarized Developer ID", "archiveSHA256": sha(archive)}
    (destination / "verification.json").write_text(json.dumps(public, indent=2))
    print("PASS: Apple Accepted, ticket stapled, signature and Gatekeeper verified; final ZIP ready", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        # Exception details from subprocesses can contain private argument values.
        print("FAIL:", str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
