"""Build an allowlisted native distribution; does not publish or modify Git history."""
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True, encoding="utf-8").strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-clean", action="store_true")
    args = parser.parse_args()
    machine = platform.machine().lower()
    if machine not in ("x86_64", "amd64") or platform.system() not in ("Windows", "Linux"):
        raise SystemExit("Release builds currently support only Windows/Linux x86_64")
    dirty = bool(git("status", "--porcelain"))
    if args.require_clean and dirty:
        raise SystemExit("Release builds require a clean checkout")
    moon_home = Path(os.environ["MOON_HOME"])
    version = re.search(r'^version = "([0-9.]+)"', (ROOT / "moon.mod").read_text(), re.M)[1]
    label = ("windows" if os.name == "nt" else "linux") + "-x86_64"
    name = f"moonpv-{version}-{label}"
    subprocess.run(["moon", "build", "--target", "native", "--release", "--deny-warn"], cwd=ROOT, check=True)
    toolchain = subprocess.check_output(["moon", "version", "--all"], text=True, encoding="utf-8").strip()
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="moonpv-package-") as temporary:
        bundle = Path(temporary) / name

        def copy(source, destination):
            target = bundle / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

        for package, executable in [("cmd/main", "moonpv"), ("examples/sunspec_inverter", "moonpv-example")]:
            source = ROOT / "_build/native/release/build" / package / (Path(package).name + ".exe")
            target = "bin/" + executable + (".exe" if os.name == "nt" else "")
            copy(source, target)
            (bundle / target).chmod(0o755)
        files = ["LICENSE", "tools/demo.py", "tools/simulator.py", "licenses/simdutf-LICENSE-MIT"]
        files += ["tests/fixtures/sunspec/" + item for item in
                  ["model_1.json", "model_103.json", "model_203.json", "LICENSE", "README.md"]]
        for relative in files:
            copy(ROOT / relative, relative)
        copy(ROOT / "docs/BINARY.zh-CN.md", "README.md")
        copy(ROOT / ".mooncakes/moonbitlang/async/LICENSE", "licenses/async-LICENSE")
        copy(moon_home / "lib/core/LICENSE", "licenses/core-LICENSE")
        copy(moon_home / "lib/core/NOTICE", "licenses/core-NOTICE")
        # Preserve the complete license comment shipped with this compiler.
        backtrace = (moon_home / "include/backtrace.h").read_text(encoding="utf-8")
        (bundle / "licenses/backtrace-LICENSE").write_text(backtrace.split("*/", 1)[0] + "*/\n", encoding="utf-8")
        (bundle / "NOTICE.txt").write_text(
            "MoonPV: https://github.com/STW135-2026/moonpv (Apache-2.0; see LICENSE).\n"
            "Includes MoonBit core/runtime and moonbitlang/async by International Digital Economy Academy.\n"
            "Core/runtime: https://github.com/moonbitlang/core (Apache-2.0; licenses/core-LICENSE and core-NOTICE).\n"
            "Async 0.22.9: https://github.com/moonbitlang/async (Apache-2.0; licenses/async-LICENSE).\n"
            "Native runtime dependencies: simdutf (MIT; licenses/simdutf-LICENSE-MIT), "
            "libbacktrace (BSD; licenses/backtrace-LICENSE).\n"
            "SunSpec Alliance model definitions: see tests/fixtures/sunspec/README.md and LICENSE.\n",
            encoding="utf-8",
        )
        manifest = {
            "version": version, "source_commit": git("rev-parse", "HEAD"), "dirty": dirty,
            "platform": label, "build_system": platform.platform(), "toolchain": toolchain,
            "files_sha256": {file.relative_to(bundle).as_posix(): digest(file)
                             for file in sorted(bundle.rglob("*")) if file.is_file()},
        }
        (bundle / "BUILD.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        if os.name == "nt":
            archive = output / (name + ".zip")
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as packed:
                for file in sorted(bundle.rglob("*")):
                    if file.is_file():
                        packed.write(file, file.relative_to(bundle.parent))
        else:
            archive = output / (name + ".tar.gz")
            with tarfile.open(archive, "w:gz") as packed:
                packed.add(bundle, arcname=name)
    archive.with_name(archive.name + ".sha256").write_text(digest(archive) + "  " + archive.name + "\n", encoding="ascii")
    print(archive)


if __name__ == "__main__":
    main()
