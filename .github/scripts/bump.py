#!/usr/bin/env python3
"""Bring the formulae up to the latest releases.

    python3 .github/scripts/bump.py [uccharan] [bolo] [--force]

uccharan: the latest GitHub release of cB-Sigma/uccharan; the url and sha256 of
its source tarball are written into Formula/uccharan.rb.

bolo: the latest version of bolo-speech on PyPI; the url and sha256 of its
wheel are written into Formula/bolo.rb, and the pinned requirements are
resolved again from a full install of bolo-speech[all] into a scratch
virtualenv (the interpreter is $PYTHON, default python3.13).

--force re-resolves bolo's pins even when the version has not changed.

Prints what changed. Under GitHub Actions it also writes `changed` (a JSON
list of the formulae that changed) and `summary` to $GITHUB_OUTPUT.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMULA = ROOT / "Formula"
UA = {"User-Agent": "homebrew-tap-autobump"}


def get(url: str, headers: dict[str, str] | None = None) -> bytes:
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def get_json(url: str, headers: dict[str, str] | None = None):
    return json.loads(get(url, headers))


def vtuple(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in re.findall(r"\d+", v))


def replace_one(text: str, pattern: str, repl: str) -> str:
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"pattern not found: {pattern}")
    return new


def bump_uccharan() -> str | None:
    path = FORMULA / "uccharan.rb"
    text = path.read_text()
    current = re.search(r'archive/refs/tags/v([^"/]+)\.tar\.gz"', text).group(1)
    headers = {"Accept": "application/vnd.github+json"}
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    release = get_json("https://api.github.com/repos/cB-Sigma/uccharan/releases/latest", headers)
    tag = release["tag_name"]
    latest = tag.removeprefix("v")
    if vtuple(latest) <= vtuple(current):
        print(f"uccharan {current} is current")
        return None
    url = f"https://github.com/cB-Sigma/uccharan/archive/refs/tags/{tag}.tar.gz"
    sha = hashlib.sha256(get(url)).hexdigest()
    text = replace_one(text, r'^  url "[^"]+"$', f'  url "{url}"')
    text = replace_one(text, r'^  sha256 "[0-9a-f]+"$', f'  sha256 "{sha}"')
    path.write_text(text)
    print(f"uccharan {current} -> {latest}")
    return f"uccharan {latest}"


def intel_mac_onnxruntime(resolved: str) -> str | None:
    """The newest onnxruntime up to `resolved` with an Intel macOS wheel for CPython 3.13."""
    releases = get_json("https://pypi.org/pypi/onnxruntime/json")["releases"]
    ok = [
        v for v, files in releases.items()
        if re.fullmatch(r"[\d.]+", v) and vtuple(v) <= vtuple(resolved)
        and any("cp313" in f["filename"] and "macosx" in f["filename"]
                and ("x86_64" in f["filename"] or "universal2" in f["filename"]) for f in files)
    ]
    return max(ok, key=vtuple) if ok else None


def resolve_bolo_pins(version: str) -> str:
    python = os.environ.get("PYTHON", "python3.13")
    with tempfile.TemporaryDirectory() as tmp:
        venv = Path(tmp) / "venv"
        subprocess.run([python, "-m", "venv", str(venv)], check=True)
        pip = [str(venv / "bin" / "python"), "-m", "pip", "--disable-pip-version-check", "--no-cache-dir"]
        subprocess.run([*pip, "install", "--quiet", "--only-binary=:all:", f"bolo-speech[all]=={version}"], check=True)
        frozen = subprocess.run([*pip, "freeze", "--all"], check=True, capture_output=True, text=True).stdout
    pins = []
    for line in sorted(frozen.splitlines(), key=str.lower):
        name = line.split("==")[0].lower().replace("_", "-")
        if not line.strip() or name in {"bolo-speech", "pip", "setuptools", "wheel"}:
            continue
        if name == "onnxruntime":
            # onnxruntime stopped publishing Intel macOS wheels after 1.23.
            ort = line.split("==")[1]
            intel = intel_mac_onnxruntime(ort)
            if intel and intel != ort:
                pins.append(f'{line}; sys_platform != "darwin" or platform_machine == "arm64"')
                pins.append(f'onnxruntime=={intel}; sys_platform == "darwin" and platform_machine == "x86_64"')
                continue
        pins.append(line)
    return "\n".join(pins)


def bump_bolo(force: bool) -> str | None:
    path = FORMULA / "bolo.rb"
    text = path.read_text()
    current = re.search(r"/bolo_speech-([^-]+)-py3-none-any\.whl", text).group(1)
    info = get_json("https://pypi.org/pypi/bolo-speech/json")
    latest = info["info"]["version"]
    if vtuple(latest) < vtuple(current) or (vtuple(latest) == vtuple(current) and not force):
        print(f"bolo {current} is current")
        return None
    wheel = next(
        u for u in get_json(f"https://pypi.org/pypi/bolo-speech/{latest}/json")["urls"]
        if u["packagetype"] == "bdist_wheel" and u["filename"].endswith("-py3-none-any.whl")
    )
    pins = resolve_bolo_pins(latest)
    text = replace_one(text, r'^  url "[^"]+", using: :nounzip$', f'  url "{wheel["url"]}", using: :nounzip')
    text = replace_one(text, r'^  sha256 "[0-9a-f]+"$', f'  sha256 "{wheel["digests"]["sha256"]}"')
    block = "\n".join(f"      {p}" for p in pins.splitlines())
    text, n = re.subn(
        r"(  def pinned_requirements\n    <<~EOS\n)(?:.*\n)*?(    EOS\n)",
        lambda m: m.group(1) + block + "\n" + m.group(2),
        text,
        count=1,
    )
    if n != 1:
        sys.exit("pinned_requirements block not found in Formula/bolo.rb")
    old = path.read_text()
    path.write_text(text)
    if text == old:
        print(f"bolo {latest}: nothing changed")
        return None
    print(f"bolo {current} -> {latest}" if latest != current else f"bolo {latest}: pins resolved again")
    return f"bolo {latest}"


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    names = [a for a in args if not a.startswith("--")] or ["uccharan", "bolo"]
    changed, summary = [], []
    for name in names:
        result = bump_uccharan() if name == "uccharan" else bump_bolo(force) if name == "bolo" else sys.exit(f"unknown formula {name}")
        if result:
            changed.append(name)
            summary.append(result)
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write(f"changed={json.dumps(changed)}\n")
            fh.write(f"summary={', '.join(summary)}\n")


if __name__ == "__main__":
    main()
