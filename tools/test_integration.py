"""CLI + real loopback TCP regressions. Run after a native release build."""
import json
import struct
import subprocess
import time
import unittest
from demo import binary, run_cli
from simulator import FixtureServer, demo_map, model_block


class Integration(unittest.TestCase):
    def read(self, server, *args):
        result = run_cli(server, *args, "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout)

    def rejected(self, server, *args, expected="", command="sunspec"):
        result = run_cli(server, *args, command=command)
        self.assertEqual(result.returncode, 1, (result.stdout, result.stderr))
        self.assertEqual(result.stdout, "", "failure must not emit a successful partial snapshot")
        self.assertIn(expected, result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_default_probe_fragmentation_and_all_instances(self):
        with FixtureServer(fragment=True) as server:
            data = self.read(server)
            self.assertEqual(data["schema_version"], 1)
            self.assertEqual(data["base_address"], 40000)
            self.assertEqual([m["id"] for m in data["models"]], [1, 103, 203, 203])
            self.assertEqual([s["address"] for s in data["snapshots"]], [40070, 40122, 40229])
            inverter, grid, other = [s["points"] for s in data["snapshots"]]
            self.assertEqual(inverter["voltage_b"]["value"], "231.2")
            self.assertEqual(inverter["frequency"]["value"], "50.00")
            self.assertEqual(grid["active_power"]["value"], "-1200")
            self.assertEqual(grid["voltage_c"]["value"], "229.0")
            self.assertEqual(other["exported_energy"]["status"], "not_accumulated")
            self.assertIsNone(other["exported_energy"]["value"])

    def test_explicit_base_and_second_meter(self):
        with FixtureServer() as server:
            data = self.read(server, 40000, "--model-address", 40229)
            self.assertEqual([s["address"] for s in data["snapshots"]], [40229])
            self.assertEqual(data["snapshots"][0]["points"]["active_power"]["value"], "3000")
            self.assertTrue(all(address >= 40000 for _, address, _ in server.requests))
            self.rejected(server, 40000, "--model-address", 40002, expected="no supported")

    def test_model_map_lists_instances_without_reading_measurements(self):
        registers, models = demo_map(base=50000)
        with FixtureServer(registers) as server:
            result = run_cli(server, 50000, "--json", command="models")
            self.assertEqual((result.returncode, result.stderr), (0, ""))
            inventory = json.loads(result.stdout)
            self.assertEqual(set(inventory), {"schema_version", "base_address", "models"})
            self.assertEqual((inventory["schema_version"], inventory["base_address"]), (1, 50000))
            self.assertEqual(inventory["models"], [
                {"id": model_id, "address": address, "length": registers[address + 1],
                 "snapshot_supported": model_id in (103, 203)} for model_id, address in models
            ])
            self.assertEqual(server.requests, [(3, address, 2) for address in
                             [50000, *(address for _, address in models), max(registers) - 1]])
            second_meter = inventory["models"][-1]["address"]
            self.assertEqual(self.read(server, 50000, "--model-address", second_meter)["snapshots"][0]
                             ["points"]["active_power"]["value"], "3000")

    def test_model_map_without_a_readable_snapshot(self):
        # Only headers are present. Include an unknown ID and a nonstandard 103.
        headers = {0: 0x5375, 1: 0x6E53, 2: 65000, 3: 4, 8: 103, 9: 49, 59: 0xFFFF, 60: 0}
        with FixtureServer(headers) as server:
            result = run_cli(server, 0, command="models")
            self.assertEqual((result.returncode, result.stderr), (0, ""))
            self.assertIn("Model 65000: address 2, length 4, snapshot: unsupported", result.stdout)
            self.assertIn("Model 103: address 8, length 49, snapshot: unsupported", result.stdout)
        with FixtureServer({0: 0x5375, 1: 0x6E53, 2: 0xFFFF, 3: 0}) as server:
            result = run_cli(server, 0, "--json", command="models")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["models"], [])
        del headers[60]
        with FixtureServer(headers) as server:
            self.rejected(server, 0, "--json", expected="model header at 59", command="models")

    def test_snapshot_reads_stop_at_last_required_point(self):
        registers, models = demo_map()
        expected_reads = []
        for model_id, address in models:
            if model_id in (103, 203):
                _, offsets = model_block(model_id)
                last = offsets["Hz_SF" if model_id == 103 else "TotWh_SF"]
                # Simulate a gateway that exposes only the part we consume.
                del registers[address + last + 1]
                expected_reads.append((3, address, last + 1))
        with FixtureServer(registers) as server:
            snapshots = self.read(server, 40000)["snapshots"]
            self.assertEqual([s["model_id"] for s in snapshots], [103, 203, 203])
            self.assertEqual(snapshots[0]["points"]["frequency"]["value"], "50.00")
            self.assertEqual(snapshots[1]["points"]["imported_energy"]["value"], "250000")
            self.assertEqual([req for req in server.requests if req[2] > 2], expected_reads)

    def test_accumulator_maximum_and_not_accumulated(self):
        registers, models = demo_map()
        address = models[2][1]
        _, offsets = model_block(203)
        for name, value in [("TotWhExp", 0xFFFFFFFF), ("TotWhImp", 0)]:
            registers[address + offsets[name]] = value >> 16
            registers[address + offsets[name] + 1] = value & 0xFFFF
        registers[address + offsets["TotWh_SF"]] = 0xFFFD
        with FixtureServer(registers) as server:
            points = self.read(server, 40000)["snapshots"][1]["points"]
            self.assertEqual(points["exported_energy"]["raw"], 4294967295)
            self.assertEqual(points["exported_energy"]["value"], "4294967.295")
            self.assertEqual(points["imported_energy"]["status"], "not_accumulated")
            self.assertIsNone(points["imported_energy"]["value"])

    def test_missing_measurement_and_scale_are_distinct(self):
        registers, models = demo_map()
        _, offsets = model_block(103)
        address = models[1][1]
        registers[address + offsets["PhVphA"]] = 0xFFFF
        registers[address + offsets["W_SF"]] = 0x8000
        with FixtureServer(registers) as server:
            points = self.read(server, 40000)["snapshots"][0]["points"]
            self.assertEqual(points["voltage_a"]["status"], "not_implemented")
            self.assertIsNone(points["voltage_a"]["raw"])
            self.assertEqual(points["active_power"]["status"], "scale_unavailable")
            self.assertEqual(points["active_power"]["raw"], 4200)
            self.assertIsNone(points["active_power"]["value"])

    def test_invalid_scales_are_errors(self):
        for value in (11, 0xFFF5):
            with self.subTest(value=value):
                registers, models = demo_map()
                registers[models[2][1] + 54] = value
                with FixtureServer(registers) as server:
                    self.rejected(server, 40000, expected="scale factor")

    def test_wrong_end_length_and_model_length(self):
        for kind in ("end", "inverter", "meter", "overflow", "zero"):
            with self.subTest(kind=kind):
                registers, models = demo_map()
                if kind == "end":
                    registers[max(registers)] = 1
                else:
                    start = models[1 if kind == "inverter" else 2][1]
                    length = {"inverter": 49, "meter": 104, "overflow": 65535, "zero": 0}[kind]
                    registers[start + 1] = length
                    if kind in ("inverter", "meter"):
                        registers[start + length + 2] = 0xFFFF
                        registers[start + length + 3] = 0
                with FixtureServer(registers) as server:
                    self.rejected(server, 40000)

    def test_64_models_accepted_and_65_rejected(self):
        for count in (64, 65):
            with self.subTest(count=count):
                inverter, _ = model_block(103, {"W": 1, "W_SF": 0})
                data = [0x5375, 0x6E53] + inverter + [65000, 1, 0] * (count - 1) + [0xFFFF, 0]
                with FixtureServer(dict(enumerate(data))) as server:
                    if count == 64:
                        self.assertEqual(len(self.read(server, 0)["models"]), 64)
                    else:
                        self.rejected(server, 0, expected="64-model")

    def test_missing_end_and_missing_marker(self):
        registers, _ = demo_map()
        del registers[max(registers)]
        with FixtureServer(registers) as server:
            self.rejected(server, 40000, expected="could not read SunSpec model header")
        with FixtureServer({0: 0, 1: 0}) as server:
            self.rejected(server, 0, expected="marker was not found")

    def test_device_exception_preserved_no_partial_output(self):
        def exception(request, frame):
            if request[1] == 40122 and request[2] > 2:
                return frame[:4] + b"\x00\x03" + frame[6:7] + b"\x83\x04"
            return frame
        with FixtureServer(transform=exception) as server:
            self.rejected(server, 40000, expected="Modbus exception 4")
        with FixtureServer(transform=lambda req, frame: frame[:4] + b"\x00\x03" + frame[6:7] + b"\x83\x04") as server:
            self.rejected(server, expected="probe at 0 failed: Modbus exception 4")
            self.assertEqual(len(server.requests), 1)

    def test_malformed_responses(self):
        mutations = {
            "transaction": lambda f: b"\xff\xff" + f[2:],
            "protocol": lambda f: f[:2] + b"\x00\x01" + f[4:],
            "unit": lambda f: f[:6] + b"\x02" + f[7:],
            "length_too_large": lambda f: f[:4] + b"\x00\xff" + f[6:],
            "length_too_short": lambda f: f[:4] + b"\x00\x01" + f[6:],
            "function": lambda f: f[:7] + b"\x04" + f[8:],
            "byte_count": lambda f: f[:8] + b"\x02" + f[9:],
            "truncated": lambda f: f[:-1],
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), FixtureServer(transform=lambda req, frame: mutation(frame), close_after_reply=True) as server:
                self.rejected(server, 40000, "--timeout-ms", 500)

    def test_timeout_and_connection_refused(self):
        with FixtureServer(transform=lambda req, frame: None) as server:
            start = time.monotonic()
            self.rejected(server, 40000, "--timeout-ms", 100, expected="timed out")
            self.assertLess(time.monotonic() - start, 3)
        # The context closed the listening socket; use that known unused port.
        self.rejected(server, 40000, "--timeout-ms", 200, expected="connect")

    def test_invalid_arguments_do_not_open_tcp(self):
        with FixtureServer() as server:
            for tail in (("--unknown",), ("--timeout-ms", "0"), ("65533",), ("--model-address", "-1")):
                with self.subTest(tail=tail):
                    result = run_cli(server, *tail)
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, "")
                    self.assertTrue(result.stderr.startswith("error:"))
            self.assertEqual(server.requests, [])
        result = subprocess.run([binary(), "--help"], text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_raw_register_commands_and_example(self):
        with FixtureServer() as server:
            for command in ("read-holding", "read-input"):
                result = run_cli(server, 40000, 2, "--json", command=command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["registers"], [0x5375, 0x6E53])
            result = subprocess.run([binary("examples/sunspec_inverter"), "127.0.0.1", str(server.port), "1"], text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "Inverter active power: 4200 W")


if __name__ == "__main__":
    unittest.main(verbosity=2)
