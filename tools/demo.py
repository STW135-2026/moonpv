"""Build and run MoonPV against a local fixture; no device or Python packages needed."""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from simulator import FixtureServer, ROOT


def binary(package="cmd/main"):
    bundled = {
        "cmd/main": "moonpv",
        "examples/sunspec_inverter": "moonpv-example",
    }
    if (ROOT / "BUILD.json").is_file():
        path = ROOT / "bin" / (bundled[package] + (".exe" if os.name == "nt" else ""))
        if not path.is_file():
            raise FileNotFoundError(f"Missing bundled program: {path}; extract the full archive again")
        return str(path)
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
    parser.add_argument("--json", action="store_true", help="print the verified CLI JSON instead of a summary")
    args = parser.parse_args()
    if not args.no_build and not (ROOT / "BUILD.json").is_file():
        subprocess.run(["moon", "build", "--target", "native", "--release"], cwd=ROOT, check=True,
                       stdout=sys.stderr)
    with FixtureServer() as server:
        result = run_cli(server, "--json")
        if result.returncode:
            raise SystemExit(result.stderr)
        data = json.loads(result.stdout)
        snapshots = data["snapshots"]
        if data["schema_version"] != 1 or [
            (item["model_id"], item["address"]) for item in snapshots
        ] != [(103, 40070), (203, 40122), (203, 40229)]:
            raise ValueError("Unexpected model discovery result")
        expected = [
            {"active_power": "4200", "voltage_a": "230.1", "frequency": "50.00"},
            {"active_power": "-1200", "imported_energy": "250000", "exported_energy": "120000"},
            {"active_power": "3000", "imported_energy": "480000"},
        ]
        for snapshot, values in zip(snapshots, expected):
            for name, value in values.items():
                point = snapshot["points"][name]
                if point["value"] != value or point["status"] != "ok":
                    raise ValueError(f"Unexpected {name} at model address {snapshot['address']}")
        energy = snapshots[2]["points"]["exported_energy"]
        if energy["status"] != "not_accumulated" or energy["value"] is not None:
            raise ValueError("Zero accumulator must be reported as not_accumulated")
        example = subprocess.run([binary("examples/sunspec_inverter"), "127.0.0.1", str(server.port), "1"],
                                 capture_output=True, text=True, encoding="utf-8", timeout=10)
        if example.returncode:
            raise SystemExit(example.stderr)
        if result.stderr or example.stderr or example.stdout.strip() != "Inverter active power: 4200 W":
            raise ValueError("Unexpected API example output or error output")
        if args.json:
            print(result.stdout.strip())
        else:
            print("Local simulated PV site (not a real-device measurement):")
            print("Model  Address  Active power  A-phase voltage")
            for snapshot in snapshots:
                points = snapshot["points"]
                print(f"{snapshot['model_id']:<6} {snapshot['address']:<8} "
                      f"{points['active_power']['value'] + ' W':<13} {points['voltage_a']['value']} V")
            print("Meter 40122: imported 250000 Wh; exported 120000 Wh")
            print("Meter 40229: imported 480000 Wh; exported not_accumulated")
            print("API example: " + example.stdout.strip())
            print("PASS: discovery, readings, accumulator status and API example")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        raise SystemExit(f"Demo failed: {error}") from None
