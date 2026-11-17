"""Loopback-only SunSpec fixture server, independent of the MoonBit decoder.

Register offsets and sizes come from the unmodified SunSpec JSON definitions.
This is a test/demo fixture, not a simulator of any manufacturer's equipment.
"""
import json
import socket
import socketserver
import struct
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "sunspec"


def model_block(model_id, values=None):
    points = json.loads((FIXTURES / f"model_{model_id}.json").read_text())["group"]["points"]
    registers, offsets = [], {}
    for point in points:
        offsets[point["name"]] = len(registers)
        size, kind = point["size"], point["type"]
        if kind in ("int16", "sunssf"):
            default = [0x8000]
        elif kind in ("uint16", "enum16", "pad"):
            default = [0xFFFF]
        elif kind == "acc32":
            default = [0, 0]
        elif kind == "string":
            default = [0] * size
        else:
            default = [0xFFFF] * size
        registers.extend(default)
    for name, value in dict(values or {}, ID=model_id, L=len(registers) - 2).items():
        point = next(p for p in points if p["name"] == name)
        offset, size = offsets[name], point["size"]
        if isinstance(value, str):
            data = value.encode("ascii").ljust(size * 2, b"\0")
            assert len(data) == size * 2, name
            registers[offset:offset + size] = struct.unpack(f">{size}H", data)
        else:
            registers[offset:offset + size] = [
                (value >> (16 * (size - i - 1))) & 0xFFFF for i in range(size)
            ]
    return registers, offsets


def demo_map(base=40000, second_meter=True):
    common, _ = model_block(1, {"Mn": "MoonPV fixture", "Md": "Virtual PV", "DA": 1})
    inverter, _ = model_block(103, {
        "PhVphA": 2301, "PhVphB": 2312, "PhVphC": 2298, "V_SF": -1,
        "W": 4200, "W_SF": 0, "Hz": 5000, "Hz_SF": -2,
    })
    meter_values = {
        "PhVphA": 2300, "PhVphB": 2310, "PhVphC": 2290, "V_SF": -1,
        "W": -1200, "W_SF": 0, "Hz": 5000, "Hz_SF": -2,
        "TotWhImp": 250000, "TotWhExp": 120000, "TotWh_SF": 0,
    }
    meter, _ = model_block(203, meter_values)
    blocks = [(1, common), (103, inverter), (203, meter)]
    if second_meter:
        other, _ = model_block(203, dict(meter_values, W=3000, TotWhImp=480000, TotWhExp=0))
        blocks.append((203, other))
    registers = [0x5375, 0x6E53]
    models = []
    for model_id, block in blocks:
        models.append((model_id, base + len(registers)))
        registers.extend(block)
    registers.extend([0xFFFF, 0])
    return {base + i: value for i, value in enumerate(registers)}, models


def receive_exactly(connection, length):
    result = bytearray()
    while len(result) < length:
        part = connection.recv(length - len(result))
        if not part:
            raise EOFError
        result.extend(part)
    return bytes(result)


class _Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    block_on_close = False


class _Handler(socketserver.BaseRequestHandler):
    def handle(self):
        owner = self.server.fixture
        self.request.settimeout(2)
        try:
            while not owner.stopped.is_set():
                header = receive_exactly(self.request, 7)
                transaction, protocol, length, unit = struct.unpack(">HHHB", header)
                if length != 6 or protocol != 0:
                    return
                pdu = receive_exactly(self.request, length - 1)
                function, address, count = struct.unpack(">BHH", pdu)
                with owner.lock:
                    owner.requests.append((function, address, count))
                if function not in (3, 4):
                    response = bytes([function | 0x80, 1])
                elif not 1 <= count <= 125:
                    response = bytes([function | 0x80, 3])
                elif any(address + i not in owner.registers for i in range(count)):
                    response = bytes([function | 0x80, 2])
                else:
                    data = struct.pack(f">{count}H", *(owner.registers[address + i] for i in range(count)))
                    response = bytes([function, len(data)]) + data
                frame = struct.pack(">HHHB", transaction, 0, len(response) + 1, unit) + response
                if owner.transform:
                    frame = owner.transform((function, address, count), frame)
                if frame is None:  # Deliberately silent peer for deadline tests.
                    owner.stopped.wait(5)
                    return
                if owner.fragment:
                    for byte in frame:
                        self.request.sendall(bytes([byte]))
                else:
                    self.request.sendall(frame)
                if owner.close_after_reply:
                    return
        except (EOFError, OSError):
            pass


class FixtureServer:
    def __init__(self, registers=None, *, transform=None, fragment=False, close_after_reply=False):
        self.registers = demo_map()[0] if registers is None else registers
        self.transform = transform
        self.fragment = fragment
        self.close_after_reply = close_after_reply
        self.stopped = threading.Event()
        self.lock = threading.Lock()
        self.requests = []

    def __enter__(self):
        self.server = _Server(("127.0.0.1", 0), _Handler)
        self.server.fixture = self
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stopped.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
