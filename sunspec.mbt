///|
/// A model block advertised by a SunSpec device. Addresses are Modbus PDU
/// addresses (zero-based), as sent on the wire.
pub struct SunSpecModel {
  id : Int32
  start_address : Int32
  length : Int32
}

///|
/// A SunSpec device map found at a holding-register base address.
pub struct SunSpecDevice {
  base_address : Int32
  models : Array[SunSpecModel]
}

///|
/// The commonly used live points from SunSpec three-phase inverter Model 103.
/// Values remain raw integers with their scale factors so no precision is lost.
pub struct Inverter103Snapshot {
  phase_voltage_a : Int32?
  phase_voltage_b : Int32?
  phase_voltage_c : Int32?
  voltage_scale_factor : Int32?
  active_power : Int32?
  active_power_scale_factor : Int32?
  frequency : Int32?
  frequency_scale_factor : Int32?
}

///|
/// Live and accumulated points from SunSpec three-phase meter Model 203.
pub struct Meter203Snapshot {
  phase_voltage_a : Int32?
  voltage_scale_factor : Int32?
  active_power : Int32?
  active_power_scale_factor : Int32?
  frequency : Int32?
  frequency_scale_factor : Int32?
  imported_energy : Int64?
  exported_energy : Int64?
  energy_scale_factor : Int32?
}

///|
/// Find the SunSpec map at one of the supplied holding-register addresses.
/// Common bases are 0, 40000 and 50000; pass only the device's documented base
/// to avoid probing registers unnecessarily.
pub async fn Client::discover_sunspec(
  self : Client,
  candidates : Array[Int32],
) -> Result[SunSpecDevice, String] {
  for base in candidates {
    if base < 0 || base > 65533 {
      continue
    }
    match self.read_holding_registers(base, 2) {
      Ok(marker) =>
        if marker[0] == 0x5375 && marker[1] == 0x6E53 {
          return scan_sunspec_models(self, base)
        }
      Err(_) => continue
    }
  }
  Err("SunSpec marker was not found at the supplied base addresses")
}

///|
/// Read and decode the standard live points in a three-phase inverter Model 103.
pub async fn Client::read_inverter_103(
  self : Client,
  device : SunSpecDevice,
) -> Result[Inverter103Snapshot, String] {
  for model in device.models {
    if model.id == 103 {
      if model.length < 50 {
        return Err(
          "SunSpec Model 103 is shorter than the standard 50-register layout",
        )
      }
      let values = match
        self.read_holding_registers(model.start_address, model.length + 2) {
        Ok(values) => values
        Err(message) => return Err(message)
      }
      if values[0] != 103 || values[1] != model.length {
        return Err("SunSpec Model 103 header changed after discovery")
      }
      return Ok({
        phase_voltage_a: sunspec_u16(values[10]),
        phase_voltage_b: sunspec_u16(values[11]),
        phase_voltage_c: sunspec_u16(values[12]),
        voltage_scale_factor: sunspec_i16_option(values[13]),
        active_power: sunspec_i16_option(values[14]),
        active_power_scale_factor: sunspec_i16_option(values[15]),
        frequency: sunspec_u16(values[16]),
        frequency_scale_factor: sunspec_i16_option(values[17]),
      })
    }
  }
  Err("SunSpec device does not advertise Model 103")
}

///|
/// Read selected live and accumulated points from SunSpec three-phase Meter Model 203.
pub async fn Client::read_meter_203(
  self : Client,
  device : SunSpecDevice,
) -> Result[Meter203Snapshot, String] {
  for model in device.models {
    if model.id == 203 {
      if model.length < 105 {
        return Err(
          "SunSpec Model 203 is shorter than the standard 105-register layout",
        )
      }
      let values = match
        self.read_holding_registers(model.start_address, model.length + 2) {
        Ok(values) => values
        Err(message) => return Err(message)
      }
      if values[0] != 203 || values[1] != model.length {
        return Err("SunSpec Model 203 header changed after discovery")
      }
      return Ok({
        phase_voltage_a: sunspec_i16_option(values[8]),
        voltage_scale_factor: sunspec_i16_option(values[15]),
        frequency: sunspec_i16_option(values[16]),
        frequency_scale_factor: sunspec_i16_option(values[17]),
        active_power: sunspec_i16_option(values[18]),
        active_power_scale_factor: sunspec_i16_option(values[22]),
        exported_energy: sunspec_u32(values[38], values[39]),
        imported_energy: sunspec_u32(values[46], values[47]),
        energy_scale_factor: sunspec_i16_option(values[54]),
      })
    }
  }
  Err("SunSpec device does not advertise Model 203")
}

///|
async fn scan_sunspec_models(
  client : Client,
  base : Int32,
) -> Result[SunSpecDevice, String] {
  let mut address = base + 2
  let models : Array[SunSpecModel] = []
  for _ in 0..<64 {
    if address > 65534 {
      return Err("SunSpec model chain runs beyond the Modbus address space")
    }
    let header = match client.read_holding_registers(address, 2) {
      Ok(header) => header
      Err(message) =>
        return Err("could not read SunSpec model header: " + message)
    }
    let id = header[0]
    let length = header[1]
    if id == 0xFFFF {
      return Ok({ base_address: base, models, })
    }
    if length < 1 || address + length + 2 > 65536 {
      return Err("SunSpec model has an invalid length or address range")
    }
    models.push({ id, start_address: address, length, })
    address = address + length + 2
  }
  Err("SunSpec model chain exceeded the 64-model safety limit")
}

///|
fn sunspec_u16(value : Int32) -> Int32? {
  if value == 0xFFFF {
    None
  } else {
    Some(value)
  }
}

///|
fn sunspec_i16(value : Int32) -> Int32 {
  if value >= 0x8000 {
    value - 65536
  } else {
    value
  }
}

///|
fn sunspec_i16_option(value : Int32) -> Int32? {
  if value == 0x8000 {
    None
  } else {
    Some(sunspec_i16(value))
  }
}

///|
fn sunspec_u32(high : Int32, low : Int32) -> Int64? {
  if high == 0xFFFF && low == 0xFFFF {
    None
  } else {
    Some((high.to_int64() << 16) | low.to_int64())
  }
}
