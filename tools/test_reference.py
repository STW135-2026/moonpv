"""Compare MoonPV with SunSpec Alliance pysunspec2 on the same TCP fixture."""
import json
import unittest
from decimal import Decimal
from importlib.metadata import version
from sunspec2.modbus.client import SunSpecModbusClientDeviceTCP
from demo import run_cli
from simulator import FixtureServer, demo_map, model_block

POINTS = {
    "voltage_a": "PhVphA", "voltage_b": "PhVphB", "voltage_c": "PhVphC",
    "active_power": "W", "frequency": "Hz",
    "imported_energy": "TotWhImp", "exported_energy": "TotWhExp",
}


class Reference(unittest.TestCase):
    def compare(self, registers):
        with FixtureServer(registers) as server:
            reference = SunSpecModbusClientDeviceTCP(ipaddr="127.0.0.1", ipport=server.port, slave_id=1, timeout=2)
            try:
                reference.scan()
                actual = run_cli(server, "--json")
                self.assertEqual(actual.returncode, 0, actual.stderr)
                output = json.loads(actual.stdout)
                models = {m.model_addr: m for model_id in (103, 203) for m in reference.models[model_id]}
                self.assertEqual(set(models), {s["address"] for s in output["snapshots"]})
                for snapshot in output["snapshots"]:
                    model = models[snapshot["address"]]
                    model.read()
                    for name, point in snapshot["points"].items():
                        expected = getattr(model, POINTS[name])
                        with self.subTest(address=snapshot["address"], point=name):
                            if point["status"] == "not_accumulated":
                                self.assertIsNone(expected.value)
                                self.assertIsNone(point["value"])
                            else:
                                self.assertEqual(point["raw"], expected.value)
                                if point["value"] is None:
                                    self.assertIsNone(expected.cvalue)
                                else:
                                    self.assertEqual(Decimal(point["value"]), Decimal(str(expected.cvalue)))
            finally:
                reference.close()

    def test_normal_inverter_and_two_meters(self):
        self.compare(demo_map()[0])

    def test_acc32_maximum_and_missing_signed_unsigned_values(self):
        registers, models = demo_map()
        _, inverter = model_block(103)
        _, meter = model_block(203)
        registers[models[1][1] + inverter["PhVphA"]] = 0xFFFF
        registers[models[2][1] + meter["PhVphB"]] = 0x8000
        start = models[2][1]
        registers[start + meter["TotWhExp"]] = 0xFFFF
        registers[start + meter["TotWhExp"] + 1] = 0xFFFF
        registers[start + meter["TotWh_SF"]] = 0xFFFD
        self.compare(registers)


if __name__ == "__main__":
    print("Independent reference: pysunspec2 " + version("pysunspec2"))
    unittest.main(verbosity=2)
