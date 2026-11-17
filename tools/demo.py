"""Build and run MoonPV against a local fixture; no device or Python packages needed."""
import argparse
import json
import subprocess
from pathlib import Path
from simulator import FixtureServer, ROOT


def binary(package="cmd/main"):
    name = Path(package).name + ".exe"
    # Moon's native build artifact uses .exe on Linux as well as Windows.
    path = ROOT / "_build" / "native" / "release" / "build" / package / name
    if not path.is_file():
        raise FileNotFoundError(f"{path}: run moon build --target native --release first")
    return str(path)


def run_cli(server, *args, command="sunspec"):
    return subprocess.run(
        [binary(), command, "127.0.0.1", str(server.port), "1", *map(str, args)],
        text=True, encoding="utf-8", capture_output=True, timeout=10,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    if not args.no_build:
        subprocess.run(["moon", "build", "--target", "native", "--release"], cwd=ROOT, check=True)
    with FixtureServer() as server:
        result = run_cli(server, "--json")
        if result.returncode:
            raise SystemExit(result.stderr)
        print("Local simulated PV site (not a real-device measurement):")
        print(result.stdout)
        snapshots = json.loads(result.stdout)["snapshots"]
        assert [item["model_id"] for item in snapshots] == [103, 203, 203]
        example = subprocess.run([binary("examples/sunspec_inverter"), "127.0.0.1", str(server.port), "1"],
                                 capture_output=True, text=True, timeout=10)
        if example.returncode:
            raise SystemExit(example.stderr)
        print(example.stdout.strip())


if __name__ == "__main__":
    main()
