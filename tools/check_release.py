"""Unpack the built distribution outside the checkout and test with no MoonBit on PATH."""
import hashlib
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(archive):
    expected = archive.with_name(archive.name + ".sha256").read_text(encoding="ascii").split()[0]
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise ValueError("Archive checksum mismatch: " + archive.name)
    with tempfile.TemporaryDirectory(prefix="MoonPV unpacked test ") as temporary:
        # Windows runners may expose TEMP through a junction. Compare resolved
        # paths on both sides, otherwise safe archive members look unrelated.
        destination = Path(temporary).resolve()
        if archive.suffix == ".zip":
            with zipfile.ZipFile(archive) as packed:
                for name in packed.namelist():
                    if not (destination / name).resolve().is_relative_to(destination):
                        raise ValueError("Unsafe archive path")
                packed.extractall(destination)
        else:
            with tarfile.open(archive) as packed:
                packed.extractall(destination, filter="data")
        roots = list(destination.iterdir())
        if len(roots) != 1 or not roots[0].is_dir():
            raise ValueError("Expected one distribution directory")
        bundle = roots[0]
        manifest = json.loads((bundle / "BUILD.json").read_text(encoding="utf-8"))
        actual_files = {p.relative_to(bundle).as_posix() for p in bundle.rglob("*") if p.is_file()}
        if actual_files != set(manifest["files_sha256"]) | {"BUILD.json"}:
            raise ValueError("Unexpected or missing distribution files")
        for name, sha in manifest["files_sha256"].items():
            if hashlib.sha256((bundle / name).read_bytes()).hexdigest() != sha:
                raise ValueError("Bundled file checksum mismatch: " + name)
        environment = dict(os.environ, PATH="", PYTHONUTF8="1", PYTHONPATH="")
        environment.pop("MOON_HOME", None)
        executable = bundle / "bin" / ("moonpv.exe" if os.name == "nt" else "moonpv")

        def run(arguments, code=0):
            result = subprocess.run(arguments, cwd=destination, env=environment,
                                    capture_output=True, text=True, encoding="utf-8", timeout=20)
            if result.returncode != code:
                raise ValueError(f"Unexpected exit {result.returncode}: {result.stdout}\n{result.stderr}")
            return result

        help_result = run([str(executable), "--help"])
        if "moonpv sunspec" not in help_result.stdout or help_result.stderr:
            raise ValueError("Standalone help is missing or writes errors")
        invalid = run([str(executable), "invalid-command"], code=2)
        if invalid.stdout or not invalid.stderr:
            raise ValueError("Invalid arguments must produce stderr only")
        demo = run([sys.executable, str(bundle / "tools/demo.py")])
        if "PASS: discovery, readings, accumulator status and API example" not in demo.stdout or demo.stderr:
            raise ValueError("Packaged demo did not pass cleanly")
        payload = run([sys.executable, str(bundle / "tools/demo.py"), "--json"])
        snapshots = json.loads(payload.stdout)["snapshots"]
        if len(snapshots) != 3 or snapshots[0]["points"]["active_power"]["value"] != "4200" or payload.stderr:
            raise ValueError("Packaged JSON demo returned unexpected data")
        # A partial extraction must fail rather than finding a local developer build.
        executable.unlink()
        missing = run([sys.executable, str(bundle / "tools/demo.py")], code=1)
        if missing.stdout or "Missing bundled program" not in missing.stderr or "Traceback" in missing.stderr:
            raise ValueError("Missing program failure is unclear")
        report = f"Archive: {archive.name}\nSource: {manifest['source_commit']}\n"
        report += demo.stdout + "PASS: file hashes, clean PATH, help, exit codes, JSON and missing-program error\n"
        archive.with_name(archive.name + ".verification.txt").write_text(report, encoding="utf-8")
        print(report, end="")


if __name__ == "__main__":
    archives = [Path(arg).resolve() for arg in sys.argv[1:]] if len(sys.argv) > 1 else sorted(
        list((ROOT / "dist").glob("*.zip")) + list((ROOT / "dist").glob("*.tar.gz")))
    if not archives:
        raise SystemExit("No release archives; run tools/package_release.py first")
    for archive in archives:
        check(archive)
