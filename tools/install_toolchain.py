"""Install the tested MoonBit release into a new, isolated directory.

No user PATH or existing MoonBit installation is changed. CI uses this script.
Checksums were verified against the official binary release and core archive.
"""
import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

VERSION = "0.10.21+06da1ed44"
BASE = "https://cli.moonbitlang.com"
ARCHIVES = {
    "Windows": ("moonbit-windows-x86_64.zip", "941b6596813861350d43e2fc92b4444f562f2b5589b07c1b82e5c62f07f47239"),
    "Linux": ("moonbit-linux-x86_64.tar.gz", "32f74e33538911313acba366d4a06e7678296aa7737945f678ff1fbc7f9f7f82"),
}
CORE_SHA256 = "9dee22c988998e41c6b39dfeacca3f354d6ac9da2159afd9f9d9853bcad1cc36"


def download(url, target, expected):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as response, target.open("wb") as output:
                shutil.copyfileobj(response, output)
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            if digest != expected:
                raise ValueError(f"Checksum mismatch: {target.name}: {digest}")
            return
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(2)


def unpack(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                path = (destination / member.filename).resolve()
                if not path.is_relative_to(destination.resolve()):
                    raise ValueError("Archive path escapes installation directory")
            bundle.extractall(destination)
    else:
        with tarfile.open(archive) as bundle:
            bundle.extractall(destination, filter="data")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists() and any(destination.iterdir()):
        parser.error("choose an empty installation directory; existing toolchains are left intact")
    if platform.machine().lower() not in ("amd64", "x86_64") or platform.system() not in ARCHIVES:
        parser.error("this installer supports Windows/Linux x86_64 only")
    filename, checksum = ARCHIVES[platform.system()]
    version = VERSION.replace("+", "%2B")
    with tempfile.TemporaryDirectory(prefix="moonpv-toolchain-") as temporary:
        folder = Path(temporary)
        print("Downloading pinned MoonBit " + VERSION, flush=True)
        download(f"{BASE}/binaries/{version}/{filename}", folder / filename, checksum)
        download(f"{BASE}/cores/core-{version}.zip", folder / "core.zip", CORE_SHA256)
        unpack(folder / filename, destination)
        unpack(folder / "core.zip", destination / "lib")
    if os.name != "nt":
        # The official Unix installer explicitly restores these permissions;
        # the release tarball does not mark every executable as executable.
        for executable in [*(destination / "bin").iterdir(), destination / "bin" / "internal" / "tcc"]:
            executable.chmod(executable.stat().st_mode | 0o111)
        (destination / "bin" / "moonx").symlink_to("moon")
    environment = dict(os.environ, MOON_HOME=str(destination))
    environment["PATH"] = str(destination / "bin") + os.pathsep + environment["PATH"]
    executable = destination / "bin" / ("moon.exe" if os.name == "nt" else "moon")
    subprocess.run([str(executable), "bundle", "--all"], cwd=destination / "lib" / "core", env=environment, check=True)
    subprocess.run([str(executable), "version", "--all"], env=environment, check=True)
    print("Set MOON_HOME to", destination, "and add its bin directory to PATH.")


if __name__ == "__main__":
    main()
