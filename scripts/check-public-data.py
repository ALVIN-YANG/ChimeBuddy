#!/usr/bin/env python3
"""Read-only publication checks. Findings never print matched secret values.

Default: tracked working files. --history: branch/tag blobs and author
metadata. --archive: ZIP contents. Optional exact secret is read from stdin.
This is a scoped leak check, not a claim that arbitrary personal data is found.
"""
import argparse
import base64
import json
import re
import subprocess
import struct
import sys
import zipfile
from pathlib import Path

RULES = {
    "private-home": re.compile(rb"/Users/(?!Shared(?:/|\b)|USER(?:/|\b)|user(?:/|\b)|example(?:/|\b)|USERNAME(?:/|\b))[A-Za-z0-9_.-]+/"),
    "credential-format": re.compile(rb"(?:sk[_-][A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)"),
    "literal-session": re.compile(rb"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"),
}
WEBSOCKET_GUID = b"258eafa5-e914-47da-95ca-c5ab0dc85b11"
PRIVATE_FILES = {"auth.json", "voice.json", "reviews.json", "shared-memory.json", "receipts.jsonl", ".env"}


def public_provenance_ranges(data):
    """C2PA manifest URNs identify public image provenance, not user chats."""
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return []
    ranges = []
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            break
        if data[offset + 4:offset + 8] == b"caBX":
            ranges.append((offset + 8, end - 4))
        offset = end
    return ranges


def findings(data, location, known=b""):
    result = []
    provenance = public_provenance_ranges(data)
    for category, pattern in RULES.items():
        for match in pattern.finditer(data):
            value = match.group()
            if category == "literal-session" and (value.lower() == WEBSOCKET_GUID or value.startswith(b"00000000-")):
                continue
            if category == "literal-session" and data[max(0, match.start() - 9):match.start()] == b"urn:c2pa:" and any(start <= match.start() < end for start, end in provenance):
                continue
            result.append({"category": category, "location": location, "line": data.count(b"\n", 0, match.start()) + 1})
    if len(known) >= 20:
        variants = {known, base64.b64encode(known), known.hex().encode()}
        if any(value in data for value in variants):
            result.append({"category": "known-credential", "location": location})
    return result


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--archive", type=Path, action="append", default=[])
    parser.add_argument("--known-secret-stdin", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    known = sys.stdin.buffer.read().strip() if args.known_secret_stdin else b""
    if args.known_secret_stdin and len(known) < 20:
        raise SystemExit("Exact-credential check requires at least 20 input bytes; value not printed")
    result = []
    checked = 0
    if args.history:
        # Publication covers branch and version-tag refs. Local Codex tree
        # checkpoints and remote-tracking refs are not pushed by this workflow.
        objects = git(args.repo, "rev-list", "--objects", "--branches", "--tags").decode().splitlines()
        process = subprocess.Popen(["git", "-C", str(args.repo), "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        for row in objects:
            sha, _, name = row.partition(" ")
            process.stdin.write((sha + "\n").encode()); process.stdin.flush()
            header = process.stdout.readline().decode().split()
            data = process.stdout.read(int(header[2])); process.stdout.read(1)
            if header[1] == "blob":
                checked += 1
                result.extend(findings(data, sha[:12] + ":" + name, known))
            elif header[1] in {"commit", "tag"}:
                result.extend(findings(data, sha[:12], known))
                for line in data.splitlines():
                    if line.startswith((b"author ", b"committer ", b"tagger ")):
                        match = re.search(rb"<([^>]+)>", line)
                        if match and not match[1].endswith(b"@users.noreply.github.com"):
                            result.append({"category": "author-email", "location": sha[:12]})
        process.stdin.close(); process.stdout.close()
        if process.wait() != 0:
            raise SystemExit("Git object scan failed")
    else:
        for name in git(args.repo, "ls-files", "-z").decode().split("\0"):
            if not name:
                continue
            path = args.repo / name
            if path.is_file():
                checked += 1
                result.extend(findings(path.read_bytes(), name, known))
    for archive in args.archive:
        with zipfile.ZipFile(archive) as handle:
            if handle.testzip() is not None:
                result.append({"category": "archive-integrity", "location": archive.name})
            for entry in handle.infolist():
                if entry.is_dir():
                    continue
                checked += 1
                name = Path(entry.filename).name
                if name in PRIVATE_FILES or name.startswith(".env.") or name.endswith((".p8", ".key", ".sqlite")) or "/.git/" in entry.filename:
                    result.append({"category": "private-file", "location": archive.name + ":" + entry.filename})
                if entry.file_size > 64 * 1024 * 1024:
                    result.append({"category": "oversize-unscanned", "location": archive.name + ":" + entry.filename})
                else:
                    result.extend(findings(handle.read(entry), archive.name + ":" + entry.filename, known))
    report = {"checked": checked, "findings": result, "passed": not result}
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print("Publication check:", "PASS" if not result else "FAIL", "checked", checked, "objects/files")
        for value in result:
            print(value["category"], value["location"], "line=" + str(value.get("line", "-")))
    return 1 if result else 0


if __name__ == "__main__":
    sys.exit(main())
